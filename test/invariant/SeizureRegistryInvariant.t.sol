/**
 * Copyright 2026 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
pragma solidity 0.8.35;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";
import {MasterMinter} from "test/mocks/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "test/mocks/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "test/mocks/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployMockFiatToken} from "test/util/DeployMockFiatToken.sol";

// ============ Handler ============

/// @dev Foundry invariant handler. Exposes action functions that Foundry calls in random sequences.
///      Maintains ghost state that mirrors the expected contract state so invariant functions can
///      assert correctness without reading unbounded on-chain mappings.
contract SeizureRegistryHandler is Test {
    uint256 internal constant _MAX_BALANCE = type(uint64).max;

    // Contract under test
    SeizureRegistry internal _registry;
    FiatTokenV2_2 internal _token;
    MasterMinter internal _masterMinter;
    address internal _masterMinterOwner;

    // Tracked role holders (handler keeps these current when it rotates roles)
    address internal _owner;
    address internal _currentSecondaryMarketBurner;
    address internal _currentHashUpdater;
    address internal _currentAddressManager;

    // Fixed recipient pool — always allowlisted; never removed in this handler so burn actions
    // reliably succeed without extra setup. The allowlist-consistency invariant is verified by
    // checking stored remintRecipient values against this pool.
    address[] internal _recipientPool;

    // Ghost state — mirrors what should be in contract storage
    bytes[] internal _ghostSecondaryMarketBurnedAddrs;
    uint32[] internal _ghostDomains;
    address[] internal _ghostRecipients;
    bytes32[] internal _ghostTxHashes;
    uint256[] internal _ghostBalances;
    mapping(uint32 => uint256) internal _ghostDomainTotals;
    uint32[] internal _ghostTouchedDomains;
    mapping(uint32 => bool) internal _ghostDomainSeen;

    constructor(
        SeizureRegistry registry,
        FiatTokenV2_2 token,
        MasterMinter masterMinter,
        address masterMinterOwner,
        address owner,
        address initialSecondaryMarketBurner,
        address initialHashUpdater,
        address initialAddressManager
    ) {
        _registry = registry;
        _token = token;
        _masterMinter = masterMinter;
        _masterMinterOwner = masterMinterOwner;
        _owner = owner;
        _currentSecondaryMarketBurner = initialSecondaryMarketBurner;
        _currentHashUpdater = initialHashUpdater;
        _currentAddressManager = initialAddressManager;

        // Seed recipient pool with 5 named addresses and allowlist all of them
        for (uint256 i = 0; i < 5; i++) {
            address r = makeAddr(string(abi.encodePacked("recipient", i)));
            _recipientPool.push(r);
            vm.prank(_currentAddressManager);
            _registry.addAllowedRecipient(r);
        }
    }

    // ============ Ghost state accessors (for invariant assertions) ============

    function secondaryMarketBurnedPairsCount() external view returns (uint256) {
        return _ghostSecondaryMarketBurnedAddrs.length;
    }

    function secondaryMarketBurnedPair(uint256 i) external view returns (bytes memory addr, uint32 domain) {
        return (_ghostSecondaryMarketBurnedAddrs[i], _ghostDomains[i]);
    }

    function ghostRecipient(uint256 i) external view returns (address) {
        return _ghostRecipients[i];
    }

    function ghostTxHash(uint256 i) external view returns (bytes32) {
        return _ghostTxHashes[i];
    }

    function ghostBalance(uint256 i) external view returns (uint256) {
        return _ghostBalances[i];
    }

    function touchedDomainsCount() external view returns (uint256) {
        return _ghostTouchedDomains.length;
    }

    function touchedDomain(uint256 i) external view returns (uint32) {
        return _ghostTouchedDomains[i];
    }

    function ghostDomainTotal(uint32 domain) external view returns (uint256) {
        return _ghostDomainTotals[domain];
    }

    function recipientPool(uint256 i) external view returns (address) {
        return _recipientPool[i];
    }

    // ============ Actions ============

    /// @dev SecondaryMarketBurns a new (addr, domain) pair. Skips if that pair was already burned.
    function act_secondaryMarketBurn(bytes calldata addr, uint32 domain, uint256 balance, uint256 recipientSeed)
        external
    {
        if (addr.length == 0 || addr.length > 64) return;
        balance = bound(balance, 1, _MAX_BALANCE);

        // Skip if already burned — AlreadySecondaryMarketBurned would revert and confuse ghost state
        if (_registry.isSecondaryMarketBurned(addr, domain)) return;

        address recipient = _recipientPool[recipientSeed % _recipientPool.length];

        vm.prank(_masterMinterOwner);
        _masterMinter.incrementMinterAllowance(balance);

        vm.prank(_currentSecondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(addr, domain, balance, recipient);

        // Update ghost state
        _ghostSecondaryMarketBurnedAddrs.push(addr);
        _ghostDomains.push(domain);
        _ghostRecipients.push(recipient);
        _ghostTxHashes.push(bytes32(0));
        _ghostBalances.push(balance);
        _ghostDomainTotals[domain] += balance;
        if (!_ghostDomainSeen[domain]) {
            _ghostDomainSeen[domain] = true;
            _ghostTouchedDomains.push(domain);
        }
    }

    /// @dev Sets a remint tx hash for a previously secondaryMarketBurned pair.
    function act_setRemintTxHash(uint256 pairIdxSeed, bytes32 txHash) external {
        if (_ghostSecondaryMarketBurnedAddrs.length == 0) return;
        if (txHash == bytes32(0)) return;

        uint256 idx = pairIdxSeed % _ghostSecondaryMarketBurnedAddrs.length;
        bytes memory addr = _ghostSecondaryMarketBurnedAddrs[idx];
        uint32 domain = _ghostDomains[idx];

        vm.prank(_currentHashUpdater);
        _registry.setRemintTxHash(addr, domain, txHash);

        _ghostTxHashes[idx] = txHash;
    }

    /// @dev Adds a new allowed recipient via the current addressManager, expanding the burn recipient pool.
    ///      Exercises the allowlist-add path under arbitrary manager rotation sequences.
    ///      Skips blacklisted addresses — FiatToken rejects mints to them, which would cause
    ///      act_secondaryMarketBurn to revert unexpectedly when picking from the pool.
    function act_addAllowedRecipient(address r) external {
        if (r == address(0)) return;
        if (_token.isBlacklisted(r)) return;

        vm.prank(_currentAddressManager);
        _registry.addAllowedRecipient(r);
        _recipientPool.push(r);
    }

    /// @dev Rotates the SecondaryMarketBurner to a new non-zero address.
    function act_rotateSecondaryMarketBurner(address newBurner) external {
        if (newBurner == address(0)) return;

        vm.prank(_owner);
        _registry.updateSecondaryMarketBurner(newBurner);
        _currentSecondaryMarketBurner = newBurner;
    }

    /// @dev Rotates the HashUpdater to a new non-zero address.
    function act_rotateHashUpdater(address newUpdater) external {
        if (newUpdater == address(0)) return;

        vm.prank(_owner);
        _registry.updateHashUpdater(newUpdater);
        _currentHashUpdater = newUpdater;
    }

    /// @dev Rotates the AddressManager to a new non-zero address.
    ///      Existing allowlist entries are unaffected — the role only gates future modifications.
    function act_rotateAddressManager(address newManager) external {
        if (newManager == address(0)) return;

        vm.prank(_owner);
        _registry.updateAddressManager(newManager);
        _currentAddressManager = newManager;
    }
}

// ============ Invariant Test ============

contract SeizureRegistryInvariantTest is StdInvariant, Test {
    SeizureRegistry internal _registry;
    FiatTokenV2_2 internal _token;
    MasterMinter internal _masterMinter;
    SeizureRegistryHandler internal _handler;

    address internal _owner = makeAddr("owner");
    address internal _secondaryMarketBurner = makeAddr("secondaryMarketBurner");
    address internal _hashUpdater = makeAddr("hashUpdater");
    address internal _rescuer = makeAddr("rescuer");
    address internal _addressManager = makeAddr("addressManager");

    function setUp() public {
        DeployMockFiatToken usdc = new DeployMockFiatToken();
        FiatTokenProxy proxy;
        (, _masterMinter, proxy) = usdc.deploy();
        _token = FiatTokenV2_2(address(proxy));

        address impl = address(new SeizureRegistry(address(_token)));
        UpgradeablePlaceholder placeholder = new UpgradeablePlaceholder();
        ERC1967Proxy registryProxy =
            new ERC1967Proxy(address(placeholder), abi.encodeCall(UpgradeablePlaceholder.initialize, (address(this))));
        UpgradeablePlaceholder(address(registryProxy))
            .upgradeToAndCall(
                impl,
                abi.encodeCall(
                    SeizureRegistry.initialize, (_secondaryMarketBurner, _hashUpdater, _rescuer, _addressManager)
                )
            );
        _registry = SeizureRegistry(address(registryProxy));

        _registry.transferOwnership(_owner);
        vm.prank(_owner);
        _registry.acceptOwnership();

        vm.startPrank(usdc.masterMinterOwner());
        _masterMinter.configureController(usdc.masterMinterOwner(), address(_registry));
        _masterMinter.configureMinter(0);
        vm.stopPrank();

        _handler = new SeizureRegistryHandler(
            _registry,
            _token,
            _masterMinter,
            usdc.masterMinterOwner(),
            _owner,
            _secondaryMarketBurner,
            _hashUpdater,
            _addressManager
        );

        targetContract(address(_handler));
    }

    // ============ Invariant 1: Supply counter consistency ============
    // totalSecondaryMarketBurnedAmount()
    //   == Sum of totalSecondaryMarketBurnedAmount(domain) for all touched domains
    //   == Sum of secondaryMarketBurnedBalance(addr, domain) for all individual pairs

    function invariant_supplyCounterConsistency() external view {
        uint256 domainSum = 0;
        uint256 n = _handler.touchedDomainsCount();
        for (uint256 i = 0; i < n; i++) {
            uint32 domain = _handler.touchedDomain(i);
            domainSum += _registry.totalSecondaryMarketBurnedAmount(domain);
        }
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(), domainSum, "Invariant: global total != sum of domain totals"
        );
        for (uint256 i = 0; i < n; i++) {
            uint32 domain = _handler.touchedDomain(i);
            assertEq(
                _registry.totalSecondaryMarketBurnedAmount(domain),
                _handler.ghostDomainTotal(domain),
                "Invariant: per-domain total != ghost-tracked total"
            );
        }

        // Third layer: global total == sum of every individual SMB balance.
        // Catches bugs where domain/global counters are correct but individual records are wrong.
        uint256 balanceSum = 0;
        uint256 m = _handler.secondaryMarketBurnedPairsCount();
        for (uint256 i = 0; i < m; i++) {
            (bytes memory addr, uint32 domain) = _handler.secondaryMarketBurnedPair(i);
            balanceSum += _registry.secondaryMarketBurnedBalance(addr, domain);
        }
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(),
            balanceSum,
            "Invariant: global total != sum of individual SMB balances"
        );
    }

    // ============ Invariant 2: Balance-as-truth ============
    // isSecondaryMarketBurned(addr, domain) <==> secondaryMarketBurnedBalance(addr, domain) > 0
    // Verified for every ghost-tracked burned pair (true side) and spot-checked for untouched pairs (false side).

    function invariant_balanceAsTruth() external view {
        uint256 n = _handler.secondaryMarketBurnedPairsCount();
        for (uint256 i = 0; i < n; i++) {
            (bytes memory addr, uint32 domain) = _handler.secondaryMarketBurnedPair(i);
            assertTrue(
                _registry.isSecondaryMarketBurned(addr, domain),
                "Invariant: SecondaryMarketBurned balance is > 0 but isSecondaryMarketBurned is false"
            );
            assertGt(
                _registry.secondaryMarketBurnedBalance(addr, domain),
                0,
                "Invariant: isSecondaryMarketBurned is true but SecondaryMarketBurned balance is 0"
            );
        }
        // Spot-check: a never-secondaryMarketBurned address/domain returns false and zero.
        bytes memory neverBurned = abi.encodePacked(keccak256("never_burned_sentinel"));
        assertFalse(_registry.isSecondaryMarketBurned(neverBurned, type(uint32).max));
        assertEq(_registry.secondaryMarketBurnedBalance(neverBurned, type(uint32).max), 0);
    }

    // ============ Invariant 3: RemintRecipient integrity ============
    // The remintRecipient stored on-chain for every secondaryMarketBurned pair must match what the handler recorded at burn time.

    function invariant_remintRecipientIntegrity() external view {
        uint256 n = _handler.secondaryMarketBurnedPairsCount();
        for (uint256 i = 0; i < n; i++) {
            (bytes memory addr, uint32 domain) = _handler.secondaryMarketBurnedPair(i);
            (,,, address storedRecipient,) = _registry.getSecondaryMarketBurnRecord(addr, domain);
            assertEq(
                storedRecipient,
                _handler.ghostRecipient(i),
                "Invariant: stored remintRecipient does not match ghost-tracked recipient"
            );
        }
    }

    // ============ Invariant 4: RemintTxHash integrity ============
    // The remintTxHash stored on-chain for every burned pair must match the last hash the handler set.
    // Pairs that have never had a hash set must return bytes32(0).

    function invariant_remintTxHashIntegrity() external view {
        uint256 n = _handler.secondaryMarketBurnedPairsCount();
        for (uint256 i = 0; i < n; i++) {
            (bytes memory addr, uint32 domain) = _handler.secondaryMarketBurnedPair(i);
            (,,,, bytes32 storedHash) = _registry.getSecondaryMarketBurnRecord(addr, domain);
            assertEq(
                storedHash, _handler.ghostTxHash(i), "Invariant: stored remintTxHash does not match ghost-tracked hash"
            );
        }
    }

    // ============ Invariant 5: SecondaryMarketBurns are permanent and non-rewritable ============
    // Once secondaryMarketBurned, a pair's balance is immutable — no subsequent call sequence
    // can clear, overwrite, or re-SMB it. The stored balance must equal exactly what was
    // recorded by the handler at SMB time for every pair, across every call sequence.

    function invariant_burnIsPermanent() external view {
        uint256 n = _handler.secondaryMarketBurnedPairsCount();
        for (uint256 i = 0; i < n; i++) {
            (bytes memory addr, uint32 domain) = _handler.secondaryMarketBurnedPair(i);
            assertEq(
                _registry.secondaryMarketBurnedBalance(addr, domain),
                _handler.ghostBalance(i),
                "Invariant: stored SMB balance changed after initial burn"
            );
            assertTrue(
                _registry.isSecondaryMarketBurned(addr, domain),
                "Invariant: isSecondaryMarketBurned became false after being set"
            );
        }
    }
}

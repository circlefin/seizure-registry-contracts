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
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";
import {MasterMinter} from "test/mocks/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "test/mocks/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "test/mocks/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployMockFiatToken} from "test/util/DeployMockFiatToken.sol";
import {SeizureRegistryV2Stub} from "test/mocks/SeizureRegistryV2Stub.sol";

/// @notice Authoritative upgrade safety test for SeizureRegistry.
///         Covers two upgrade scenarios:
///           A. Storage-compatible upgrade to a new impl with a different TOKEN address.
///           B. State-adding upgrade via reinitializer(3) using SeizureRegistryV2Stub.
///         Both scenarios assert that all pre-upgrade SMB records and roles survive the upgrade.
contract UpgradeIntegrationTest is Test {
    // EIP-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Old FiatToken stack (V1 registry points here)
    DeployMockFiatToken private _usdc1;
    FiatTokenV2_2 internal _oldToken;
    MasterMinter internal _oldMasterMinter;

    // New FiatToken stack (used after the different-TOKEN upgrade in Scenario A)
    DeployMockFiatToken private _usdc2;
    FiatTokenV2_2 internal _newToken;
    MasterMinter internal _newMasterMinter;

    SeizureRegistry internal _registry;

    address internal _owner = makeAddr("owner");
    address internal _secondaryMarketBurner = makeAddr("secondaryMarketBurner");
    address internal _hashUpdater = makeAddr("hashUpdater");
    address internal _rescuer = makeAddr("rescuer");
    address internal _addressManager = makeAddr("addressManager");

    // Burned addresses and domains used across tests
    bytes internal constant _BURNED_ADDR_1 = abi.encodePacked(address(0xbeef));
    bytes internal constant _BURNED_ADDR_2 = abi.encodePacked(address(0xcafe));
    bytes internal constant _BURNED_ADDR_3 = abi.encodePacked(address(0xdead));
    uint32 internal constant _DOMAIN_1 = 1;
    uint32 internal constant _DOMAIN_2 = 2;

    // SMB amounts for Scenario A (three pre-upgrade burns across two domains)
    uint256 internal constant _SMB_AMOUNT_1 = 100e6;
    uint256 internal constant _SMB_AMOUNT_2 = 200e6;
    uint256 internal constant _SMB_AMOUNT_3 = 300e6;

    address internal _le1 = makeAddr("le1");
    address internal _le2 = makeAddr("le2");

    function setUp() public {
        // Deploy old FiatToken ecosystem (V1 registry mints here)
        _usdc1 = new DeployMockFiatToken();
        FiatTokenProxy proxy1;
        (, _oldMasterMinter, proxy1) = _usdc1.deploy();
        _oldToken = FiatTokenV2_2(address(proxy1));

        // Deploy new FiatToken ecosystem (registry mints here after the TOKEN upgrade)
        _usdc2 = new DeployMockFiatToken();
        FiatTokenProxy proxy2;
        (, _newMasterMinter, proxy2) = _usdc2.deploy();
        _newToken = FiatTokenV2_2(address(proxy2));

        // Deploy SeizureRegistry V1 pointing at _oldToken
        address impl = address(new SeizureRegistry(address(_oldToken)));
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

        // Wire registry as minter on old token
        vm.startPrank(_usdc1.masterMinterOwner());
        _oldMasterMinter.configureController(_usdc1.masterMinterOwner(), address(_registry));
        _oldMasterMinter.configureMinter(0);
        vm.stopPrank();

        // Pre-wire registry as minter on new token (ready to use immediately after upgrade)
        vm.startPrank(_usdc2.masterMinterOwner());
        _newMasterMinter.configureController(_usdc2.masterMinterOwner(), address(_registry));
        _newMasterMinter.configureMinter(0);
        vm.stopPrank();

        // Allowlist recipients
        vm.startPrank(_addressManager);
        _registry.addAllowedRecipient(_le1);
        _registry.addAllowedRecipient(_le2);
        vm.stopPrank();
    }

    // ============ Helpers ============

    function _grantOldMinterAllowance(uint256 amount) internal {
        vm.prank(_usdc1.masterMinterOwner());
        _oldMasterMinter.incrementMinterAllowance(amount);
    }

    function _grantNewMinterAllowance(uint256 amount) internal {
        vm.prank(_usdc2.masterMinterOwner());
        _newMasterMinter.incrementMinterAllowance(amount);
    }

    function _doSMB(bytes memory burnedAddr, uint32 domain, uint256 balance, address recipient) internal {
        vm.prank(_secondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(burnedAddr, domain, balance, recipient);
    }

    // ============ Scenario A: storage-compatible upgrade with different TOKEN ============

    /// @notice Upgrades to a new impl with a different TOKEN immutable. Asserts all three pre-upgrade
    ///         SMB records (across 2 domains) survive the upgrade unchanged, the ERC-1967 impl slot
    ///         is updated, and all roles/ownership are preserved.
    function test_upgrade_differentToken_preservesAllState() public {
        // Pre-upgrade: 3 SMBs across 2 domains
        _grantOldMinterAllowance(_SMB_AMOUNT_1);
        _doSMB(_BURNED_ADDR_1, _DOMAIN_1, _SMB_AMOUNT_1, _le1);

        _grantOldMinterAllowance(_SMB_AMOUNT_2);
        _doSMB(_BURNED_ADDR_2, _DOMAIN_1, _SMB_AMOUNT_2, _le1);

        _grantOldMinterAllowance(_SMB_AMOUNT_3);
        _doSMB(_BURNED_ADDR_1, _DOMAIN_2, _SMB_AMOUNT_3, _le2);

        uint256 oldTokenSupplyBeforeUpgrade = _oldToken.totalSupply();
        assertEq(
            oldTokenSupplyBeforeUpgrade,
            _SMB_AMOUNT_1 + _SMB_AMOUNT_2 + _SMB_AMOUNT_3,
            "oldTokenSupplyBeforeUpgrade should be 600e6"
        );

        // Deploy new impl pointing at _newToken; upgrade with empty initData
        address newImpl = address(new SeizureRegistry(address(_newToken)));
        vm.prank(_owner);
        _registry.upgradeToAndCall(newImpl, "");

        // Impl slot updated
        address storedImpl = address(uint160(uint256(vm.load(address(_registry), _ERC1967_IMPL_SLOT))));
        assertEq(storedImpl, newImpl, "ERC-1967 impl slot should point at new impl");

        // TOKEN immutable updated to newToken
        assertEq(address(_registry.TOKEN()), address(_newToken), "TOKEN should be updated to newToken");

        // SMB records preserved
        assertTrue(
            _registry.isSecondaryMarketBurned(_BURNED_ADDR_1, _DOMAIN_1),
            "Burned address 1 in domain 1 record should be preserved"
        );
        assertTrue(
            _registry.isSecondaryMarketBurned(_BURNED_ADDR_2, _DOMAIN_1),
            "Burned address 2 in domain 1 record should be preserved"
        );
        assertTrue(
            _registry.isSecondaryMarketBurned(_BURNED_ADDR_1, _DOMAIN_2),
            "Burned address 1 in domain 2 record should be preserved"
        );
        assertFalse(
            _registry.isSecondaryMarketBurned(_BURNED_ADDR_3, _DOMAIN_1),
            "Burned address 3 in domain 1 record should not be SMB'd"
        );

        // Supply counters preserved
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(),
            _SMB_AMOUNT_1 + _SMB_AMOUNT_2 + _SMB_AMOUNT_3,
            "totalSecondaryMarketBurnedAmount should be preserved"
        );
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(_DOMAIN_1),
            _SMB_AMOUNT_1 + _SMB_AMOUNT_2,
            "totalSecondaryMarketBurnedAmount for domain 1 should be preserved"
        );
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(_DOMAIN_2),
            _SMB_AMOUNT_3,
            "totalSecondaryMarketBurnedAmount for domain 2 should be preserved"
        );

        // Full record details preserved for each burned address
        (bytes memory retAddr, uint32 retDomain, uint256 retBalance, address retRecipient, bytes32 retHash) =
            _registry.getSecondaryMarketBurnRecord(_BURNED_ADDR_1, _DOMAIN_1);
        assertEq(retAddr, _BURNED_ADDR_1, "Burned address 1 in domain 1 record should be preserved");
        assertEq(retDomain, _DOMAIN_1, "Domain should be 1");
        assertEq(retBalance, _SMB_AMOUNT_1, "Balance should be _SMB_AMOUNT_1");
        assertEq(retRecipient, _le1, "Recipient should be le1");
        assertEq(retHash, bytes32(0), "Remint txHash shouldn't be set");

        (retAddr, retDomain, retBalance, retRecipient, retHash) =
            _registry.getSecondaryMarketBurnRecord(_BURNED_ADDR_2, _DOMAIN_1);
        assertEq(retAddr, _BURNED_ADDR_2, "Burned address 2 in domain 1 record should be preserved");
        assertEq(retDomain, _DOMAIN_1, "Domain should be 1");
        assertEq(retBalance, _SMB_AMOUNT_2, "Balance should be _SMB_AMOUNT_2");
        assertEq(retRecipient, _le1, "Recipient should be le1");
        assertEq(retHash, bytes32(0), "Remint txHash shouldn't be set");

        (retAddr, retDomain, retBalance, retRecipient, retHash) =
            _registry.getSecondaryMarketBurnRecord(_BURNED_ADDR_1, _DOMAIN_2);
        assertEq(retAddr, _BURNED_ADDR_1, "Burned address 1 in domain 2 record should be preserved");
        assertEq(retDomain, _DOMAIN_2, "Domain should be 2");
        assertEq(retBalance, _SMB_AMOUNT_3, "Balance should be _SMB_AMOUNT_3");
        assertEq(retRecipient, _le2, "Recipient should be le2");
        assertEq(retHash, bytes32(0), "Remint txHash shouldn't be set");

        (retAddr, retDomain, retBalance, retRecipient, retHash) =
            _registry.getSecondaryMarketBurnRecord(_BURNED_ADDR_3, _DOMAIN_1);
        assertEq(retAddr, _BURNED_ADDR_3, "Burned address 3 in domain 1 record should not be preserved");
        assertEq(retDomain, _DOMAIN_1, "Domain should be 1");
        assertEq(retBalance, 0, "Balance should be 0 since it's not a SMB'd address");
        assertEq(retRecipient, address(0), "Recipient should be address(0) since it's not a SMB'd address");
        assertEq(retHash, bytes32(0), "Remint txHash shouldn't be set since it's not a SMB'd address");

        // All four roles preserved
        assertEq(_registry.secondaryMarketBurner(), _secondaryMarketBurner, "secondaryMarketBurner should be preserved");
        assertEq(_registry.hashUpdater(), _hashUpdater, "hashUpdater should be preserved");
        assertEq(_registry.rescuer(), _rescuer, "rescuer should be preserved");
        assertEq(_registry.addressManager(), _addressManager, "addressManager should be preserved");

        // Ownership preserved
        assertEq(_registry.owner(), _owner, "owner should be preserved");

        // Old token supply unchanged — no new mints on old token after upgrade
        assertEq(_oldToken.totalSupply(), oldTokenSupplyBeforeUpgrade, "oldTokenSupply should be unchanged");
    }

    /// @notice After a different-TOKEN upgrade, new SMBs mint on the new token only.
    ///         Old token supply must not increase after the upgrade.
    function test_upgrade_differentToken_newSMBMintsOnNewTokenOnly() public {
        uint256 postUpgradeSmbAmount = 50e6;

        // Pre-upgrade SMB (old token)
        _grantOldMinterAllowance(_SMB_AMOUNT_1);
        _doSMB(_BURNED_ADDR_1, _DOMAIN_1, _SMB_AMOUNT_1, _le1);
        uint256 oldTokenSupplySnapshot = _oldToken.totalSupply();

        // Upgrade to new impl with _newToken
        address newImpl = address(new SeizureRegistry(address(_newToken)));
        vm.prank(_owner);
        _registry.upgradeToAndCall(newImpl, "");

        // Execute a new SMB using the new token's minter allowance
        address newRecipient = makeAddr("newRecipient");
        vm.prank(_addressManager);
        _registry.addAllowedRecipient(newRecipient);
        _grantNewMinterAllowance(postUpgradeSmbAmount);
        _doSMB(_BURNED_ADDR_2, _DOMAIN_1, postUpgradeSmbAmount, newRecipient);

        // New token received the mint
        assertEq(
            _newToken.balanceOf(newRecipient),
            postUpgradeSmbAmount,
            "New token balance of newRecipient should be postUpgradeSmbAmount"
        );

        // Old token was NOT minted to — balance and total supply frozen at the pre-upgrade snapshot
        assertEq(_oldToken.balanceOf(newRecipient), 0, "Old token balance of newRecipient should be 0");
        assertEq(_oldToken.totalSupply(), oldTokenSupplySnapshot, "oldTokenSupply should be unchanged");

        // Total SMB amount reflects both the pre-upgrade and post-upgrade burns
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(),
            _SMB_AMOUNT_1 + postUpgradeSmbAmount,
            "totalSecondaryMarketBurnedAmount should reflect both burns"
        );
    }

    // ============ Scenario B: reinitializer(3) upgrade with new state ============

    /// @notice Upgrades to SeizureRegistryV2Stub via reinitializer(3). Asserts the pre-upgrade SMB
    ///         record survives, the new V2 storage field is initialized correctly, and the
    ///         reinitializer cannot be called a second time.
    function test_upgrade_reinitializer_preservesDataAndInitializesNewState() public {
        uint256 preSmbAmount = 75e6;
        uint256 postSmbAmount = 25e6;

        // Pre-upgrade: 1 SMB
        _grantOldMinterAllowance(preSmbAmount);
        _doSMB(_BURNED_ADDR_1, _DOMAIN_1, preSmbAmount, _le1);

        // Upgrade to V2Stub with same token, passing reinitializer(3) calldata
        address newRole = makeAddr("newRole");
        address v2Stub = address(new SeizureRegistryV2Stub(address(_oldToken)));
        vm.prank(_owner);
        _registry.upgradeToAndCall(v2Stub, abi.encodeCall(SeizureRegistryV2Stub.initializeV2, (newRole)));

        // Prior SMB record intact
        assertTrue(
            _registry.isSecondaryMarketBurned(_BURNED_ADDR_1, _DOMAIN_1),
            "Burned address 1 in domain 1 record should be preserved"
        );
        assertEq(
            _registry.secondaryMarketBurnedBalance(_BURNED_ADDR_1, _DOMAIN_1),
            preSmbAmount,
            "Burned balance should be preSmbAmount"
        );
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(),
            preSmbAmount,
            "totalSecondaryMarketBurnedAmount should be preSmbAmount"
        );
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(_DOMAIN_1),
            preSmbAmount,
            "totalSecondaryMarketBurnedAmount for domain 1 should be preSmbAmount"
        );

        // New V2 state initialized
        assertEq(SeizureRegistryV2Stub(address(_registry)).newRole(), newRole, "New role should be set to newRole");

        // TOKEN still points to old token (same address passed to V2Stub constructor)
        assertEq(address(_registry.TOKEN()), address(_oldToken), "TOKEN should still point to old token");

        // All four roles preserved
        assertEq(_registry.secondaryMarketBurner(), _secondaryMarketBurner, "secondaryMarketBurner should be preserved");
        assertEq(_registry.hashUpdater(), _hashUpdater, "hashUpdater should be preserved");
        assertEq(_registry.rescuer(), _rescuer, "rescuer should be preserved");
        assertEq(_registry.addressManager(), _addressManager, "addressManager should be preserved");

        // Ownership preserved
        assertEq(_registry.owner(), _owner, "owner should be preserved");

        // reinitializer(3) is blocked on re-call
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        SeizureRegistryV2Stub(address(_registry)).initializeV2(makeAddr("anotherRole"));

        // Registry remains fully functional after reinitializer upgrade
        _grantOldMinterAllowance(postSmbAmount);
        _doSMB(_BURNED_ADDR_2, _DOMAIN_1, postSmbAmount, _le2);

        // New post-upgrade SMB recorded
        assertTrue(
            _registry.isSecondaryMarketBurned(_BURNED_ADDR_2, _DOMAIN_1),
            "Burned address 2 in domain 1 record should be preserved"
        );

        // Total SMB amount accumulates across the upgrade
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(),
            preSmbAmount + postSmbAmount,
            "totalSecondaryMarketBurnedAmount should reflect both burns"
        );
    }
}

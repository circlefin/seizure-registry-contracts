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

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {ZeroAddress} from "src/common/Errors.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";
import {MasterMinter} from "test/mocks/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "test/mocks/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "test/mocks/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployMockFiatToken} from "test/util/DeployMockFiatToken.sol";

contract SeizureRegistryTest is Test {
    SeizureRegistry internal _registry;
    address internal _impl;

    DeployMockFiatToken private _usdc;
    FiatTokenV2_2 internal _token;
    MasterMinter internal _masterMinter;

    address internal _owner = makeAddr("owner");
    address internal _secondaryMarketBurner = makeAddr("secondaryMarketBurner");
    address internal _hashUpdater = makeAddr("hashUpdater");
    address internal _rescuer = makeAddr("rescuer");
    address internal _addressManager = makeAddr("addressManager");
    address internal _other = makeAddr("other");

    bytes internal constant _ADDR_BYTES = abi.encodePacked(address(0xbeef));
    uint32 internal constant _DOMAIN = 1;
    uint256 internal constant _BALANCE = 1_000e6;
    bytes32 internal constant _TX_HASH = keccak256("txhash");

    function setUp() public {
        // Deploy mock FiatToken
        _usdc = new DeployMockFiatToken();
        FiatTokenProxy proxy;
        (, _masterMinter, proxy) = _usdc.deploy();
        _token = FiatTokenV2_2(address(proxy));

        // Deploy SeizureRegistry implementation + proxy via UpgradeablePlaceholder pattern
        _impl = address(new SeizureRegistry(address(_token)));
        UpgradeablePlaceholder placeholder = new UpgradeablePlaceholder();
        ERC1967Proxy registryProxy =
            new ERC1967Proxy(address(placeholder), abi.encodeCall(UpgradeablePlaceholder.initialize, (address(this))));
        UpgradeablePlaceholder(address(registryProxy))
            .upgradeToAndCall(
                _impl,
                abi.encodeCall(
                    SeizureRegistry.initialize, (_secondaryMarketBurner, _hashUpdater, _rescuer, _addressManager)
                )
            );
        _registry = SeizureRegistry(address(registryProxy));

        // 2-step ownership transfer to _owner
        _registry.transferOwnership(_owner);
        vm.prank(_owner);
        _registry.acceptOwnership();

        // Configure registry as a minter (allowance starts at 0; incremented per-test via _grantMintAllowance)
        vm.startPrank(_usdc.masterMinterOwner());
        _masterMinter.configureController(_usdc.masterMinterOwner(), address(_registry));
        _masterMinter.configureMinter(0);
        vm.stopPrank();
    }

    // ============ TOKEN immutable ============

    function test_token_setCorrectly() public view {
        assertEq(address(_registry.TOKEN()), address(_token));
    }

    // ============ Constructor ============

    function test_constructor_revertsOnZeroToken() public {
        vm.expectRevert(ZeroAddress.selector);
        new SeizureRegistry(address(0));
    }

    function test_constructor_disablesInitializersOnImplementation() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        SeizureRegistry(_impl).initialize(_secondaryMarketBurner, _hashUpdater, _rescuer, _addressManager);
    }

    // ============ initialize ============

    function test_initialize_cannotBeCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _registry.initialize(_secondaryMarketBurner, _hashUpdater, _rescuer, _addressManager);
    }

    function test_initialize_revertsOnZeroSecondaryMarketBurner() public {
        (UpgradeablePlaceholder p, address impl) = _buildProxy();
        vm.expectRevert(ZeroAddress.selector);
        p.upgradeToAndCall(
            impl, abi.encodeCall(SeizureRegistry.initialize, (address(0), _hashUpdater, _rescuer, _addressManager))
        );
    }

    function test_initialize_revertsOnZeroHashUpdater() public {
        (UpgradeablePlaceholder p, address impl) = _buildProxy();
        vm.expectRevert(ZeroAddress.selector);
        p.upgradeToAndCall(
            impl,
            abi.encodeCall(SeizureRegistry.initialize, (_secondaryMarketBurner, address(0), _rescuer, _addressManager))
        );
    }

    function test_initialize_revertsOnZeroAddressManager() public {
        (UpgradeablePlaceholder p, address impl) = _buildProxy();
        vm.expectRevert(ZeroAddress.selector);
        p.upgradeToAndCall(
            impl,
            abi.encodeCall(SeizureRegistry.initialize, (_secondaryMarketBurner, _hashUpdater, _rescuer, address(0)))
        );
    }

    // ============ Role getters ============

    function test_roleGetters_returnCorrectValuesAfterInit() public view {
        assertEq(_registry.secondaryMarketBurner(), _secondaryMarketBurner, "SecondaryMarketBurner mismatch");
        assertEq(_registry.hashUpdater(), _hashUpdater, "HashUpdater mismatch");
        assertEq(_registry.rescuer(), _rescuer, "Rescuer mismatch");
        assertEq(_registry.addressManager(), _addressManager, "AddressManager mismatch");
    }

    function test_owner_setCorrectlyAfterInit() public view {
        // Placeholder sets proxy owner at v1; setUp completes 2-step transfer to _owner
        assertEq(_registry.owner(), _owner, "Owner mismatch");
    }

    // ============ renounceOwnership ============

    function test_renounceOwnership_revertsForOwner() public {
        vm.expectRevert(SeizureRegistry.RenounceOwnershipDisabled.selector);
        vm.prank(_owner);
        _registry.renounceOwnership();
    }

    function test_renounceOwnership_revertsForNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _other));
        vm.prank(_other);
        _registry.renounceOwnership();
    }

    // ============ _authorizeUpgrade ============

    function test_authorizeUpgrade_nonOwnerReverts() public {
        address newImpl = address(new SeizureRegistry(address(_token)));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _other));
        vm.prank(_other);
        _registry.upgradeToAndCall(newImpl, "");
    }

    function test_authorizeUpgrade_ownerSucceeds_statePreserved() public {
        address newImpl = address(new SeizureRegistry(address(_token)));

        vm.prank(_owner);
        _registry.upgradeToAndCall(newImpl, "");

        assertEq(_registry.owner(), _owner);
        assertEq(_registry.secondaryMarketBurner(), _secondaryMarketBurner);
        assertEq(_registry.hashUpdater(), _hashUpdater);
        assertEq(_registry.rescuer(), _rescuer);
        assertEq(_registry.addressManager(), _addressManager);
        assertEq(address(_registry.TOKEN()), address(_token));
    }

    function test_authorizeUpgrade_differentTokenImpl_reflectsNewImmutable() public {
        // Deploy a second FiatToken to use as the new tokenContract immutable
        DeployMockFiatToken usdc2 = new DeployMockFiatToken();
        FiatTokenProxy proxy2;
        (,, proxy2) = usdc2.deploy();
        address newToken = address(proxy2);

        address newImpl = address(new SeizureRegistry(newToken));

        vm.prank(_owner);
        _registry.upgradeToAndCall(newImpl, "");

        assertEq(address(_registry.TOKEN()), newToken, "TOKEN should reflect new impl immutable");
        // Storage-backed state is unchanged
        assertEq(_registry.owner(), _owner, "Owner mismatch");
        assertEq(_registry.secondaryMarketBurner(), _secondaryMarketBurner, "SecondaryMarketBurner mismatch");
        assertEq(_registry.hashUpdater(), _hashUpdater, "HashUpdater mismatch");
        assertEq(_registry.rescuer(), _rescuer, "Rescuer mismatch");
        assertEq(_registry.addressManager(), _addressManager, "AddressManager mismatch");
    }

    // ============ 2-step ownership ============

    function test_ownership_twoStepTransfer_endToEnd() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(_owner);
        _registry.transferOwnership(newOwner);
        assertEq(_registry.owner(), _owner, "Owner should not change before acceptance");
        assertEq(_registry.pendingOwner(), newOwner, "Pending owner should be set");

        vm.prank(newOwner);
        _registry.acceptOwnership();
        assertEq(_registry.owner(), newOwner, "Owner should be updated");
        assertEq(_registry.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function test_ownership_transferToCurrentOwner_isIdempotent() public {
        vm.prank(_owner);
        _registry.transferOwnership(_owner);

        assertEq(_registry.owner(), _owner, "Owner should be unchanged");
        assertEq(_registry.pendingOwner(), _owner, "Pending owner should be set to current owner");

        vm.prank(_owner);
        _registry.acceptOwnership();
        assertEq(_registry.owner(), _owner, "Owner should still be unchanged after accept");
        assertEq(_registry.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function test_ownership_pendingOwnerCanBeOverridden() public {
        address first = makeAddr("first");
        address second = makeAddr("second");

        vm.prank(_owner);
        _registry.transferOwnership(first);
        assertEq(_registry.pendingOwner(), first);

        // Override pending owner before first accepts
        vm.prank(_owner);
        _registry.transferOwnership(second);
        assertEq(_registry.pendingOwner(), second, "Pending owner should be overridden");

        // First can no longer accept
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, first));
        vm.prank(first);
        _registry.acceptOwnership();

        // Second can accept
        vm.prank(second);
        _registry.acceptOwnership();
        assertEq(_registry.owner(), second);
    }

    function test_ownership_nonPendingOwnerCannotAccept() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(_owner);
        _registry.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _other));
        vm.prank(_other);
        _registry.acceptOwnership();
    }

    // ============ onlyOwner functions ============

    function test_onlyOwner_canUpdateAllRolesAndUpgrade() public {
        address newBurner = makeAddr("newBurner");
        address newUpdater = makeAddr("newUpdater");
        address newRescuer = makeAddr("newRescuer");
        address newManager = makeAddr("newManager");
        address newImpl = address(new SeizureRegistry(address(_token)));

        vm.startPrank(_owner);
        _registry.updateSecondaryMarketBurner(newBurner);
        _registry.updateHashUpdater(newUpdater);
        _registry.updateRescuer(newRescuer);
        _registry.updateAddressManager(newManager);
        _registry.upgradeToAndCall(newImpl, "");
        vm.stopPrank();

        assertEq(_registry.secondaryMarketBurner(), newBurner, "SecondaryMarketBurner should be updated");
        assertEq(_registry.hashUpdater(), newUpdater, "HashUpdater should be updated");
        assertEq(_registry.rescuer(), newRescuer, "Rescuer should be updated");
        assertEq(_registry.addressManager(), newManager, "AddressManager should be updated");
    }

    // ============ getSecondaryMarketBurnRecord (bytes overload) ============

    function test_getSecondaryMarketBurnRecord_preBurn_returnsZeroFields() public view {
        (bytes memory burnedAddress, uint32 domain_, uint256 balance, address remintRecipient, bytes32 remintTxHash) =
            _registry.getSecondaryMarketBurnRecord(_ADDR_BYTES, _DOMAIN);

        assertEq(burnedAddress, _ADDR_BYTES, "BurnedAddress mismatch");
        assertEq(domain_, _DOMAIN, "Domain mismatch");
        assertEq(balance, 0, "Balance mismatch");
        assertEq(remintRecipient, address(0), "RemintRecipient mismatch");
        assertEq(remintTxHash, bytes32(0), "RemintTxHash mismatch");
    }

    function test_getSecondaryMarketBurnRecord_postBurn_returnsCorrectFields() public {
        address remintRecipient = makeAddr("remintRecipient");
        _performSecondaryMarketBurn(remintRecipient);

        (bytes memory burnedAddress, uint32 domain_, uint256 balance, address recipient, bytes32 remintTxHash) =
            _registry.getSecondaryMarketBurnRecord(_ADDR_BYTES, _DOMAIN);

        assertEq(burnedAddress, _ADDR_BYTES, "BurnedAddress mismatch");
        assertEq(domain_, _DOMAIN, "Domain mismatch");
        assertEq(balance, _BALANCE, "Balance mismatch");
        assertEq(recipient, remintRecipient, "RemintRecipient mismatch");
        assertEq(remintTxHash, bytes32(0), "RemintTxHash should be zero before setRemintTxHash");
    }

    function test_getSecondaryMarketBurnRecord_postSetRemintTxHash_returnsCorrectHash() public {
        address remintRecipient = makeAddr("remintRecipient");
        _performSecondaryMarketBurn(remintRecipient);

        vm.prank(_hashUpdater);
        _registry.setRemintTxHash(_ADDR_BYTES, _DOMAIN, _TX_HASH);

        (bytes memory burnedAddress, uint32 domain_, uint256 balance, address recipient, bytes32 remintTxHash) =
            _registry.getSecondaryMarketBurnRecord(_ADDR_BYTES, _DOMAIN);

        assertEq(burnedAddress, _ADDR_BYTES, "BurnedAddress mismatch");
        assertEq(domain_, _DOMAIN, "Domain mismatch");
        assertEq(balance, _BALANCE, "Balance mismatch");
        assertEq(recipient, remintRecipient, "RemintRecipient mismatch");
        assertEq(remintTxHash, _TX_HASH, "RemintTxHash mismatch");
    }

    function test_getSecondaryMarketBurnRecord_differentDomainsAreIndependent() public {
        address remintRecipient = makeAddr("remintRecipient");
        _performSecondaryMarketBurn(remintRecipient);

        (bytes memory burnedAddress, uint32 domain_, uint256 balance, address recipient, bytes32 remintTxHash) =
            _registry.getSecondaryMarketBurnRecord(_ADDR_BYTES, _DOMAIN + 1);

        assertEq(burnedAddress, _ADDR_BYTES, "BurnedAddress mismatch");
        assertEq(domain_, _DOMAIN + 1, "Domain mismatch");
        assertEq(balance, 0, "Balance mismatch");
        assertEq(recipient, address(0), "RemintRecipient mismatch");
        assertEq(remintTxHash, bytes32(0), "RemintTxHash mismatch");
    }

    function test_getSecondaryMarketBurnRecord_differentAddressesAreIndependent() public {
        address remintRecipient = makeAddr("remintRecipient");
        _performSecondaryMarketBurn(remintRecipient);

        bytes memory otherAddr = abi.encodePacked(address(0xdead));
        (bytes memory burnedAddress, uint32 domain_, uint256 balance, address recipient, bytes32 remintTxHash) =
            _registry.getSecondaryMarketBurnRecord(otherAddr, _DOMAIN);

        assertEq(burnedAddress, otherAddr, "BurnedAddress mismatch");
        assertEq(domain_, _DOMAIN, "Domain mismatch");
        assertEq(balance, 0, "Balance mismatch");
        assertEq(recipient, address(0), "RemintRecipient mismatch");
        assertEq(remintTxHash, bytes32(0), "RemintTxHash mismatch");
    }

    // ============ getSecondaryMarketBurnRecord (address overload) ============

    address internal constant _ADDR_EVM = address(0xbeef);

    function test_getSecondaryMarketBurnRecord_evmAddress_preBurn_returnsZeroFields() public view {
        (address burnedAddress, uint32 domain_, uint256 balance, address remintRecipient, bytes32 remintTxHash) =
            _registry.getSecondaryMarketBurnRecord(_ADDR_EVM, _DOMAIN);

        assertEq(burnedAddress, _ADDR_EVM, "BurnedAddress mismatch");
        assertEq(domain_, _DOMAIN, "Domain mismatch");
        assertEq(balance, 0, "Balance mismatch");
        assertEq(remintRecipient, address(0), "RemintRecipient mismatch");
        assertEq(remintTxHash, bytes32(0), "RemintTxHash mismatch");
    }

    function test_getSecondaryMarketBurnRecord_evmAddress_postBurn_returnsCorrectFields() public {
        address remintRecipient = makeAddr("remintRecipient");
        // _ADDR_BYTES = abi.encodePacked(_ADDR_EVM), so the same record is hit
        _performSecondaryMarketBurn(remintRecipient);

        (address burnedAddress, uint32 domain_, uint256 balance, address recipient, bytes32 remintTxHash) =
            _registry.getSecondaryMarketBurnRecord(_ADDR_EVM, _DOMAIN);

        assertEq(burnedAddress, _ADDR_EVM, "BurnedAddress mismatch");
        assertEq(domain_, _DOMAIN, "Domain mismatch");
        assertEq(balance, _BALANCE, "Balance mismatch");
        assertEq(recipient, remintRecipient, "RemintRecipient mismatch");
        assertEq(remintTxHash, bytes32(0), "RemintTxHash should be zero before setRemintTxHash");
    }

    function test_getSecondaryMarketBurnRecord_evmAddress_postSetRemintTxHash_returnsCorrectHash() public {
        address remintRecipient = makeAddr("remintRecipient");
        _performSecondaryMarketBurn(remintRecipient);

        vm.prank(_hashUpdater);
        _registry.setRemintTxHash(_ADDR_BYTES, _DOMAIN, _TX_HASH);

        (address burnedAddress, uint32 domain_, uint256 balance, address recipient, bytes32 remintTxHash) =
            _registry.getSecondaryMarketBurnRecord(_ADDR_EVM, _DOMAIN);

        assertEq(burnedAddress, _ADDR_EVM, "BurnedAddress mismatch");
        assertEq(domain_, _DOMAIN, "Domain mismatch");
        assertEq(balance, _BALANCE, "Balance mismatch");
        assertEq(recipient, remintRecipient, "RemintRecipient mismatch");
        assertEq(remintTxHash, _TX_HASH, "RemintTxHash mismatch");
    }

    function test_getSecondaryMarketBurnRecord_evmAddress_bytesAndAddressOverloadAreEquivalent() public {
        address remintRecipient = makeAddr("remintRecipient");
        _performSecondaryMarketBurn(remintRecipient);

        vm.prank(_hashUpdater);
        _registry.setRemintTxHash(_ADDR_BYTES, _DOMAIN, _TX_HASH);

        (,, uint256 bytesBalance, address bytesRecipient, bytes32 bytesTxHash) =
            _registry.getSecondaryMarketBurnRecord(_ADDR_BYTES, _DOMAIN);
        (,, uint256 addrBalance, address addrRecipient, bytes32 addrTxHash) =
            _registry.getSecondaryMarketBurnRecord(_ADDR_EVM, _DOMAIN);

        assertEq(addrBalance, bytesBalance, "Balance should match between overloads");
        assertEq(addrRecipient, bytesRecipient, "RemintRecipient should match between overloads");
        assertEq(addrTxHash, bytesTxHash, "RemintTxHash should match between overloads");
    }

    // ============ Helpers ============

    /// @dev Deploys a fresh placeholder-initialized proxy + impl, ready for upgradeToAndCall.
    ///      Used by zero-address revert tests so vm.expectRevert can be placed directly before
    ///      the upgradeToAndCall call (vm.expectRevert only captures the next external call).
    function _buildProxy() internal returns (UpgradeablePlaceholder p, address impl) {
        impl = address(new SeizureRegistry(address(_token)));
        UpgradeablePlaceholder placeholder = new UpgradeablePlaceholder();
        ERC1967Proxy registryProxy =
            new ERC1967Proxy(address(placeholder), abi.encodeCall(UpgradeablePlaceholder.initialize, (address(this))));
        p = UpgradeablePlaceholder(address(registryProxy));
    }

    function _grantMinterAllowance(uint256 amount) private {
        vm.prank(_usdc.masterMinterOwner());
        _masterMinter.incrementMinterAllowance(amount);
    }

    /// @dev Allowlists `remintRecipient`, grants mint allowance, and fires secondaryMarketBurnAndRemint.
    function _performSecondaryMarketBurn(address remintRecipient) internal {
        vm.prank(_addressManager);
        _registry.addAllowedRecipient(remintRecipient);
        _grantMinterAllowance(_BALANCE);
        vm.prank(_secondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(_ADDR_BYTES, _DOMAIN, _BALANCE, remintRecipient);
    }
}

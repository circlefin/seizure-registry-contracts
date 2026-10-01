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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Test} from "forge-std/Test.sol";
import {UnauthorizedCaller, ZeroAddress} from "src/common/Errors.sol";
import {Allowlistable, AllowlistableStorage} from "src/modules/Allowlistable.sol";

// ============ Test Harnesses ============

/// @dev Base harness — does NOT call __Allowlistable_init; addressManager starts at address(0)
contract AllowlistableHarness is Allowlistable {
    function initialize(address owner_) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
    }

    function exposeEnsureAddressRecipientAllowed(address recipient) external view {
        _ensureAddressRecipientAllowed(recipient);
    }

    function verifyOnlyAddressManagerModifier() public onlyAddressManager {}
}

/// @dev Harness that calls __Allowlistable_init during initialization
contract AllowlistableHarnessWithInit is Allowlistable {
    function initialize(address owner_, address addressManager_) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
        __Allowlistable_init(addressManager_);
    }

    function verifyOnlyAddressManagerModifier() public onlyAddressManager {}
}

/// @dev Harness that supports reinitialization to simulate an upgrade re-running the module init
contract AllowlistableHarnessWithReinit is Allowlistable {
    function initialize(address owner_, address addressManager_) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
        __Allowlistable_init(addressManager_);
    }

    function reinit(address newAddressManager) public reinitializer(2) {
        __Allowlistable_init(newAddressManager);
    }

    function verifyOnlyAddressManagerModifier() public onlyAddressManager {}
}

// ============ Tests ============

contract AllowlistableTest is Test {
    AllowlistableHarness private _allowlistable;

    address private _owner = makeAddr("owner");
    address private _addressManager = makeAddr("addressManager");
    address private _recipient = makeAddr("recipient");
    address private _otherRecipient = makeAddr("otherRecipient");
    address private _other = makeAddr("other");

    function setUp() public {
        _allowlistable = new AllowlistableHarness();
        _allowlistable.initialize(_owner);
    }

    // ============ Storage Slot ============

    function test_storageSlot_correctlyCalculated() public pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.Allowlistable"))) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(AllowlistableStorage.SLOT, expected, "Storage slot should match EIP-7201 calculation");
    }

    // ============ Initial State ============

    function test_initialState_addressManagerIsZero() public view {
        assertEq(_allowlistable.addressManager(), address(0));
    }

    function test_initialState_ownerIsSet() public view {
        assertEq(_allowlistable.owner(), _owner);
    }

    function test_initialState_noAddressIsAnAllowedRecipient() public {
        // Modifier reverts for any caller when addressManager is still address(0)
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_addressManager);
        _allowlistable.verifyOnlyAddressManagerModifier();

        // No address is an allowed recipient by default
        assertFalse(_allowlistable.isAllowedRecipient(_recipient));
    }

    // ============ Initialization ============

    function test_allowlistableInit_setsAddressManagerDuringInitialization() public {
        AllowlistableHarnessWithInit allowlistableWithInit = new AllowlistableHarnessWithInit();
        allowlistableWithInit.initialize(_owner, _addressManager);

        assertEq(
            allowlistableWithInit.addressManager(),
            _addressManager,
            "Address manager should be set during initialization"
        );
        assertEq(allowlistableWithInit.owner(), _owner, "Owner should be set during initialization");

        vm.prank(_addressManager);
        allowlistableWithInit.addAllowedRecipient(_recipient);

        assertTrue(
            allowlistableWithInit.isAllowedRecipient(_recipient),
            "Address manager should be able to add an allowed recipient"
        );
    }

    function test_reinit_emitsOldAddressManagerNonZero() public {
        AllowlistableHarnessWithReinit allowlistableWithReinit = new AllowlistableHarnessWithReinit();
        allowlistableWithReinit.initialize(_owner, _addressManager);
        assertEq(allowlistableWithReinit.addressManager(), _addressManager, "Initial address manager should be set");

        address newAddressManager = makeAddr("newAddressManager");

        vm.expectEmit(true, true, false, false, address(allowlistableWithReinit));
        emit Allowlistable.AddressManagerChanged(_addressManager, newAddressManager);
        allowlistableWithReinit.reinit(newAddressManager);

        assertEq(
            allowlistableWithReinit.addressManager(),
            newAddressManager,
            "Address manager should be updated during reinit"
        );
    }

    function test_init_revertIfZeroAddressManager() public {
        AllowlistableHarnessWithInit allowlistableWithInit = new AllowlistableHarnessWithInit();
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        allowlistableWithInit.initialize(_owner, address(0));
    }

    // ============ updateAddressManager ============

    function test_updateAddressManager_basicSuccess() public {
        vm.expectEmit(true, true, false, false, address(_allowlistable));
        emit Allowlistable.AddressManagerChanged(address(0), _addressManager);

        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        assertEq(_allowlistable.addressManager(), _addressManager);

        vm.prank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);
        assertTrue(_allowlistable.isAllowedRecipient(_recipient), "Address manager should be able to add recipients");
    }

    function test_updateAddressManager_changeAddressManager() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        address newAddressManager = makeAddr("newAddressManager");

        vm.expectEmit(true, true, false, false, address(_allowlistable));
        emit Allowlistable.AddressManagerChanged(_addressManager, newAddressManager);

        vm.prank(_owner);
        _allowlistable.updateAddressManager(newAddressManager);

        assertEq(_allowlistable.addressManager(), newAddressManager);

        vm.prank(newAddressManager);
        _allowlistable.addAllowedRecipient(_recipient);
        assertTrue(
            _allowlistable.isAllowedRecipient(_recipient), "New address manager should be able to add recipients"
        );

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_addressManager);
        _allowlistable.addAllowedRecipient(_otherRecipient);
    }

    function test_updateAddressManager_isIdempotent() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.expectEmit(true, true, false, false, address(_allowlistable));
        emit Allowlistable.AddressManagerChanged(_addressManager, _addressManager);

        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        assertEq(_allowlistable.addressManager(), _addressManager);

        vm.prank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);
        assertTrue(
            _allowlistable.isAllowedRecipient(_recipient), "Address manager should still be able to add recipients"
        );
    }

    function test_updateAddressManager_revertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        vm.prank(_owner);
        _allowlistable.updateAddressManager(address(0));
    }

    function test_updateAddressManager_revertIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _other));
        vm.prank(_other);
        _allowlistable.updateAddressManager(_addressManager);
    }

    // ============ onlyAddressManager ============

    function test_onlyAddressManager_success() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.prank(_addressManager);
        _allowlistable.verifyOnlyAddressManagerModifier();
    }

    function test_onlyAddressManager_revertIfNotAddressManager() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_other);
        _allowlistable.verifyOnlyAddressManagerModifier();
    }

    // ============ addAllowedRecipient ============

    function test_addAllowedRecipient_success() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        assertFalse(
            _allowlistable.isAllowedRecipient(_recipient), "Recipient should not be an allowed recipient by default"
        );

        vm.expectEmit(true, false, false, false, address(_allowlistable));
        emit Allowlistable.AllowedRecipientAdded(_recipient);

        vm.prank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);

        assertTrue(_allowlistable.isAllowedRecipient(_recipient), "Recipient should be an allowed recipient");
        assertFalse(
            _allowlistable.isAllowedRecipient(_otherRecipient), "Other recipient should not be an allowed recipient"
        );
    }

    function test_addAllowedRecipient_isIdempotent() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.prank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);

        vm.expectEmit(true, false, false, false, address(_allowlistable));
        emit Allowlistable.AllowedRecipientAdded(_recipient);

        vm.prank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);

        assertTrue(_allowlistable.isAllowedRecipient(_recipient), "Recipient should be an allowed recipient");
    }

    function test_addAllowedRecipient_revertIfZeroAddress() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        vm.prank(_addressManager);
        _allowlistable.addAllowedRecipient(address(0));
    }

    function test_addAllowedRecipient_revertIfNotAddressManager() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_other);
        _allowlistable.addAllowedRecipient(_recipient);
    }

    // ============ removeAllowedRecipient ============

    function test_removeAllowedRecipient_success() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.startPrank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);
        _allowlistable.addAllowedRecipient(_otherRecipient);
        vm.stopPrank();

        assertTrue(_allowlistable.isAllowedRecipient(_recipient), "Recipient should be an allowed recipient");
        assertTrue(_allowlistable.isAllowedRecipient(_otherRecipient), "Other recipient should be allowlisted");

        vm.expectEmit(true, false, false, false, address(_allowlistable));
        emit Allowlistable.AllowedRecipientRemoved(_recipient);

        vm.prank(_addressManager);
        _allowlistable.removeAllowedRecipient(_recipient);

        assertFalse(_allowlistable.isAllowedRecipient(_recipient), "Recipient should no longer be an allowed recipient");
        assertTrue(
            _allowlistable.isAllowedRecipient(_otherRecipient), "Other recipient should still be an allowed recipient"
        );
    }

    function test_removeAllowedRecipient_withoutFirstAdding() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.expectEmit(true, false, false, false, address(_allowlistable));
        emit Allowlistable.AllowedRecipientRemoved(_recipient);

        vm.prank(_addressManager);
        _allowlistable.removeAllowedRecipient(_recipient);

        assertFalse(_allowlistable.isAllowedRecipient(_recipient), "Recipient should no longer be an allowed recipient");
    }

    function test_removeAllowedRecipient_isIdempotent() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.startPrank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);
        _allowlistable.removeAllowedRecipient(_recipient);
        vm.stopPrank();

        assertFalse(_allowlistable.isAllowedRecipient(_recipient), "Recipient should no longer be an allowed recipient");

        vm.expectEmit(true, false, false, false, address(_allowlistable));
        emit Allowlistable.AllowedRecipientRemoved(_recipient);

        vm.prank(_addressManager);
        _allowlistable.removeAllowedRecipient(_recipient);

        assertFalse(_allowlistable.isAllowedRecipient(_recipient), "Recipient should no longer be an allowed recipient");
    }

    function test_removeAllowedRecipient_revertIfNotAddressManager() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_other);
        _allowlistable.removeAllowedRecipient(_recipient);
    }

    // ============ _ensureAddressRecipientAllowed ============

    function test_ensureAddressRecipientAllowed_success() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.prank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);

        _allowlistable.exposeEnsureAddressRecipientAllowed(_recipient);
    }

    function test_ensureAddressRecipientAllowed_revertIfNotAnAllowedRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(Allowlistable.RecipientNotAllowed.selector, _recipient));
        _allowlistable.exposeEnsureAddressRecipientAllowed(_recipient);
    }

    function test_ensureAddressRecipientAllowed_revertAfterRemoval() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.startPrank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);
        _allowlistable.removeAllowedRecipient(_recipient);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Allowlistable.RecipientNotAllowed.selector, _recipient));
        _allowlistable.exposeEnsureAddressRecipientAllowed(_recipient);
    }

    // ============ isAllowedRecipient ============

    function test_isAllowedRecipient_returnsCorrectStatus() public {
        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);

        vm.prank(_addressManager);
        _allowlistable.addAllowedRecipient(_recipient);

        assertTrue(_allowlistable.isAllowedRecipient(_recipient), "Recipient should be an allowed recipient");
        assertFalse(
            _allowlistable.isAllowedRecipient(_otherRecipient), "Other recipient should not be an allowed recipient"
        );
    }

    // ============ addressManager ============

    function test_addressManager_returnsCorrectStatus() public {
        assertEq(_allowlistable.addressManager(), address(0), "Address manager should be zero initially");

        vm.prank(_owner);
        _allowlistable.updateAddressManager(_addressManager);
        assertEq(_allowlistable.addressManager(), _addressManager, "Address manager should reflect the set address");

        address newAddressManager = makeAddr("newAddressManager");
        vm.prank(_owner);
        _allowlistable.updateAddressManager(newAddressManager);
        assertEq(_allowlistable.addressManager(), newAddressManager, "Address manager should reflect the latest update");
    }
}

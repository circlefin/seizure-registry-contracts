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

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UnauthorizedCaller} from "src/common/Errors.sol";
import {Rescuable, RescuableStorage} from "src/modules/Rescuable.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

// ============ Test Harness ============

/// @dev Minimal harness that exposes Rescuable for testing.
contract RescuableHarness is Rescuable {
    function initialize(address owner_, address rescuer_) external initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
        __Rescuable_init(rescuer_);
    }
}

// ============ Tests ============

contract RescuableTest is Test {
    RescuableHarness internal rescuable;
    MockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal rescuerAddr = makeAddr("rescuer");
    address internal alice = makeAddr("alice");

    uint256 internal constant RESCUE_AMOUNT = 1000e6;

    function setUp() public {
        rescuable = new RescuableHarness();
    }

    // ============ Storage Slot ============

    function test_storageSlot_correctlyCalculated() public pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.Rescuable"))) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(RescuableStorage.SLOT, expected, "Storage slot should match EIP-7201 calculation");
    }

    // ─── Initialization ───

    function testInitialization_success() public {
        assertEq(rescuable.rescuer(), address(0), "Rescuer should be zero address before init");

        vm.expectEmit(true, true, false, false, address(rescuable));
        emit Rescuable.RescuerChanged(address(0), rescuerAddr);
        rescuable.initialize(owner, rescuerAddr);

        assertEq(rescuable.rescuer(), rescuerAddr);
        assertEq(rescuable.owner(), owner);
    }

    function testInitialization_revertIfAlreadyInitialized() public {
        rescuable.initialize(owner, rescuerAddr);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        rescuable.initialize(owner, rescuerAddr);
    }

    // ─── rescueERC20 ───

    function testRescueERC20_success() public {
        rescuable.initialize(owner, rescuerAddr);
        _fundRescuable();

        vm.prank(rescuerAddr);
        vm.expectEmit(true, true, true, true, address(rescuable));
        emit Rescuable.RescueERC20(address(token), alice, RESCUE_AMOUNT);
        rescuable.rescueERC20(IERC20(address(token)), alice, RESCUE_AMOUNT);

        assertEq(token.balanceOf(alice), RESCUE_AMOUNT);
        assertEq(token.balanceOf(address(rescuable)), 0);
    }

    function testRescueERC20_revertIfNotRescuer() public {
        rescuable.initialize(owner, rescuerAddr);
        _fundRescuable();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        rescuable.rescueERC20(IERC20(address(token)), alice, RESCUE_AMOUNT);
    }

    function testRescueERC20_revertIfOwnerNotRescuer() public {
        rescuable.initialize(owner, rescuerAddr);
        _fundRescuable();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        rescuable.rescueERC20(IERC20(address(token)), alice, RESCUE_AMOUNT);
    }

    function testRescueERC20_revertIfToZeroAddress() public {
        rescuable.initialize(owner, rescuerAddr);
        _fundRescuable();

        vm.prank(rescuerAddr);
        vm.expectRevert(abi.encodeWithSelector(Rescuable.InvalidRescueRecipient.selector, address(0)));
        rescuable.rescueERC20(IERC20(address(token)), address(0), RESCUE_AMOUNT);
    }

    function testRescueERC20_revertIfToSelf() public {
        rescuable.initialize(owner, rescuerAddr);
        _fundRescuable();

        vm.prank(rescuerAddr);
        vm.expectRevert(abi.encodeWithSelector(Rescuable.InvalidRescueRecipient.selector, address(rescuable)));
        rescuable.rescueERC20(IERC20(address(token)), address(rescuable), RESCUE_AMOUNT);
    }

    function testRescueERC20_revertIfExceedsBalance() public {
        rescuable.initialize(owner, rescuerAddr);
        _fundRescuable();

        vm.prank(rescuerAddr);
        vm.expectRevert();
        rescuable.rescueERC20(IERC20(address(token)), alice, RESCUE_AMOUNT + 1);
    }

    function testRescueERC20_partialThenRemainder() public {
        rescuable.initialize(owner, rescuerAddr);
        _fundRescuable();

        uint256 first = RESCUE_AMOUNT / 2;

        vm.prank(rescuerAddr);
        rescuable.rescueERC20(IERC20(address(token)), alice, first);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(address(rescuable)), RESCUE_AMOUNT - first);

        vm.prank(rescuerAddr);
        rescuable.rescueERC20(IERC20(address(token)), alice, RESCUE_AMOUNT - first);
        assertEq(token.balanceOf(alice), RESCUE_AMOUNT);
        assertEq(token.balanceOf(address(rescuable)), 0);
    }

    // ─── updateRescuer ───

    function testUpdateRescuer_success() public {
        rescuable.initialize(owner, rescuerAddr);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false, address(rescuable));
        emit Rescuable.RescuerChanged(rescuerAddr, alice);
        rescuable.updateRescuer(alice);

        assertEq(rescuable.rescuer(), alice);
    }

    function testUpdateRescuer_oldRescuerLosesAccess() public {
        rescuable.initialize(owner, rescuerAddr);
        _fundRescuable();

        vm.prank(owner);
        rescuable.updateRescuer(alice);

        vm.prank(rescuerAddr);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        rescuable.rescueERC20(IERC20(address(token)), alice, RESCUE_AMOUNT);
    }

    function testUpdateRescuer_newRescuerGainsAccess() public {
        rescuable.initialize(owner, rescuerAddr);
        _fundRescuable();

        vm.prank(owner);
        rescuable.updateRescuer(alice);

        vm.prank(alice);
        rescuable.rescueERC20(IERC20(address(token)), alice, RESCUE_AMOUNT);
        assertEq(token.balanceOf(alice), RESCUE_AMOUNT);
    }

    function testUpdateRescuer_revertIfNotOwner() public {
        rescuable.initialize(owner, rescuerAddr);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        rescuable.updateRescuer(alice);
    }

    function testUpdateRescuer_toZeroAddress() public {
        rescuable.initialize(owner, rescuerAddr);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false, address(rescuable));
        emit Rescuable.RescuerChanged(rescuerAddr, address(0));
        rescuable.updateRescuer(address(0));

        assertEq(rescuable.rescuer(), address(0));
    }

    function testUpdateRescuer_idempotent() public {
        rescuable.initialize(owner, rescuerAddr);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false, address(rescuable));
        emit Rescuable.RescuerChanged(rescuerAddr, rescuerAddr);
        rescuable.updateRescuer(rescuerAddr);

        assertEq(rescuable.rescuer(), rescuerAddr);
    }

    // ─── Helpers ───

    function _fundRescuable() internal {
        token = new MockERC20("USD Coin", "USDC");
        token.mint(address(rescuable), RESCUE_AMOUNT);
    }
}

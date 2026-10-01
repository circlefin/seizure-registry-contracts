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

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";

contract ERC1967ProxyHarness is ERC1967Proxy {
    constructor(address impl, bytes memory data) ERC1967Proxy(impl, data) {}

    function implementation() public view returns (address) {
        return _implementation();
    }
}

contract UpgradeablePlaceholderTest is Test {
    address private _owner = makeAddr("owner");

    UpgradeablePlaceholder private _impl;
    UpgradeablePlaceholder private _placeholder;
    ERC1967ProxyHarness private _proxy;

    function setUp() public {
        _impl = new UpgradeablePlaceholder();
        _proxy = new ERC1967ProxyHarness(address(_impl), abi.encodeCall(UpgradeablePlaceholder.initialize, (_owner)));
        _placeholder = UpgradeablePlaceholder(address(_proxy));
    }

    // ============ owner ============

    function test_owner_setCorrectlyAfterInitialize() public view {
        assertEq(_placeholder.owner(), _owner);
    }

    // ============ initialize ============

    function test_initialize_revertWhenReInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        vm.prank(_owner);
        _placeholder.initialize(_owner);
    }

    function test_initialize_revertIfOwnerIsZeroAddress() public {
        UpgradeablePlaceholder newImpl = new UpgradeablePlaceholder();
        vm.expectRevert(abi.encodeWithSelector(UpgradeablePlaceholder.NullOwnerNotAllowed.selector));
        new ERC1967ProxyHarness(address(newImpl), abi.encodeCall(UpgradeablePlaceholder.initialize, (address(0))));
    }

    // ============ transferOwnership ============

    function test_transferOwnership_success() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(_owner);
        _placeholder.transferOwnership(newOwner);

        assertEq(_placeholder.owner(), _owner, "Owner should not change before acceptance");
        assertEq(_placeholder.pendingOwner(), newOwner, "Pending owner should be set");

        vm.prank(newOwner);
        _placeholder.acceptOwnership();

        assertEq(_placeholder.owner(), newOwner, "Owner should be updated after acceptance");
        assertEq(_placeholder.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function test_transferOwnership_idempotent() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(_owner);
        _placeholder.transferOwnership(newOwner);

        vm.prank(_owner);
        _placeholder.transferOwnership(newOwner);

        assertEq(_placeholder.owner(), _owner, "Owner should be unchanged");
        assertEq(_placeholder.pendingOwner(), newOwner, "Pending owner should still be set");
    }

    function test_transferOwnership_revertIfNotOwner() public {
        address random = makeAddr("random");
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, random));
        vm.prank(random);
        _placeholder.transferOwnership(random);
    }

    // ============ upgradeToAndCall ============

    function test_upgradeToAndCall_success() public {
        address newImpl = address(new UpgradeablePlaceholder());

        vm.prank(_owner);
        _placeholder.upgradeToAndCall(newImpl, "");

        assertEq(_proxy.implementation(), newImpl, "Implementation should be updated");
    }

    function test_upgradeToAndCall_revertIfNotOwner() public {
        address random = makeAddr("random");
        address newImpl = address(new UpgradeablePlaceholder());

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, random));
        vm.prank(random);
        _placeholder.upgradeToAndCall(newImpl, "");
    }
}

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
import {Test} from "forge-std/Test.sol";
import {UnauthorizedCaller, ZeroAddress} from "src/common/Errors.sol";
import {HashUpdatable, HashUpdatableStorage} from "src/modules/HashUpdatable.sol";
import {SecondaryMarketBurnableStorage} from "src/modules/SecondaryMarketBurnable.sol";
import {Immutables} from "src/modules/Immutables.sol";

// ============ Test Harnesses ============

/// @dev Base harness — does NOT call __HashUpdatable_init; hashUpdater starts at address(0)
contract HashUpdatableHarness is HashUpdatable {
    constructor(address token_) Immutables(token_) {}

    function initialize(address owner_) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
    }

    function verifyOnlyHashUpdaterModifier() public onlyHashUpdater {}

    /// @dev Writes a RemintRecord directly to storage, simulating secondaryMarketBurnAndRemint
    function writeRemintRecordForTest(bytes calldata addr, uint32 domain, uint256 balance) external {
        SecondaryMarketBurnableStorage.get().records[domain][addr] =
            SecondaryMarketBurnableStorage.RemintRecord({balance: balance, remintRecipient: address(1)});
    }

    /// @dev Exposes the stored remint tx hash so tests don't read from the wrong EVM context
    function getRemintTxHashForTest(bytes calldata addr, uint32 domain) external view returns (bytes32) {
        return HashUpdatableStorage.get().remintTxHashes[domain][addr];
    }
}

/// @dev Harness that calls __HashUpdatable_init during initialization
contract HashUpdatableHarnessWithInit is HashUpdatable {
    constructor(address token_) Immutables(token_) {}

    function initialize(address owner_, address hashUpdater_) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
        __HashUpdatable_init(hashUpdater_);
    }

    function verifyOnlyHashUpdaterModifier() public onlyHashUpdater {}

    /// @dev Writes a RemintRecord directly to storage, simulating secondaryMarketBurnAndRemint
    function writeRemintRecordForTest(bytes calldata addr, uint32 domain, uint256 balance) external {
        SecondaryMarketBurnableStorage.get().records[domain][addr] =
            SecondaryMarketBurnableStorage.RemintRecord({balance: balance, remintRecipient: address(1)});
    }

    /// @dev Exposes the stored remint tx hash so tests don't read from the wrong EVM context
    function getRemintTxHashForTest(bytes calldata addr, uint32 domain) external view returns (bytes32) {
        return HashUpdatableStorage.get().remintTxHashes[domain][addr];
    }
}

/// @dev Harness that supports reinitialization to simulate an upgrade re-running the module init
contract HashUpdatableHarnessWithReinit is HashUpdatable {
    constructor(address token_) Immutables(token_) {}

    function initialize(address owner_, address hashUpdater_) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
        __HashUpdatable_init(hashUpdater_);
    }

    function reinit(address newHashUpdater_) public reinitializer(2) {
        __HashUpdatable_init(newHashUpdater_);
    }

    function verifyOnlyHashUpdaterModifier() public onlyHashUpdater {}

    /// @dev Writes a RemintRecord directly to storage, simulating secondaryMarketBurnAndRemint
    function writeRemintRecordForTest(bytes calldata addr, uint32 domain, uint256 balance) external {
        SecondaryMarketBurnableStorage.get().records[domain][addr] =
            SecondaryMarketBurnableStorage.RemintRecord({balance: balance, remintRecipient: address(1)});
    }

    /// @dev Exposes the stored remint tx hash so tests don't read from the wrong EVM context
    function getRemintTxHashForTest(bytes calldata addr, uint32 domain) external view returns (bytes32) {
        return HashUpdatableStorage.get().remintTxHashes[domain][addr];
    }
}

// ============ Tests ============

contract HashUpdatableTest is Test {
    /// @dev address(1) is a valid non-zero token address; no minting occurs in these unit tests
    address private constant DUMMY_TOKEN = address(1);

    HashUpdatableHarness private _hashUpdatable;

    address private _owner = makeAddr("owner");
    address private _hashUpdater = makeAddr("hashUpdater");
    address private _other = makeAddr("other");

    bytes private _addr = abi.encodePacked(makeAddr("burnedAddress"));
    bytes private _otherAddr = abi.encodePacked(makeAddr("otherBurnedAddress"));
    uint32 private _domain = 1;
    bytes32 private _txHash = keccak256("txHash");
    bytes32 private _otherTxHash = keccak256("otherTxHash");

    function setUp() public {
        _hashUpdatable = new HashUpdatableHarness(DUMMY_TOKEN);
        _hashUpdatable.initialize(_owner);
    }

    // ============ Storage Slot ============

    function test_storageSlot_correctlyCalculated() public pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.HashUpdatable"))) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(HashUpdatableStorage.SLOT, expected, "Storage slot should match EIP-7201 calculation");
    }

    // ============ Initial State ============

    function test_initialState_hashUpdaterIsZero() public view {
        assertEq(_hashUpdatable.hashUpdater(), address(0));
    }

    function test_initialState_ownerIsSet() public view {
        assertEq(_hashUpdatable.owner(), _owner);
    }

    function test_initialState_onlyHashUpdaterRevertsForAnyCallerWhenUnset() public {
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_hashUpdater);
        _hashUpdatable.verifyOnlyHashUpdaterModifier();
    }

    // ============ Initialization ============

    function test_hashUpdatableInit_setsHashUpdaterDuringInitialization() public {
        HashUpdatableHarnessWithInit h = new HashUpdatableHarnessWithInit(DUMMY_TOKEN);

        vm.expectEmit(true, true, false, false, address(h));
        emit HashUpdatable.HashUpdaterChanged(address(0), _hashUpdater);
        h.initialize(_owner, _hashUpdater);

        assertEq(h.hashUpdater(), _hashUpdater, "Hash updater should be set during initialization");
        assertEq(h.owner(), _owner, "Owner should be set during initialization");

        h.writeRemintRecordForTest(_addr, _domain, 100e6);
        vm.prank(_hashUpdater);
        h.setRemintTxHash(_addr, _domain, _txHash);
        assertEq(
            h.getRemintTxHashForTest(_addr, _domain), _txHash, "Remint tx hash should be set for address and domain"
        );
    }

    function test_reinit_emitsOldHashUpdaterNonZero() public {
        HashUpdatableHarnessWithReinit h = new HashUpdatableHarnessWithReinit(DUMMY_TOKEN);
        h.initialize(_owner, _hashUpdater);
        assertEq(h.hashUpdater(), _hashUpdater, "Initial hash updater should be set");

        address newHashUpdater = makeAddr("newHashUpdater");

        vm.expectEmit(true, true, false, false, address(h));
        emit HashUpdatable.HashUpdaterChanged(_hashUpdater, newHashUpdater);
        h.reinit(newHashUpdater);

        assertEq(h.hashUpdater(), newHashUpdater, "Hash updater should be updated during reinit");

        h.writeRemintRecordForTest(_addr, _domain, 100e6);
        vm.prank(newHashUpdater);
        h.setRemintTxHash(_addr, _domain, _txHash);
        assertEq(
            h.getRemintTxHashForTest(_addr, _domain), _txHash, "Remint tx hash should be set for address and domain"
        );
    }

    function test_init_revertIfZeroHashUpdater() public {
        HashUpdatableHarnessWithInit h = new HashUpdatableHarnessWithInit(DUMMY_TOKEN);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        h.initialize(_owner, address(0));
    }

    // ============ updateHashUpdater ============

    function test_updateHashUpdater_basicSuccess() public {
        vm.expectEmit(true, true, false, false, address(_hashUpdatable));
        emit HashUpdatable.HashUpdaterChanged(address(0), _hashUpdater);

        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);

        assertEq(_hashUpdatable.hashUpdater(), _hashUpdater);

        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);
        vm.prank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _txHash);
        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            _txHash,
            "Hash updater should be able to set remint tx hash"
        );
    }

    function test_updateHashUpdater_changeHashUpdater() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);

        address newHashUpdater = makeAddr("newHashUpdater");

        vm.expectEmit(true, true, false, false, address(_hashUpdatable));
        emit HashUpdatable.HashUpdaterChanged(_hashUpdater, newHashUpdater);

        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(newHashUpdater);

        assertEq(_hashUpdatable.hashUpdater(), newHashUpdater);

        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);
        vm.prank(newHashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _txHash);
        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            _txHash,
            "New hash updater should be able to set remint tx hash"
        );

        // old hash updater can no longer call gated functions
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_hashUpdater);
        _hashUpdatable.verifyOnlyHashUpdaterModifier();
    }

    function test_updateHashUpdater_isIdempotent() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);

        vm.expectEmit(true, true, false, false, address(_hashUpdatable));
        emit HashUpdatable.HashUpdaterChanged(_hashUpdater, _hashUpdater);

        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);

        assertEq(_hashUpdatable.hashUpdater(), _hashUpdater);

        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);
        vm.prank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _txHash);
        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            _txHash,
            "Hash updater should still be able to set remint tx hash"
        );
    }

    function test_updateHashUpdater_revertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(address(0));
    }

    function test_updateHashUpdater_revertIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _other));
        vm.prank(_other);
        _hashUpdatable.updateHashUpdater(_hashUpdater);
    }

    // ============ onlyHashUpdater ============

    function test_onlyHashUpdater_success() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);

        vm.prank(_hashUpdater);
        _hashUpdatable.verifyOnlyHashUpdaterModifier();
    }

    function test_onlyHashUpdater_revertIfNotHashUpdater() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_other);
        _hashUpdatable.verifyOnlyHashUpdaterModifier();
    }

    // ============ hashUpdater ============

    function test_hashUpdater_returnsCorrectValue() public {
        assertEq(_hashUpdatable.hashUpdater(), address(0), "Hash updater should be zero initially");

        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);
        assertEq(_hashUpdatable.hashUpdater(), _hashUpdater, "Hash updater should reflect the set address");

        address newHashUpdater = makeAddr("newHashUpdater");
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(newHashUpdater);
        assertEq(_hashUpdatable.hashUpdater(), newHashUpdater, "Hash updater should reflect the latest update");
    }

    // ============ setRemintTxHash ============

    function test_setRemintTxHash_success() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);
        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);

        vm.expectEmit(false, true, false, true, address(_hashUpdatable));
        emit HashUpdatable.RemintTxHashUpdated(_addr, _domain, _txHash);

        vm.prank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _txHash);

        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            _txHash,
            "Remint tx hash should be stored for address and domain"
        );
    }

    function test_setRemintTxHash_doesNotAffectOtherDomains() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);

        uint32 otherDomain = 2;
        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);
        _hashUpdatable.writeRemintRecordForTest(_addr, otherDomain, 200e6);

        vm.startPrank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _txHash);
        _hashUpdatable.setRemintTxHash(_addr, otherDomain, _otherTxHash);
        vm.stopPrank();

        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            _txHash,
            "Correct remint tx hash should be set for address and domain"
        );
        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, otherDomain),
            _otherTxHash,
            "Correct remint tx hash should be set for address and other domain"
        );
    }

    function test_setRemintTxHash_doesNotAffectOtherAddresses() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);

        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);
        _hashUpdatable.writeRemintRecordForTest(_otherAddr, _domain, 200e6);

        vm.startPrank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _txHash);
        _hashUpdatable.setRemintTxHash(_otherAddr, _domain, _otherTxHash);
        vm.stopPrank();

        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            _txHash,
            "Correct remint tx hash should be set for address and domain"
        );
        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_otherAddr, _domain),
            _otherTxHash,
            "Correct remint tx hash should be set for other address and domain"
        );
    }

    function test_setRemintTxHash_canUpdateExistingHash() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);
        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);

        vm.prank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _txHash);

        vm.expectEmit(false, true, false, true, address(_hashUpdatable));
        emit HashUpdatable.RemintTxHashUpdated(_addr, _domain, _otherTxHash);

        vm.prank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _otherTxHash);

        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            _otherTxHash,
            "Remint tx hash should be updated to new value for address and domain"
        );
    }

    function test_setRemintTxHash_revertIfZeroHash() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);
        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);

        vm.expectRevert(abi.encodeWithSelector(HashUpdatable.ZeroHash.selector));
        vm.prank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, bytes32(0));

        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            bytes32(0),
            "Remint tx hash should still be zero (never set)"
        );
    }

    function test_setRemintTxHash_revertIfRecordNotFound() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);

        vm.expectRevert(abi.encodeWithSelector(HashUpdatable.RecordNotFound.selector));
        vm.prank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _txHash);

        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            bytes32(0),
            "Remint tx hash should still be zero (never set)"
        );
    }

    function test_setRemintTxHash_revertIfRecordExistsOnDifferentDomain() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);
        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);

        uint32 wrongDomain = 999;
        vm.expectRevert(abi.encodeWithSelector(HashUpdatable.RecordNotFound.selector));
        vm.prank(_hashUpdater);
        _hashUpdatable.setRemintTxHash(_addr, wrongDomain, _txHash);

        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, wrongDomain),
            bytes32(0),
            "Remint tx hash on wrong domain should still be zero"
        );
        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            bytes32(0),
            "Remint tx hash on correct domain should also still be zero (never set)"
        );
    }

    function test_setRemintTxHash_revertIfNotHashUpdater() public {
        vm.prank(_owner);
        _hashUpdatable.updateHashUpdater(_hashUpdater);
        _hashUpdatable.writeRemintRecordForTest(_addr, _domain, 100e6);

        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_other);
        _hashUpdatable.setRemintTxHash(_addr, _domain, _txHash);

        assertEq(
            _hashUpdatable.getRemintTxHashForTest(_addr, _domain),
            bytes32(0),
            "Remint tx hash should still be zero (never set)"
        );
    }
}

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
import {IMintableToken} from "src/interfaces/IMintableToken.sol";
import {Allowlistable} from "src/modules/Allowlistable.sol";
import {Immutables} from "src/modules/Immutables.sol";
import {SecondaryMarketBurnable, SecondaryMarketBurnableStorage} from "src/modules/SecondaryMarketBurnable.sol";
import {MasterMinter} from "test/mocks/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "test/mocks/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "test/mocks/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployMockFiatToken} from "test/util/DeployMockFiatToken.sol";

// ============ Mock Contracts ============

/// @dev IMintableToken implementation whose mint always returns false (never reverts) to exercise the MintFailed guard
contract MockFiatTokenReturnsFalse is IMintableToken {
    function mint(address, uint256) external pure returns (bool) {
        return false;
    }
}

// ============ Test Harnesses ============

/// @dev Base harness — does NOT call __SecondaryMarketBurnable_init; role starts at address(0)
contract SecondaryMarketBurnableHarness is SecondaryMarketBurnable {
    constructor(address token_) Immutables(token_) {}

    function initialize(address owner_) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
    }

    function exposeEnsureNotAlreadySecondaryMarketBurned(bytes calldata addr, uint32 domain) external view {
        _ensureNotAlreadySecondaryMarketBurned(addr, domain);
    }

    function verifyOnlySecondaryMarketBurnerModifier() public onlySecondaryMarketBurner {}
}

/// @dev Harness that calls __SecondaryMarketBurnable_init during initialization
contract SecondaryMarketBurnableHarnessWithInit is SecondaryMarketBurnable {
    constructor(address token_) Immutables(token_) {}

    function initialize(address owner_, address secondaryMarketBurner_) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
        __SecondaryMarketBurnable_init(secondaryMarketBurner_);
    }

    function verifyOnlySecondaryMarketBurnerModifier() public onlySecondaryMarketBurner {}
}

/// @dev Harness that supports reinitialization to simulate an upgrade re-running the module init
contract SecondaryMarketBurnableHarnessWithReinit is SecondaryMarketBurnable {
    constructor(address token_) Immutables(token_) {}

    function initialize(address owner_, address secondaryMarketBurner_) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
        __SecondaryMarketBurnable_init(secondaryMarketBurner_);
    }

    function reinit(address newSecondaryMarketBurner) public reinitializer(2) {
        __SecondaryMarketBurnable_init(newSecondaryMarketBurner);
    }

    function verifyOnlySecondaryMarketBurnerModifier() public onlySecondaryMarketBurner {}
}

// ============ Tests ============

contract SecondaryMarketBurnableTest is Test {
    // ---- Token infrastructure ----
    DeployMockFiatToken private usdc;
    FiatTokenV2_2 private _token;
    MasterMinter private _masterMinter;

    // ---- Registry harness ----
    SecondaryMarketBurnableHarness private _secondaryMarketBurnable;

    address private _owner = makeAddr("owner");
    address private _secondaryMarketBurner = makeAddr("secondaryMarketBurner");
    address private _addressManager = makeAddr("addressManager");
    address private _recipient = makeAddr("recipient");
    address private _otherRecipient = makeAddr("otherRecipient");
    address private _other = makeAddr("other");

    bytes private _secondaryMarketBurnedAddress = hex"1234";
    bytes private _otherSecondaryMarketBurnedAddress = hex"5678";
    uint32 private _domain = 1;
    uint32 private _otherDomain = 2;
    uint256 private _balance = 1_000_000;
    uint256 private _otherBalance = 2_000_000;

    // ============ Helpers ============

    function setUp() public {
        usdc = new DeployMockFiatToken();
        FiatTokenProxy proxy;
        (, _masterMinter, proxy) = usdc.deploy();
        _token = FiatTokenV2_2(address(proxy));

        _secondaryMarketBurnable = new SecondaryMarketBurnableHarness(address(_token));
        _secondaryMarketBurnable.initialize(_owner);

        // masterMinterOwner configures itself as the controller for the registry minter,
        // with initial allowance 0 (funded per operation).
        vm.startPrank(usdc.masterMinterOwner());
        _masterMinter.configureController(usdc.masterMinterOwner(), address(_secondaryMarketBurnable));
        _masterMinter.configureMinter(0);
        vm.stopPrank();
    }

    /// @dev Sets the address manager and allowlists `recipient`
    function _allowlist(address recipient) private {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateAddressManager(_addressManager);
        vm.prank(_addressManager);
        _secondaryMarketBurnable.addAllowedRecipient(recipient);
    }

    /// @dev Full setup: sets the SMBurner role, allowlists `_recipient`, and pre-funds the minter allowance.
    function _setup() private {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        _allowlist(_recipient);
        _prefundAllowance(_balance);
    }

    /// @dev Simulates the minter-controller pre-funding the registry's minter allowance.
    ///      In production a dedicated minterController role calls MasterMinter.incrementMinterAllowance.
    function _prefundAllowance(uint256 amount) private {
        vm.prank(usdc.masterMinterOwner());
        _masterMinter.incrementMinterAllowance(amount);
    }

    // ============ Storage Slots ============

    function test_storageSlot_correctlyCalculated() public pure {
        bytes32 expected = keccak256(
            abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.SecondaryMarketBurnable"))) - 1)
        ) & ~bytes32(uint256(0xff));
        assertEq(SecondaryMarketBurnableStorage.SLOT, expected, "Storage slot should match EIP-7201 calculation");
    }

    // ============ Initial State ============

    function test_initialState_secondaryMarketBurnerIsZero() public view {
        assertEq(_secondaryMarketBurnable.secondaryMarketBurner(), address(0));
    }

    function test_initialState_ownerIsSet() public view {
        assertEq(_secondaryMarketBurnable.owner(), _owner);
    }

    function test_initialState_noAddressIsBurned() public {
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.verifyOnlySecondaryMarketBurnerModifier();

        assertFalse(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "No address should be secondary market burned"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(),
            0,
            "Total secondary market burned amount should be 0"
        );
    }

    // ============ Initialization ============

    function test_secondaryMarketBurnableInit_setsRoleDuringInitialization() public {
        DeployMockFiatToken usdc2 = new DeployMockFiatToken();
        FiatTokenProxy proxy2;
        MasterMinter mm2;
        (, mm2, proxy2) = usdc2.deploy();
        FiatTokenV2_2 token2 = FiatTokenV2_2(address(proxy2));

        SecondaryMarketBurnableHarnessWithInit secondaryMarketBurnableWithInit =
            new SecondaryMarketBurnableHarnessWithInit(address(token2));
        secondaryMarketBurnableWithInit.initialize(_owner, _secondaryMarketBurner);

        assertEq(secondaryMarketBurnableWithInit.secondaryMarketBurner(), _secondaryMarketBurner);
        assertEq(secondaryMarketBurnableWithInit.owner(), _owner);

        vm.startPrank(usdc2.masterMinterOwner());
        mm2.configureController(usdc2.masterMinterOwner(), address(secondaryMarketBurnableWithInit));
        mm2.configureMinter(0);
        mm2.incrementMinterAllowance(_balance);
        vm.stopPrank();

        vm.prank(_owner);
        secondaryMarketBurnableWithInit.updateAddressManager(_addressManager);
        vm.prank(_addressManager);
        secondaryMarketBurnableWithInit.addAllowedRecipient(_recipient);

        vm.prank(_secondaryMarketBurner);
        secondaryMarketBurnableWithInit.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
        assertTrue(
            secondaryMarketBurnableWithInit.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "Address should be secondary market burned"
        );
    }

    function test_reinit_emitsOldSecondaryMarketBurnerNonZero() public {
        SecondaryMarketBurnableHarnessWithReinit secondaryMarketBurnableWithReinit =
            new SecondaryMarketBurnableHarnessWithReinit(address(_token));
        secondaryMarketBurnableWithReinit.initialize(_owner, _secondaryMarketBurner);
        assertEq(
            secondaryMarketBurnableWithReinit.secondaryMarketBurner(),
            _secondaryMarketBurner,
            "Initial secondary market burner should be set"
        );

        address newSecondaryMarketBurner = makeAddr("newSecondaryMarketBurner");
        vm.expectEmit(true, true, false, false, address(secondaryMarketBurnableWithReinit));
        emit SecondaryMarketBurnable.SecondaryMarketBurnerChanged(_secondaryMarketBurner, newSecondaryMarketBurner);
        secondaryMarketBurnableWithReinit.reinit(newSecondaryMarketBurner);

        assertEq(
            secondaryMarketBurnableWithReinit.secondaryMarketBurner(),
            newSecondaryMarketBurner,
            "Secondary market burner should be updated during reinit"
        );
    }

    function test_init_revertIfZeroSecondaryMarketBurner() public {
        SecondaryMarketBurnableHarnessWithInit secondaryMarketBurnableWithInit =
            new SecondaryMarketBurnableHarnessWithInit(address(_token));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        secondaryMarketBurnableWithInit.initialize(_owner, address(0));
    }

    // ============ updateSecondaryMarketBurner ============

    function test_updateSecondaryMarketBurner_basicSuccess() public {
        vm.expectEmit(true, true, false, false, address(_secondaryMarketBurnable));
        emit SecondaryMarketBurnable.SecondaryMarketBurnerChanged(address(0), _secondaryMarketBurner);

        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);

        assertEq(_secondaryMarketBurnable.secondaryMarketBurner(), _secondaryMarketBurner);

        // Confirm the new burner can execute the core operation end-to-end
        _allowlist(_recipient);
        _prefundAllowance(_balance);
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "Secondary market burner should be able to execute secondary market burn and remint"
        );
    }

    function test_updateSecondaryMarketBurner_changeSecondaryMarketBurner() public {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);

        address newSecondaryMarketBurner = makeAddr("newSecondaryMarketBurner");
        vm.expectEmit(true, true, false, false, address(_secondaryMarketBurnable));
        emit SecondaryMarketBurnable.SecondaryMarketBurnerChanged(_secondaryMarketBurner, newSecondaryMarketBurner);

        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(newSecondaryMarketBurner);

        assertEq(_secondaryMarketBurnable.secondaryMarketBurner(), newSecondaryMarketBurner);

        // Old burner can no longer execute burns
        _allowlist(_recipient);
        _prefundAllowance(_balance);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );

        // New burner can execute burns
        vm.prank(newSecondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "New secondary market burner should be able to execute secondary market burn and remint"
        );
    }

    function test_updateSecondaryMarketBurner_isIdempotent() public {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);

        vm.expectEmit(true, true, false, false, address(_secondaryMarketBurnable));
        emit SecondaryMarketBurnable.SecondaryMarketBurnerChanged(_secondaryMarketBurner, _secondaryMarketBurner);

        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        assertEq(_secondaryMarketBurnable.secondaryMarketBurner(), _secondaryMarketBurner);

        // Burner is still effective after the idempotent update
        _allowlist(_recipient);
        _prefundAllowance(_balance);
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "Secondary market burner is still effective after the idempotent update"
        );
    }

    function test_updateSecondaryMarketBurner_revertIfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(address(0));
    }

    function test_updateSecondaryMarketBurner_revertIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _other));
        vm.prank(_other);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
    }

    // ============ onlySecondaryMarketBurner ============

    function test_onlySecondaryMarketBurner_success() public {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.verifyOnlySecondaryMarketBurnerModifier();
    }

    function test_onlySecondaryMarketBurner_revertIfNotSecondaryMarketBurner() public {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_other);
        _secondaryMarketBurnable.verifyOnlySecondaryMarketBurnerModifier();
    }

    // ============ secondaryMarketBurnAndRemint ============

    function test_secondaryMarketBurnAndRemint_basicSuccess() public {
        _setup();

        vm.expectEmit(false, true, false, false, address(_secondaryMarketBurnable));
        emit SecondaryMarketBurnable.SecondaryMarketBurnRecorded(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );

        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );

        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "Address should be secondary market burned"
        );
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurnedBalance(_secondaryMarketBurnedAddress, _domain),
            _balance,
            "Secondary market burned balance recorded should be equal to the balance we secondary market burned"
        );
        assertEq(_token.balanceOf(_recipient), _balance, "Recipient should receive the re-minted balance");

        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(),
            _balance,
            "Total secondary market burned amount should be equal to the balance we secondary market burned"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(_domain),
            _balance,
            "Total secondary market burned amount for domain should be equal to the balance we secondary market burned"
        );
    }

    function test_secondaryMarketBurnAndRemint_allowanceLifecycle() public {
        // This is more of a clarification of the minter allowance lifecycle for the contract (hidden in other tests through the _setup() function)
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        _allowlist(_recipient);

        // Before: registry minter allowance is 0
        assertEq(
            _token.minterAllowance(address(_secondaryMarketBurnable)),
            0,
            "Minter allowance should be 0 before minter-controller acts"
        );

        // Minter-controller pre-funds the allowance (test contract is the controller).
        _prefundAllowance(_balance);
        assertEq(
            _token.minterAllowance(address(_secondaryMarketBurnable)),
            _balance,
            "Minter allowance should equal balance after pre-funding"
        );

        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );

        // After: FiatToken.mint consumed the minter allowance — back to 0
        assertEq(
            _token.minterAllowance(address(_secondaryMarketBurnable)),
            0,
            "Minter allowance should be 0 after mint consumes it"
        );
        assertEq(_token.balanceOf(_recipient), _balance, "Recipient should receive the re-minted balance");
    }

    function test_secondaryMarketBurnAndRemint_mintFailsWithoutAllowance() public {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        _allowlist(_recipient);
        // No _prefundAllowance — allowance remains 0

        vm.expectRevert("FiatToken: mint amount exceeds minterAllowance");
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );

        // CEI: storage writes happen before token.mint, but a revert in mint rolls back the entire tx.
        assertFalse(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "Address should not be secondary market burned, as the re-mint fails"
        );
    }

    function test_secondaryMarketBurnAndRemint_separateDomainsForSameAddress() public {
        _setup();

        // Pre-fund the allowance for the second secondary market burn
        _prefundAllowance(_otherBalance);

        vm.startPrank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _otherDomain, _otherBalance, _recipient
        );
        vm.stopPrank();

        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "Address should be secondary market burned for domain"
        );
        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _otherDomain),
            "Address should be secondary market burned for other domain"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(),
            _balance + _otherBalance,
            "Total secondary market burned amount should be equal to the balance we secondary market burned for domain plus the balance we secondary market burned for other domain"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(_domain),
            _balance,
            "Total secondary market burned amount for domain should be equal to the balance we secondary market burned for domain"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(_otherDomain),
            _otherBalance,
            "Total secondary market burned amount for other domain should be equal to the balance we secondary market burned for other domain"
        );
        assertEq(
            _token.balanceOf(_recipient), _balance + _otherBalance, "Recipient should receive the re-minted balances"
        );
    }

    function test_secondaryMarketBurnAndRemint_revertIfEmptyAddress() public {
        _setup();
        vm.expectRevert(abi.encodeWithSelector(SecondaryMarketBurnable.EmptyAddress.selector));
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(hex"", _domain, _balance, _recipient);
    }

    function test_secondaryMarketBurnAndRemint_revertIfZeroBalance() public {
        _setup();
        vm.expectRevert(abi.encodeWithSelector(SecondaryMarketBurnable.ZeroBalance.selector));
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(_secondaryMarketBurnedAddress, _domain, 0, _recipient);
    }

    function test_secondaryMarketBurnAndRemint_revertIfRecipientNotAllowed() public {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        vm.expectRevert(abi.encodeWithSelector(Allowlistable.RecipientNotAllowed.selector, _recipient));
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
    }

    function test_secondaryMarketBurnAndRemint_revertIfZeroRecipient() public {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        vm.expectRevert(abi.encodeWithSelector(Allowlistable.RecipientNotAllowed.selector, address(0)));
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, address(0)
        );
    }

    function test_secondaryMarketBurnAndRemint_revertIfAlreadyBurned() public {
        _setup();
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );

        _prefundAllowance(_balance);
        vm.expectRevert(
            abi.encodeWithSelector(
                SecondaryMarketBurnable.AlreadySecondaryMarketBurned.selector, _secondaryMarketBurnedAddress, _domain
            )
        );
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
    }

    function test_secondaryMarketBurnAndRemint_revertIfNotSecondaryMarketBurner() public {
        _setup();
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        vm.prank(_other);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
    }

    function test_secondaryMarketBurnAndRemint_revertsAtomicallyIfMintFails() public {
        _setup();
        // Burn the allowance so the mint will fail inside secondaryMarketBurnAndRemint
        assertEq(
            _token.minterAllowance(address(_secondaryMarketBurnable)),
            _balance,
            "Minter allowance should be equal to the balance we secondary market burned"
        );
        // Drain the allowance by minting directly first (simulating a race / double-spend scenario)
        vm.prank(address(_secondaryMarketBurnable));
        _token.mint(_other, _balance);
        assertEq(
            _token.minterAllowance(address(_secondaryMarketBurnable)),
            0,
            "Minter allowance should drop to 0 after minting directly"
        );

        vm.expectRevert("FiatToken: mint amount exceeds minterAllowance");
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );

        // CEI: storage writes happen before token.mint, but a revert in mint rolls back the entire tx.
        assertFalse(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "Address should not be secondary market burned, as the token mint portion of the function fails"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(),
            0,
            "Total secondary market burned amount should be 0"
        );
    }

    function test_secondaryMarketBurnAndRemint_revertIfMintReturnsFalse() public {
        MockFiatTokenReturnsFalse mockToken = new MockFiatTokenReturnsFalse();
        SecondaryMarketBurnableHarness harness = new SecondaryMarketBurnableHarness(address(mockToken));
        harness.initialize(_owner);
        vm.prank(_owner);
        harness.updateSecondaryMarketBurner(_secondaryMarketBurner);
        vm.prank(_owner);
        harness.updateAddressManager(_addressManager);
        vm.prank(_addressManager);
        harness.addAllowedRecipient(_recipient);

        vm.expectRevert(abi.encodeWithSelector(SecondaryMarketBurnable.MintFailed.selector));
        vm.prank(_secondaryMarketBurner);
        harness.secondaryMarketBurnAndRemint(_secondaryMarketBurnedAddress, _domain, _balance, _recipient);
    }

    // ============ _ensureNotAlreadySecondaryMarketBurned ============

    function test_ensureNotAlreadySecondaryMarketBurned_success() public view {
        _secondaryMarketBurnable.exposeEnsureNotAlreadySecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain);
    }

    function test_ensureNotAlreadySecondaryMarketBurned_revertIfAlreadyBurned() public {
        _setup();
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SecondaryMarketBurnable.AlreadySecondaryMarketBurned.selector, _secondaryMarketBurnedAddress, _domain
            )
        );
        _secondaryMarketBurnable.exposeEnsureNotAlreadySecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain);
    }

    // ============ isSecondaryMarketBurned / secondaryMarketBurnedBalance ============

    function test_isSecondaryMarketBurned_returnsCorrectStatus() public {
        _setup();
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );

        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _domain),
            "Address should be secondary market burned for domain"
        );
        assertFalse(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_otherSecondaryMarketBurnedAddress, _domain),
            "Other address should not be secondary market burned for domain"
        );
        assertFalse(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_secondaryMarketBurnedAddress, _otherDomain),
            "Address should not be secondary market burned for other domain"
        );
    }

    function test_secondaryMarketBurnedBalance_returnsCorrectStatus() public {
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurnedBalance(_secondaryMarketBurnedAddress, _domain),
            0,
            "Secondary market burned balance should be 0 for address and domain"
        );

        _setup();
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurnedBalance(_secondaryMarketBurnedAddress, _domain),
            _balance,
            "Secondary market burned balance should be equal to the balance we secondary market burned for address and domain"
        );
    }

    function test_isSecondaryMarketBurned_evmAddressOverload_matchesBytesOverload() public {
        address evmAddr = address(0x55FE002aefF02F77364de339a1292923A15844B8);
        bytes memory evmBytes = abi.encodePacked(evmAddr);

        _setup();
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(evmBytes, _domain, _balance, _recipient);

        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(evmAddr, _domain),
            "EVM address overload should return true after burn"
        );
        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(evmBytes, _domain),
            "EVM bytes overload should return true after burn"
        );
        assertFalse(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_other, _domain), "Different address should return false"
        );

        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurnedBalance(evmAddr, _domain),
            _balance,
            "EVM address overload should return correct balance"
        );
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurnedBalance(evmBytes, _domain),
            _balance,
            "EVM bytes overload should return correct balance"
        );
    }

    // ============ totalSecondaryMarketBurnedAmount ============

    function test_totalSecondaryMarketBurnedAmount_returnsCorrectStatus() public {
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(),
            0,
            "Total secondary market burned amount should be 0"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(_domain),
            0,
            "Total secondary market burned amount for domain should be 0"
        );

        _setup();
        _prefundAllowance(_otherBalance); // second secondary market burn needs its own allowance

        vm.startPrank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _secondaryMarketBurnedAddress, _domain, _balance, _recipient
        );
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(
            _otherSecondaryMarketBurnedAddress, _otherDomain, _otherBalance, _recipient
        );
        vm.stopPrank();

        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(),
            _balance + _otherBalance,
            "Total secondary market burned amount should be equal to the balance we secondary market burned for domain plus the balance we secondary market burned for other domain"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(_domain),
            _balance,
            "Total secondary market burned amount for domain should be equal to the balance we secondary market burned for domain"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(_otherDomain),
            _otherBalance,
            "Total secondary market burned amount for other domain should be equal to the balance we secondary market burned for other domain"
        );
    }

    // ============ secondaryMarketBurner getter ============

    function test_secondaryMarketBurner_returnsCorrectStatus() public {
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurner(),
            address(0),
            "Secondary market burner should be 0 initially"
        );

        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurner(),
            _secondaryMarketBurner,
            "Secondary market burner should be equal to the secondary market burner we set"
        );

        address newSecondaryMarketBurner = makeAddr("newSecondaryMarketBurner");
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(newSecondaryMarketBurner);
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurner(),
            newSecondaryMarketBurner,
            "Secondary market burner should be equal to the new secondary market burner we set"
        );
    }

    // ============ Per-Chain SMB Tests ============
    //
    // The `secondaryMarketBurnedAddress` field is raw bytes — the canonical binary
    // representation of the address, decoded off-chain before submission.
    // Domain IDs are from docs/domains.md in chain-expansion-scripts.
    // Each non-EVM chain gets its own test because address encoding differs;
    // all EVM chains share the same 20-byte format so they are covered by a single test.

    /// @dev Runs a successful SMB assertion for a given chain address and domain.
    function _assertSMBSucceeds(bytes memory chainAddress, uint32 domain) private {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        _allowlist(_recipient);
        _prefundAllowance(_balance);

        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(chainAddress, domain, _balance, _recipient);

        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(chainAddress, domain),
            "Address should be secondary market burned for chain and domain"
        );
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurnedBalance(chainAddress, domain),
            _balance,
            "Secondary market burned balance should be equal to the balance we secondary market burned for chain and domain"
        );
        assertEq(_token.balanceOf(_recipient), _balance, "Recipient should receive the re-minted balance");
        assertEq(
            _token.minterAllowance(address(_secondaryMarketBurnable)), 0, "Minter allowance should be 0 after mint"
        );
    }

    function test_secondaryMarketBurnAndRemint_evm() public {
        // All EVM chains use 20-byte addresses. Domain 0 = Ethereum (representative).
        // Raw: abi.encodePacked of the EVM address.
        bytes memory evmAddress = abi.encodePacked(address(0x55FE002aefF02F77364de339a1292923A15844B8));
        _assertSMBSucceeds(evmAddress, 0);
    }

    function test_secondaryMarketBurnAndRemint_noble() public {
        // Noble (Cosmos IBC): bech32-decoded 20-byte hash. Domain 4.
        // Source: noble1ukv0qhw3zszzyjty32cck2j229ekpmr6g806yp
        bytes memory nobleAddress = hex"e598f05dd114042249648ab18b2a4a517360ec7a";
        _assertSMBSucceeds(nobleAddress, 4);
    }

    function test_secondaryMarketBurnAndRemint_solana() public {
        // Solana: base58-decoded 32-byte ed25519 public key. Domain 5.
        // Source: FSyXLen1kkAjbfYBTCBZCfs36xAspxrLBoTuNKA6na8R
        bytes memory solanaAddress = hex"d6ab0c4cf98bd0f5f9e9d70212e484f5384e8467e5cd8abcb4435e02cae7cd4a";
        _assertSMBSucceeds(solanaAddress, 5);
    }

    function test_secondaryMarketBurnAndRemint_sui() public {
        // Sui: hex-decoded 32-byte address. Domain 8.
        // Source: 0x20db03980e117fe62bacd78a0b0b96c5ed588754e25d3c21a52b294b5d57ea7b
        bytes memory suiAddress = hex"20db03980e117fe62bacd78a0b0b96c5ed588754e25d3c21a52b294b5d57ea7b";
        _assertSMBSucceeds(suiAddress, 8);
    }

    function test_secondaryMarketBurnAndRemint_aptos() public {
        // Aptos: hex-decoded 32-byte address. Domain 9.
        // Source: 0xe16a858661bf74702611c836df8d7fcbf61d9a7a1382a82f586e412478f043d8
        bytes memory aptosAddress = hex"e16a858661bf74702611c836df8d7fcbf61d9a7a1382a82f586e412478f043d8";
        _assertSMBSucceeds(aptosAddress, 9);
    }

    function test_secondaryMarketBurnAndRemint_starknet() public {
        // Starknet: hex-decoded 32-byte Stark curve address. Domain 25.
        // Source: 0x057da7c2e6668745525c4b9582f426eddcf4afcfa97427ef96ecb07d67e5735e
        bytes memory starknetAddress = hex"057da7c2e6668745525c4b9582f426eddcf4afcfa97427ef96ecb07d67e5735e";
        _assertSMBSucceeds(starknetAddress, 25);
    }

    function test_secondaryMarketBurnAndRemint_stellar() public {
        // Stellar: strkey-decoded 33 bytes — version byte (0x30) + 32-byte public key. Domain 27.
        // Source: GDZZZV63F63EL63XSKXE6V535JYUW2WFO6VKLYH73LCOUJCUCDRFPNIW
        bytes memory stellarAddress = hex"30f39cd7db2fb645fb7792ae4f57bbea714b6ac577aaa5e0ffdac4ea245410e257";
        _assertSMBSucceeds(stellarAddress, 27);
    }

    function test_secondaryMarketBurnAndRemint_algorand() public {
        // Algorand: base32-decoded 32-byte public key, checksum stripped. Domain 38.
        // Source: TGYXKLVNWWWOY66DF7EB4WMGG76SRBJVKK6P5PLX7MQO2YAYTPIPN35OL4
        bytes memory algoAddress = hex"99b1752eadb5acec7bc32fc81e598637fd28853552bcfebd77fb20ed60189bd0";
        _assertSMBSucceeds(algoAddress, 38);
    }

    function test_secondaryMarketBurnAndRemint_hedera() public {
        // Hedera: entity ID stored as UTF-8 bytes — no canonical binary form. Domain 40.
        bytes memory hederaAddress = bytes("0.0.2201630");
        _assertSMBSucceeds(hederaAddress, 40);
    }

    function test_secondaryMarketBurnAndRemint_statemint() public {
        // Statemint: SS58-decoded 33 bytes — network prefix (0x00) + 32-byte key, checksum stripped. Domain 41.
        // Source: 1YbGh3EZxGKUL6b8upjhV1kxXaEd5Q7EqUUXF4TsmJm513z
        bytes memory statemintAddress = hex"001817f8ef1bd20183ac50551a983c3ccac5d8ef4dc01b668e557c48c7296fb336";
        _assertSMBSucceeds(statemintAddress, 41);
    }

    function test_secondaryMarketBurnAndRemint_near_implicit() public {
        // NEAR: hex-decoded 32-byte ed25519 implicit account. Domain 42.
        // Source (64-char hex): 4a432082cc1cd551b14d6f075e9345087d64f57c2660400ef33cac5a0bb263b0
        bytes memory nearAddress = hex"4a432082cc1cd551b14d6f075e9345087d64f57c2660400ef33cac5a0bb263b0";
        _assertSMBSucceeds(nearAddress, 42);
    }

    function test_secondaryMarketBurnAndRemint_xrp() public {
        // XRP Ledger: base58check-decoded 21 bytes — version byte + 20-byte AccountID, checksum stripped. Domain 43.
        // Source: rnXyVQzgxZe7TR1EPzTkGj2jxH4LMJYh66
        bytes memory xrpAddress = hex"0031bc232b08a21a5ec14f0087363eb2204b30f857";
        _assertSMBSucceeds(xrpAddress, 43);
    }

    function test_secondaryMarketBurnAndRemint_tron() public {
        // TRON: base58check-decoded 21 bytes — 0x41 network prefix + 20-byte address, checksum stripped. Domain 44.
        // Source: TFF5WpZmCSbNRnbabp4gybRKK7ryHhhqNx
        bytes memory tronAddress = hex"4139d908dac893cbcb53cc86e0ecc369aa4def1a29";
        _assertSMBSucceeds(tronAddress, 44);
    }

    function test_secondaryMarketBurnAndRemint_evm_checksumAndLowercaseResolveToSameRecord() public {
        // Checksummed and lowercase hex are the same 20 bytes at runtime.
        // Burning with one form and querying or re-burning with the other hits the same record.
        bytes memory checksummed = abi.encodePacked(address(0x55FE002aefF02F77364de339a1292923A15844B8));
        bytes memory lowercase = hex"55fe002aeff02f77364de339a1292923a15844b8";
        assertEq(checksummed, lowercase, "checksummed and lowercase should be identical bytes");

        _setup();
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(checksummed, _domain, _balance, _recipient);

        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(lowercase, _domain),
            "Lowercase query should resolve to the same record"
        );
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurnedBalance(lowercase, _domain),
            _balance,
            "Lowercase balance query should return the burned balance"
        );

        _prefundAllowance(_balance);
        vm.expectRevert(
            abi.encodeWithSelector(SecondaryMarketBurnable.AlreadySecondaryMarketBurned.selector, lowercase, _domain)
        );
        vm.prank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(lowercase, _domain, _balance, _recipient);

        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(checksummed, _domain),
            "Checksummed query should resolve to the same record"
        );
        assertEq(
            _secondaryMarketBurnable.secondaryMarketBurnedBalance(checksummed, _domain),
            _balance,
            "Checksummed balance query should return the burned balance"
        );
        assertFalse(
            _secondaryMarketBurnable.isSecondaryMarketBurned(_other, _domain), "Different address should return false"
        );

        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(),
            _balance,
            "Total secondary market burned amount should be equal to the balance we secondary market burned for domain"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(_domain),
            _balance,
            "Total secondary market burned amount for domain should be equal to the balance we secondary market burned for domain"
        );
    }

    function test_secondaryMarketBurnAndRemint_chainAddressesDoNotCollide() public {
        vm.prank(_owner);
        _secondaryMarketBurnable.updateSecondaryMarketBurner(_secondaryMarketBurner);
        _allowlist(_recipient);
        _prefundAllowance(_balance + _otherBalance);

        bytes memory sharedBytes = abi.encodePacked(address(0x1234567890123456789012345678901234567890));
        uint32 ethDomain = 0;
        uint32 baseDomain = 6;

        vm.startPrank(_secondaryMarketBurner);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(sharedBytes, ethDomain, _balance, _recipient);
        _secondaryMarketBurnable.secondaryMarketBurnAndRemint(sharedBytes, baseDomain, _otherBalance, _recipient);
        vm.stopPrank();

        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(sharedBytes, ethDomain),
            "Address should be secondary market burned for Ethereum domain"
        );
        assertTrue(
            _secondaryMarketBurnable.isSecondaryMarketBurned(sharedBytes, baseDomain),
            "Address should be secondary market burned for Base domain"
        );
        assertEq(
            _secondaryMarketBurnable.totalSecondaryMarketBurnedAmount(),
            _balance + _otherBalance,
            "Total secondary market burned amount should be equal to the balance we secondary market burned for Ethereum domain plus the balance we secondary market burned for Base domain"
        );
    }
}

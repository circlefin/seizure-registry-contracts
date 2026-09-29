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

import {UnauthorizedCaller, ZeroAddress} from "../common/Errors.sol";
import {Allowlistable} from "./Allowlistable.sol";
import {Immutables} from "./Immutables.sol";

/// @title SecondaryMarketBurnable
/// @notice Manages the SecondaryMarketBurner role. Atomically re-mints a frozen balance from a
///         blocklisted cross-chain address to an allowlisted law enforcement recipient and records
///         an on-chain audit trail. Composes `Allowlistable` to gate remint recipients.
///         The `TOKEN` reference lives in `Immutables`; the minter allowance is managed externally
///         by a separate minter-controller role before each `secondaryMarketBurnAndRemint` call.
abstract contract SecondaryMarketBurnable is Allowlistable, Immutables {
    // ============ Events ============

    /// @notice Emitted when the SecondaryMarketBurner address is updated
    /// @param oldSecondaryMarketBurner The previous SecondaryMarketBurner address
    /// @param newSecondaryMarketBurner The new SecondaryMarketBurner address
    event SecondaryMarketBurnerChanged(
        address indexed oldSecondaryMarketBurner, address indexed newSecondaryMarketBurner
    );

    /// @notice Emitted when a balance is SecondaryMarketBurned and re-minted to a recipient
    /// @param secondaryMarketBurnedAddress The SecondaryMarketBurned address whose balance was burned
    /// @param domain The domain on which the burned address resides
    /// @param balance The blocklisted balance that was burned and re-minted
    /// @param remintRecipient The recipient address that received the re-minted balance
    event SecondaryMarketBurnRecorded(
        bytes secondaryMarketBurnedAddress, uint32 indexed domain, uint256 balance, address indexed remintRecipient
    );

    // ============ Errors ============

    /// @notice Thrown when the given address has already been SecondaryMarketBurned on the given domain
    error AlreadySecondaryMarketBurned(bytes secondaryMarketBurnedAddress, uint32 domain);

    /// @notice Thrown when the SecondaryMarketBurned address bytes are empty
    error EmptyAddress();

    /// @notice Thrown when the mint call fails
    error MintFailed();

    /// @notice Thrown when the blocklisted balance to burn is zero
    error ZeroBalance();

    // ============ Modifiers ============

    /// @notice Restricts the caller to the SecondaryMarketBurner role
    modifier onlySecondaryMarketBurner() {
        if (msg.sender != SecondaryMarketBurnableStorage.get().secondaryMarketBurner) {
            revert UnauthorizedCaller();
        }
        _;
    }

    // ============ Initialization ============

    /// @notice Initializes the SecondaryMarketBurner role
    /// @param secondaryMarketBurner_ The initial SecondaryMarketBurner address
    // solhint-disable-next-line func-name-mixedcase
    function __SecondaryMarketBurnable_init(address secondaryMarketBurner_) internal onlyInitializing {
        _setSecondaryMarketBurner(secondaryMarketBurner_);
    }

    // ============ View Functions ============

    /// @notice The address holding the SecondaryMarketBurner role
    /// @return The SecondaryMarketBurner address
    function secondaryMarketBurner() public view returns (address) {
        return SecondaryMarketBurnableStorage.get().secondaryMarketBurner;
    }

    /// @notice Whether the given address has been SecondaryMarketBurned on the given domain
    /// @param secondaryMarketBurnedAddress The SecondaryMarketBurned address to check
    /// @param domain The domain to check
    /// @return True if the address has been SecondaryMarketBurned on the domain
    function isSecondaryMarketBurned(bytes calldata secondaryMarketBurnedAddress, uint32 domain)
        public
        view
        returns (bool)
    {
        return SecondaryMarketBurnableStorage.get().records[domain][secondaryMarketBurnedAddress].balance != 0;
    }

    /// @notice Whether the given EVM address has been SecondaryMarketBurned on the given domain
    /// @param secondaryMarketBurnedAddress The EVM address to check
    /// @param domain The domain to check
    /// @return True if the address has been SecondaryMarketBurned on the domain
    function isSecondaryMarketBurned(address secondaryMarketBurnedAddress, uint32 domain) public view returns (bool) {
        bytes memory addr = abi.encodePacked(secondaryMarketBurnedAddress);
        return SecondaryMarketBurnableStorage.get().records[domain][addr].balance != 0;
    }

    /// @notice The blocklisted balance recorded for a SecondaryMarketBurned address on a domain
    /// @param secondaryMarketBurnedAddress The SecondaryMarketBurned address to check
    /// @param domain The domain to check
    /// @return The blocklisted balance, or zero if not SecondaryMarketBurned
    function secondaryMarketBurnedBalance(bytes calldata secondaryMarketBurnedAddress, uint32 domain)
        public
        view
        returns (uint256)
    {
        return SecondaryMarketBurnableStorage.get().records[domain][secondaryMarketBurnedAddress].balance;
    }

    /// @notice The blocklisted balance recorded for a SecondaryMarketBurned EVM address on a domain
    /// @param secondaryMarketBurnedAddress The EVM address to check
    /// @param domain The domain to check
    /// @return The blocklisted balance, or zero if not SecondaryMarketBurned
    function secondaryMarketBurnedBalance(address secondaryMarketBurnedAddress, uint32 domain)
        public
        view
        returns (uint256)
    {
        bytes memory addr = abi.encodePacked(secondaryMarketBurnedAddress);
        return SecondaryMarketBurnableStorage.get().records[domain][addr].balance;
    }

    /// @notice The total SecondaryMarketBurned amount across all domains
    /// @return The total SecondaryMarketBurned amount
    function totalSecondaryMarketBurnedAmount() public view returns (uint256) {
        return SecondaryMarketBurnableStorage.get().totalSecondaryMarketBurnedAmount;
    }

    /// @notice The total SecondaryMarketBurned amount on a given domain
    /// @param domain The domain to query
    /// @return The SecondaryMarketBurned amount on the domain
    function totalSecondaryMarketBurnedAmount(uint32 domain) public view returns (uint256) {
        return SecondaryMarketBurnableStorage.get().secondaryMarketBurnedAmountByDomain[domain];
    }

    // ============ External Functions ============

    /// @notice Updates the SecondaryMarketBurner address
    /// @param newSecondaryMarketBurner The new SecondaryMarketBurner address
    function updateSecondaryMarketBurner(address newSecondaryMarketBurner) external onlyOwner {
        _setSecondaryMarketBurner(newSecondaryMarketBurner);
    }

    /// @notice Records a secondaryMarketBurn on a cross-chain address and re-mints the equivalent
    ///         balance to an allowlisted recipient.
    ///         The minter allowance for this call must have been incremented by the minter-controller
    ///         role before this function is called
    /// @dev Checks-effects-interactions: all storage writes happen before the external mint call so
    ///      a revert in `TOKEN.mint` rolls back the entire transaction with no partial state.
    ///      CEI also ensures a reentrant callback sees `isSecondaryMarketBurned == true` and reverts.
    /// @param secondaryMarketBurnedAddress The address whose balance is being burned
    /// @param domain The domain on which the burned address resides
    /// @param balance The blocklisted balance to burn and re-mint; caller is responsible for off-chain verification
    /// @param remintRecipient The allowlisted recipient to re-mint the balance to
    function secondaryMarketBurnAndRemint(
        bytes calldata secondaryMarketBurnedAddress,
        uint32 domain,
        uint256 balance,
        address remintRecipient
    ) external onlySecondaryMarketBurner {
        if (secondaryMarketBurnedAddress.length == 0) revert EmptyAddress();
        if (balance == 0) revert ZeroBalance();
        _ensureAddressRecipientAllowed(remintRecipient);
        _ensureNotAlreadySecondaryMarketBurned(secondaryMarketBurnedAddress, domain);

        SecondaryMarketBurnableStorage.Data storage $ = SecondaryMarketBurnableStorage.get();
        $.records[domain][secondaryMarketBurnedAddress] =
            SecondaryMarketBurnableStorage.RemintRecord({balance: balance, remintRecipient: remintRecipient});
        $.secondaryMarketBurnedAmountByDomain[domain] += balance;
        $.totalSecondaryMarketBurnedAmount += balance;

        if (!TOKEN.mint(remintRecipient, balance)) {
            revert MintFailed();
        }

        emit SecondaryMarketBurnRecorded(secondaryMarketBurnedAddress, domain, balance, remintRecipient);
    }

    // ============ Internal Functions ============

    /// @notice Reverts if the given address has already been SecondaryMarketBurned on the given domain
    /// @param secondaryMarketBurnedAddress The cross-chain address to check
    /// @param domain The domain to check
    function _ensureNotAlreadySecondaryMarketBurned(bytes calldata secondaryMarketBurnedAddress, uint32 domain)
        internal
        view
    {
        if (isSecondaryMarketBurned(secondaryMarketBurnedAddress, domain)) {
            revert AlreadySecondaryMarketBurned(secondaryMarketBurnedAddress, domain);
        }
    }

    /// @notice Sets the SecondaryMarketBurner address
    /// @param newSecondaryMarketBurner The new SecondaryMarketBurner address
    function _setSecondaryMarketBurner(address newSecondaryMarketBurner) private {
        if (newSecondaryMarketBurner == address(0)) revert ZeroAddress();
        address oldSecondaryMarketBurner = SecondaryMarketBurnableStorage.get().secondaryMarketBurner;
        SecondaryMarketBurnableStorage.get().secondaryMarketBurner = newSecondaryMarketBurner;
        emit SecondaryMarketBurnerChanged(oldSecondaryMarketBurner, newSecondaryMarketBurner);
    }
}

/// @title SecondaryMarketBurnableStorage
/// @notice Implements the EIP-7201 storage pattern for the `SecondaryMarketBurnable` module
library SecondaryMarketBurnableStorage {
    /// @notice On-chain record of a burned balance and the recipient it was re-minted to.
    struct RemintRecord {
        /// The blocklisted balance that was burned and re-minted
        uint256 balance;
        /// The recipient address that received the re-minted balance
        address remintRecipient;
    }

    /// @custom:storage-location erc7201:circle.SeizureRegistry.SecondaryMarketBurnable
    struct Data {
        /// The address holding the secondary market burner role
        address secondaryMarketBurner;
        /// Mapping of domain to SecondaryMarketBurned address to RemintRecord
        mapping(uint32 domain => mapping(bytes secondaryMarketBurnedAddress => RemintRecord record)) records;
        /// Mapping of domain to the total SecondaryMarketBurned amount on that domain
        mapping(uint32 domain => uint256 amount) secondaryMarketBurnedAmountByDomain;
        /// The total SecondaryMarketBurned amount across all domains
        uint256 totalSecondaryMarketBurnedAmount;
    }

    /// @notice Slot: `keccak256(abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.SecondaryMarketBurnable"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0xa06ac12c812906c1eb2966abad675ddf61be53bc61bf6bff81cf65f2df610500;

    /// @notice Returns the namespaced storage struct for the `SecondaryMarketBurnable` module
    /// @return $ Storage struct pointer for SecondaryMarketBurnable
    // solhint-disable-next-line use-natspec
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}

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
import {SecondaryMarketBurnable} from "./SecondaryMarketBurnable.sol";

/// @title HashUpdatable
/// @notice Manages the HashUpdater role and the remint transaction hash for each SecondaryMarketBurned
///         record. Inherits `SecondaryMarketBurnable` one-way so that `setRemintTxHash` can gate on
///         an existing burn record via `isSecondaryMarketBurned` without creating a circular import.
abstract contract HashUpdatable is SecondaryMarketBurnable {
    // ============ Events ============

    /// @notice Emitted when the HashUpdater address is updated
    /// @param oldHashUpdater The previous HashUpdater address
    /// @param newHashUpdater The new HashUpdater address
    event HashUpdaterChanged(address indexed oldHashUpdater, address indexed newHashUpdater);

    /// @notice Emitted when a remint transaction hash is set for a SecondaryMarketBurned record
    /// @param secondaryMarketBurnedAddress The SecondaryMarketBurned address
    /// @param domain The domain on which the burned address resides
    /// @param txHash The remint transaction hash
    event RemintTxHashUpdated(bytes secondaryMarketBurnedAddress, uint32 indexed domain, bytes32 txHash);

    // ============ Errors ============

    /// @notice Thrown when the provided transaction hash is zero
    error ZeroHash();

    /// @notice Thrown when setRemintTxHash is called for an address with no SecondaryMarketBurn record
    error RecordNotFound();

    // ============ Modifiers ============

    /// @notice Restricts the caller to the HashUpdater role
    modifier onlyHashUpdater() {
        if (msg.sender != HashUpdatableStorage.get().hashUpdater) {
            revert UnauthorizedCaller();
        }
        _;
    }

    // ============ Initialization ============

    /// @notice Initializes the HashUpdater role
    /// @param hashUpdater_ The initial HashUpdater address
    // solhint-disable-next-line func-name-mixedcase
    function __HashUpdatable_init(address hashUpdater_) internal onlyInitializing {
        _setHashUpdater(hashUpdater_);
    }

    // ============ View Functions ============

    /// @notice The address holding the HashUpdater role
    /// @return The HashUpdater address
    function hashUpdater() public view returns (address) {
        return HashUpdatableStorage.get().hashUpdater;
    }

    // ============ External Functions ============

    /// @notice Updates the HashUpdater address
    /// @param newHashUpdater The new HashUpdater address
    function updateHashUpdater(address newHashUpdater) external onlyOwner {
        _setHashUpdater(newHashUpdater);
    }

    /// @notice Sets the remint transaction hash for a SecondaryMarketBurned record.
    ///         May overwrite a previously set hash.
    /// @param secondaryMarketBurnedAddress The SecondaryMarketBurned address
    /// @param domain The domain on which the burned address resides
    /// @param txHash The remint transaction hash to record
    function setRemintTxHash(bytes calldata secondaryMarketBurnedAddress, uint32 domain, bytes32 txHash)
        external
        onlyHashUpdater
    {
        if (txHash == bytes32(0)) revert ZeroHash();
        if (!isSecondaryMarketBurned(secondaryMarketBurnedAddress, domain)) revert RecordNotFound();
        HashUpdatableStorage.get().remintTxHashes[domain][secondaryMarketBurnedAddress] = txHash;
        emit RemintTxHashUpdated(secondaryMarketBurnedAddress, domain, txHash);
    }

    // ============ Internal Functions ============

    /// @notice Sets the HashUpdater address
    /// @param newHashUpdater The new HashUpdater address
    function _setHashUpdater(address newHashUpdater) private {
        if (newHashUpdater == address(0)) revert ZeroAddress();
        address oldHashUpdater = HashUpdatableStorage.get().hashUpdater;
        HashUpdatableStorage.get().hashUpdater = newHashUpdater;
        emit HashUpdaterChanged(oldHashUpdater, newHashUpdater);
    }
}

/// @title HashUpdatableStorage
/// @notice Implements the EIP-7201 storage pattern for the `HashUpdatable` module
library HashUpdatableStorage {
    /// @custom:storage-location erc7201:circle.SeizureRegistry.HashUpdatable
    struct Data {
        /// The address holding the hash updater role
        address hashUpdater;
        /// Mapping of domain to SecondaryMarketBurned address to remint transaction hash
        mapping(uint32 domain => mapping(bytes secondaryMarketBurnedAddress => bytes32 txHash)) remintTxHashes;
    }

    /// @notice Slot: `keccak256(abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.HashUpdatable"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0xfac8b489356174da7f6f353bca13309a67767a6b7b6322b966f09a818a486f00;

    /// @notice Returns the namespaced storage struct for the `HashUpdatable` module
    /// @return $ Storage struct pointer for HashUpdatable
    // solhint-disable-next-line use-natspec
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}

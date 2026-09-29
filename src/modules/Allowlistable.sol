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
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UnauthorizedCaller, ZeroAddress} from "../common/Errors.sol";

/// @title Allowlistable
/// @notice Manages the AddressManager role and the allowed recipients list for the Seizure Registry.
///         Provides an owner-gated setter for the role, and AddressManager-gated add/remove for recipients.
abstract contract Allowlistable is Initializable, Ownable2StepUpgradeable {
    // ============ Events ============

    /// @notice Emitted when the address manager address is updated
    /// @param oldAddressManager The previous address manager address
    /// @param newAddressManager The new address manager address
    event AddressManagerChanged(address indexed oldAddressManager, address indexed newAddressManager);

    /// @notice Emitted when an address is added as an allowed recipient
    /// @param recipient The address added as an allowed recipient
    event AllowedRecipientAdded(address indexed recipient);

    /// @notice Emitted when an address is removed as an allowed recipient
    /// @param recipient The address removed as an allowed recipient
    event AllowedRecipientRemoved(address indexed recipient);

    // ============ Errors ============

    /// @notice Thrown when a recipient is not an allowed recipient
    error RecipientNotAllowed(address recipient);

    // ============ Modifiers ============

    /// @notice Restricts the caller to the address manager role
    modifier onlyAddressManager() {
        if (msg.sender != AllowlistableStorage.get().addressManager) {
            revert UnauthorizedCaller();
        }
        _;
    }

    // ============ Initialization ============

    /// @notice Initializes the address manager role
    /// @param addressManager_ The initial address manager address
    // solhint-disable-next-line func-name-mixedcase
    function __Allowlistable_init(address addressManager_) internal onlyInitializing {
        _setAddressManager(addressManager_);
    }

    // ============ View Functions ============

    /// @notice The address holding the address manager role
    /// @return The address manager address
    function addressManager() public view returns (address) {
        return AllowlistableStorage.get().addressManager;
    }

    /// @notice Whether the given address is an allowed recipient
    /// @param recipient The address to check
    /// @return True if the address is an allowed recipient
    function isAllowedRecipient(address recipient) public view returns (bool) {
        return AllowlistableStorage.get().allowedRecipients[recipient];
    }

    // ============ External Functions ============

    /// @notice Updates the address manager address
    /// @param newAddressManager The new address manager address
    function updateAddressManager(address newAddressManager) external onlyOwner {
        _setAddressManager(newAddressManager);
    }

    /// @notice Adds an address as an allowed recipient
    /// @dev This function should be idempotent
    /// @param recipient The address to add
    function addAllowedRecipient(address recipient) external onlyAddressManager {
        if (recipient == address(0)) revert ZeroAddress();
        _setAllowedRecipientState(recipient, true);
        emit AllowedRecipientAdded(recipient);
    }

    /// @notice Removes an address as an allowed recipient
    /// @dev This function should be idempotent. Unlike `addAllowedRecipient`, no zero-address check
    ///      is performed; passing the zero address has no meaningful effect (zero address is never a valid recipient).
    /// @param recipient The address to remove
    function removeAllowedRecipient(address recipient) external onlyAddressManager {
        _setAllowedRecipientState(recipient, false);
        emit AllowedRecipientRemoved(recipient);
    }

    // ============ Internal Functions ============

    /// @notice Reverts if the given address is not an allowed recipient
    /// @param recipient The recipient address to check
    function _ensureAddressRecipientAllowed(address recipient) internal view {
        if (!isAllowedRecipient(recipient)) {
            revert RecipientNotAllowed(recipient);
        }
    }

    /// @notice Sets the allowed recipient status of an address
    /// @param recipient The recipient address to update
    /// @param allowed Whether the recipient should be allowed
    function _setAllowedRecipientState(address recipient, bool allowed) internal {
        AllowlistableStorage.get().allowedRecipients[recipient] = allowed;
    }

    /// @notice Sets the address manager address
    /// @param newAddressManager The new address manager address
    function _setAddressManager(address newAddressManager) private {
        if (newAddressManager == address(0)) revert ZeroAddress();
        address oldAddressManager = AllowlistableStorage.get().addressManager;
        AllowlistableStorage.get().addressManager = newAddressManager;
        emit AddressManagerChanged(oldAddressManager, newAddressManager);
    }
}

/// @title AllowlistableStorage
/// @notice Implements the EIP-7201 storage pattern for the `Allowlistable` module
library AllowlistableStorage {
    /// @custom:storage-location erc7201:circle.SeizureRegistry.Allowlistable
    struct Data {
        /// The address holding the address manager role
        address addressManager;
        /// Mapping of allowed LE recipient addresses
        mapping(address recipient => bool allowed) allowedRecipients;
    }

    /// @notice Slot: `keccak256(abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.Allowlistable"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x5035815ec910b0c48aee928d834a28fd3c057f74605423d5fc7d0d013e5fb200;

    /// @notice Returns the namespaced storage struct for the `Allowlistable` module
    /// @return $ Storage struct pointer for Allowlistable
    // solhint-disable-next-line use-natspec
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}

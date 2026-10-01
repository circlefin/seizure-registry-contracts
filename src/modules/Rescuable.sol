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

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UnauthorizedCaller} from "../common/Errors.sol";

/// @title Rescuable
/// @notice Defines a `rescuer` role that may rescue ERC-20 tokens locked in the contract.
/// @dev Standard rescue-locked-tokens pattern.
abstract contract Rescuable is Initializable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    // ============ Events ============

    /// @notice Emitted when the rescuer address is updated.
    /// @param oldRescuer The old rescuer address.
    /// @param newRescuer The new rescuer address.
    event RescuerChanged(address indexed oldRescuer, address indexed newRescuer);

    /// @notice Emitted when ERC-20 tokens are rescued.
    /// @param token The ERC-20 token address.
    /// @param to The recipient address.
    /// @param amount The amount rescued.
    event RescueERC20(address indexed token, address indexed to, uint256 amount); // solhint-disable-line gas-indexed-events

    // ============ Errors ============

    /// @notice Thrown when rescue recipient is invalid (zero address or self).
    /// @param recipient The invalid recipient address.
    error InvalidRescueRecipient(address recipient);

    // ============ Modifiers ============

    /// @notice Restricts the caller to the `rescuer` role.
    modifier onlyRescuer() {
        _checkRescuer();
        _;
    }

    // ============ Initialization ============

    /// @notice Initializes the `rescuer` role.
    /// @param rescuer_ The initial rescuer address.
    // solhint-disable-next-line func-name-mixedcase
    function __Rescuable_init(address rescuer_) internal onlyInitializing {
        _setRescuer(rescuer_);
    }

    // ============ View Functions ============

    /// @notice Returns the address with the `rescuer` role.
    /// @return The address of the rescuer.
    function rescuer() public view returns (address) {
        return RescuableStorage.get().rescuer;
    }

    // ============ External Functions ============

    /// @notice Rescue ERC-20 tokens locked in this contract.
    /// @param token The ERC-20 token contract address.
    /// @param to The recipient address.
    /// @param amount The amount to withdraw.
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyRescuer {
        if (to == address(0) || to == address(this)) revert InvalidRescueRecipient(to);
        token.safeTransfer(to, amount);
        emit RescueERC20(address(token), to, amount);
    }

    /// @notice Sets the address that may call `rescueERC20`.
    /// @dev May only be called by the `owner` role.
    /// @param newRescuer The new rescuer address.
    function updateRescuer(address newRescuer) external onlyOwner {
        _setRescuer(newRescuer);
    }

    // ============ Private Functions ============

    /// @notice Reverts if `msg.sender` is not the rescuer.
    function _checkRescuer() private view {
        if (rescuer() != msg.sender) {
            revert UnauthorizedCaller();
        }
    }

    /// @notice Sets the rescuer in storage and emits an event.
    /// @param newRescuer The new rescuer address.
    function _setRescuer(address newRescuer) private {
        address oldRescuer = RescuableStorage.get().rescuer;
        RescuableStorage.get().rescuer = newRescuer;
        emit RescuerChanged(oldRescuer, newRescuer);
    }
}

/// @title RescuableStorage
/// @notice Implements the EIP-7201 storage pattern for the `Rescuable` module.
library RescuableStorage {
    /// @custom:storage-location erc7201:circle.SeizureRegistry.Rescuable
    struct Data {
        /// @dev The address that is allowed to rescue ERC-20 tokens.
        address rescuer;
    }

    /// @notice Slot: `keccak256(abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.Rescuable"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0xc97e0ba968f41b230c0680e590f199be4e9b9e04447a4c90b7f6216279377e00;

    /// @notice Returns the namespaced storage struct for the `Rescuable` module.
    /// @return $ Storage struct pointer for Rescuable
    // solhint-disable-next-line use-natspec
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}

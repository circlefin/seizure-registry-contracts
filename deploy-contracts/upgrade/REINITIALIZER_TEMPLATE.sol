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

// Template for SeizureRegistry upgrades that add new storage state via reinitializer(N).
// See deploy-contracts/upgrade/README.md for the storage safety checklist before proceeding.
// TODO: copy this file, fill in all TODOs, remove `abstract` from the contract.

import {SeizureRegistry} from "src/SeizureRegistry.sol";

// TODO: Rename to match your version, e.g., V3SeizureRegistryStorage.
//       Replace every "VN" occurrence with your version label throughout.

/// @notice EIP-7201 namespaced storage for SeizureRegistry VN additions.
library VNSeizureRegistryStorage {
    /// @custom:storage-location erc7201:circle.SeizureRegistry.VN
    struct Data {
        // TODO: Add new fields here — APPEND ONLY within this new namespace.
        // Example: address newRole;
        uint256 _placeholder; // remove once real fields are added
    }

    /// @notice Slot: `keccak256(abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.VN"))) - 1)) & ~bytes32(uint256(0xff))`
    /// @dev    TODO: Replace with the computed value (see README slot computation steps).
    bytes32 public constant SLOT = 0x0000000000000000000000000000000000000000000000000000000000000000; // TODO: fill in

    // solhint-disable-next-line use-natspec
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}

/// @notice Template for SeizureRegistry upgrades that add new storage state.
/// @dev    ABSTRACT — not deployable. TODO: Rename to SeizureRegistryV3 (or your version label).
abstract contract SeizureRegistryVN is SeizureRegistry {
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param tokenContract_ Pass the existing token address to preserve TOKEN, or a new address to update it.
    constructor(address tokenContract_) SeizureRegistry(tokenContract_) {}

    /// @notice Initializes VN state. Runs exactly once via upgradeToAndCall; blocked on re-call.
    /// @dev    TODO: Replace 3 with the correct reinitializer version (see README version history).
    ///         TODO: Add parameters for every new field that needs initialization.
    // solhint-disable-next-line func-name-mixedcase
    function initializeVN()
        external
        reinitializer(
            3 /* TODO: replace with correct N */
        )
    {
        // TODO: Read VNSeizureRegistryStorage.get() and initialize new fields.
    }

    // TODO: Add view functions and new logic for your added fields.
}

// TODO: Write a companion upgrade script — copy 001_UpgradeSeizureRegistry.s.sol, that makes sense
//       depending on the functionality of the upgraded version, the new fields that need
//       to be initialized, and state changes. See README for the full pattern.

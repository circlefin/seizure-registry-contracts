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

import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {ZeroAddress} from "src/common/Errors.sol";

/// @title SeizureRegistryV2Stub
/// @notice Minimal V2 implementation used in upgrade integration tests.
///         Extends SeizureRegistry with a new storage field (`newRole`) in its own EIP-7201 namespace
///         and a `reinitializer(3)` initializer to set it. Represents an upgrade that adds both
///         new state and new functionality without touching any existing storage slots.
/// @dev    Not for production use. Constructor accepts a `tokenContract_` so tests can supply either
///         the same token (to keep TOKEN unchanged) or a different one (to verify the immutable update).
contract SeizureRegistryV2Stub is SeizureRegistry {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address tokenContract_) SeizureRegistry(tokenContract_) {}

    /// @notice Initializes V2 state. Runs exactly once via upgradeToAndCall; blocked on re-call.
    /// @param newRole_ The address to assign to the new `newRole` storage field.
    function initializeV2(address newRole_) external reinitializer(3) {
        if (newRole_ == address(0)) revert ZeroAddress();
        V2StubStorage.get().newRole = newRole_;
    }

    /// @notice Returns the V2 `newRole` address.
    function newRole() public view returns (address) {
        return V2StubStorage.get().newRole;
    }
}

/// @title V2StubStorage
/// @notice EIP-7201 namespaced storage for SeizureRegistryV2Stub.
library V2StubStorage {
    /// @custom:storage-location erc7201:circle.SeizureRegistry.V2Stub
    struct Data {
        address newRole;
    }

    /// @notice Slot: `keccak256(abi.encode(uint256(keccak256(bytes("circle.SeizureRegistry.V2Stub"))) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 public constant SLOT = 0x6058c37af2b2c1b86d5bf499033c114abb419ef22a674f8ce98ea84b3ef05e00;

    /// @notice Returns the namespaced storage struct for V2StubStorage.
    /// @return $ Storage struct pointer
    // solhint-disable-next-line use-natspec
    function get() internal pure returns (Data storage $) {
        assembly ("memory-safe") {
            $.slot := SLOT
        }
    }
}

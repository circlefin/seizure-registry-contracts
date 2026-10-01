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

import {Script} from "forge-std/Script.sol";

/// @title BaseDeployScript
/// @notice Shared helpers for SeizureRegistry deploy scripts.
abstract contract BaseDeployScript is Script {
    /// @notice Reads an address from the environment and reverts if it is zero.
    /// @param envKey The environment variable name to read.
    /// @return addr The non-zero address value.
    function _readAddress(string memory envKey) internal view virtual returns (address addr) {
        addr = vm.envAddress(envKey);
        require(addr != address(0), string.concat(envKey, " is zero"));
    }
}

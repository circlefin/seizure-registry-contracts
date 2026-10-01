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

import {console} from "forge-std/console.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {BaseDeployScript} from "./shared/BaseDeployScript.sol";
import {Constants} from "./shared/Constants.sol";

/// @title AcceptOwnership
/// @notice Completes the 2-step ownership transfer on SeizureRegistry by having the
///         designated owner call `acceptOwnership()`.
///
/// Run this after `DeploySeizureRegistry` (which calls `transferOwnership`) once the
/// designated owner is ready to accept.
///
/// Required env vars:
///   SR_PROXY_ADDRESS   — deployed SeizureRegistry proxy (same as used in bytecode validation)
///   SR_OWNER_ADDRESS   — designated owner accepting ownership; must equal the current pendingOwner
contract AcceptOwnership is BaseDeployScript {
    function run() external returns (address proxyAddress) {
        proxyAddress = _readAddress(Constants.SR_PROXY_ADDRESS);
        address designatedOwner = _readAddress(Constants.SR_OWNER_ADDRESS);

        SeizureRegistry registry = SeizureRegistry(proxyAddress);

        console.log("Owner before:  ", registry.owner());
        console.log("Pending owner: ", registry.pendingOwner());

        require(designatedOwner == registry.pendingOwner(), "SR_OWNER_ADDRESS does not match pendingOwner on proxy");

        vm.startBroadcast(designatedOwner);
        registry.acceptOwnership();
        vm.stopBroadcast();

        console.log("Owner after:   ", registry.owner());
    }
}

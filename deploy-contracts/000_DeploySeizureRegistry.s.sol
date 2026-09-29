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
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";
import {BaseDeployScript} from "./shared/BaseDeployScript.sol";
import {Constants} from "./shared/Constants.sol";

/// @title DeploySeizureRegistry
/// @notice Deploys and initializes the SeizureRegistry UUPS proxy system.
///
/// Required env vars:
///   DEPLOYER_ADDRESS                    — transaction broadcaster; becomes v1 proxy owner
///   TOKEN_CONTRACT_ADDRESS              — FiatToken immutable (set in SeizureRegistry constructor)
///   SR_OWNER_ADDRESS                    — designated owner; receives pendingOwner after deploy
///   SR_SECONDARY_MARKET_BURNER_ADDRESS  — initial secondaryMarketBurner role
///   SR_HASH_UPDATER_ADDRESS             — initial hashUpdater role
///   SR_RESCUER_ADDRESS                  — initial rescuer role
///   SR_ADDRESS_MANAGER_ADDRESS          — initial addressManager role
///
/// Post-deploy: the designated owner must call `acceptOwnership()` on the proxy to complete
/// the 2-step ownership transfer.
contract DeploySeizureRegistry is BaseDeployScript {
    function run()
        external
        returns (address seizureRegistryImplAddress, address upgradeablePlaceholderAddress, address proxyAddress)
    {
        address deployerAddress = _readAddress(Constants.DEPLOYER_ADDRESS);
        address tokenContract = _readAddress(Constants.TOKEN_CONTRACT_ADDRESS);
        address smb = _readAddress(Constants.SR_SECONDARY_MARKET_BURNER_ADDRESS);
        address hashUpdater = _readAddress(Constants.SR_HASH_UPDATER_ADDRESS);
        address rescuer = _readAddress(Constants.SR_RESCUER_ADDRESS);
        address addressManager = _readAddress(Constants.SR_ADDRESS_MANAGER_ADDRESS);
        address owner = _readAddress(Constants.SR_OWNER_ADDRESS);

        vm.startBroadcast(deployerAddress);

        // 1. Deploy SeizureRegistry implementation
        SeizureRegistry impl = new SeizureRegistry(tokenContract);
        seizureRegistryImplAddress = address(impl);

        // 2. Deploy ERC1967 proxy pointed at placeholder; deployer becomes v1 owner.
        //    UpgradeablePlaceholder is a no-op UUPS impl that establishes proxy ownership atomically.
        UpgradeablePlaceholder placeholder = new UpgradeablePlaceholder();
        upgradeablePlaceholderAddress = address(placeholder);
        ERC1967Proxy proxy = new ERC1967Proxy(
            upgradeablePlaceholderAddress, abi.encodeCall(UpgradeablePlaceholder.initialize, (deployerAddress))
        );
        proxyAddress = address(proxy);

        // 3. Upgrade proxy to real implementation and initialize roles (reinitializer(2))
        UpgradeablePlaceholder(proxyAddress)
            .upgradeToAndCall(
                seizureRegistryImplAddress,
                abi.encodeCall(SeizureRegistry.initialize, (smb, hashUpdater, rescuer, addressManager))
            );

        // 4. Begin 2-step ownership transfer to designated owner
        SeizureRegistry(proxyAddress).transferOwnership(owner);

        vm.stopBroadcast();

        console.log("SeizureRegistry implementation: ", seizureRegistryImplAddress);
        console.log("UpgradeablePlaceholder:         ", upgradeablePlaceholderAddress);
        console.log("SeizureRegistry proxy:          ", proxyAddress);
        console.log("Pending owner (must call acceptOwnership()):", owner);
    }
}

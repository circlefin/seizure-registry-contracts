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
import {BaseDeployScript} from "deploy-contracts/shared/BaseDeployScript.sol";
import {UpgradeConstants} from "./UpgradeConstants.sol";
import {Constants} from "deploy-contracts/shared/Constants.sol";

/// @title UpgradeSeizureRegistry
/// @notice Storage-compatible upgrade script: swaps the SeizureRegistry implementation with no
///         on-chain initialization. Use this when the new implementation requires no new storage
///         state (logic-only change, different TOKEN address, etc.).
///
///         If the upgrade adds new storage fields via reinitializer(N), write a new numbered
///         script (e.g. 002_UpgradeSeizureRegistryVN.s.sol) that reads the reinitializer
///         parameters as typed env vars and encodes the calldata internally. See
///         REINITIALIZER_TEMPLATE.sol for the full pattern.
///
/// Required env vars:
///   OWNER_ADDRESS       — transaction broadcaster for the upgrade
///   SR_PROXY_ADDRESS    — the SeizureRegistry proxy to upgrade
///   SR_NEW_IMPL_ADDRESS — the newly deployed SeizureRegistry implementation
contract UpgradeSeizureRegistry is BaseDeployScript {
    // EIP-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev Snapshot of role state captured before the upgrade, used to assert nothing changed after.
    struct PreUpgradeSnapshot {
        address owner;
        address secondaryMarketBurner;
        address hashUpdater;
        address rescuer;
        address addressManager;
    }

    /// @notice Upgrades the SeizureRegistry proxy with no initialization call.
    /// @return proxyAddress   The proxy that was upgraded (SR_PROXY_ADDRESS).
    /// @return newImplAddress The new implementation now behind the proxy (SR_NEW_IMPL_ADDRESS).
    function run() external returns (address proxyAddress, address newImplAddress) {
        address owner = _readAddress(UpgradeConstants.OWNER_ADDRESS);
        proxyAddress = _readAddress(UpgradeConstants.SR_PROXY_ADDRESS);
        newImplAddress = _readAddress(UpgradeConstants.SR_NEW_IMPL_ADDRESS);

        require(proxyAddress.code.length > 0, string.concat(UpgradeConstants.SR_PROXY_ADDRESS, " has no code"));
        require(newImplAddress.code.length > 0, string.concat(UpgradeConstants.SR_NEW_IMPL_ADDRESS, " has no code"));

        address oldImplAddress = _readAddress(UpgradeConstants.SR_OLD_IMPL_ADDRESS);
        address currentImpl = address(uint160(uint256(vm.load(proxyAddress, _ERC1967_IMPL_SLOT))));
        require(currentImpl == oldImplAddress, "Current implementation does not match SR_OLD_IMPL_ADDRESS");

        console.log("\n=== SeizureRegistry Upgrade Configuration ===");
        console.log("Proxy address:      ", proxyAddress);
        console.log("New implementation: ", newImplAddress);
        console.log("Owner:              ", owner);

        console.log("\n=== Pre-Upgrade State ===");
        _logCurrentState(proxyAddress);

        SeizureRegistry sr = SeizureRegistry(proxyAddress);
        PreUpgradeSnapshot memory snapshot = PreUpgradeSnapshot({
            owner: sr.owner(),
            secondaryMarketBurner: sr.secondaryMarketBurner(),
            hashUpdater: sr.hashUpdater(),
            rescuer: sr.rescuer(),
            addressManager: sr.addressManager()
        });

        console.log("\n=== Upgrading ===");
        vm.startBroadcast(owner);
        // Empty calldata: storage-compatible upgrade only. For reinitializer upgrades, use a
        // dedicated script that reads typed env vars and encodes the calldata internally.
        SeizureRegistry(proxyAddress).upgradeToAndCall(newImplAddress, "");
        vm.stopBroadcast();

        console.log("\n=== Post-Upgrade Validation ===");
        _validateUpgrade(proxyAddress, newImplAddress, snapshot);

        console.log("\n=== SeizureRegistry Upgrade Complete ===");
    }

    function _logCurrentState(address proxyAddress) internal view {
        SeizureRegistry sr = SeizureRegistry(proxyAddress);
        address currentImpl = address(uint160(uint256(vm.load(proxyAddress, _ERC1967_IMPL_SLOT))));
        console.log("Implementation:          ", currentImpl);
        console.log("Owner:                   ", sr.owner());
        console.log("Secondary market burner: ", sr.secondaryMarketBurner());
        console.log("Hash updater:            ", sr.hashUpdater());
        console.log("Rescuer:                 ", sr.rescuer());
        console.log("Address manager:         ", sr.addressManager());
        console.log("TOKEN:                   ", address(sr.TOKEN()));
        console.log("Total SMB amount:        ", sr.totalSecondaryMarketBurnedAmount());
    }

    function _validateUpgrade(address proxyAddress, address expectedImpl, PreUpgradeSnapshot memory snapshot)
        internal
        view
    {
        address actualImpl = address(uint160(uint256(vm.load(proxyAddress, _ERC1967_IMPL_SLOT))));
        require(actualImpl == expectedImpl, "Implementation address mismatch");
        console.log("[OK] Implementation:          ", actualImpl);

        SeizureRegistry sr = SeizureRegistry(proxyAddress);
        require(sr.owner() == snapshot.owner, "Owner changed unexpectedly");
        console.log("[OK] Owner:                   ", sr.owner());

        require(
            sr.secondaryMarketBurner() == snapshot.secondaryMarketBurner, "secondaryMarketBurner changed unexpectedly"
        );
        console.log("[OK] Secondary market burner: ", sr.secondaryMarketBurner());

        require(sr.hashUpdater() == snapshot.hashUpdater, "hashUpdater changed unexpectedly");
        console.log("[OK] Hash updater:            ", sr.hashUpdater());

        require(sr.rescuer() == snapshot.rescuer, "Rescuer changed unexpectedly");
        console.log("[OK] Rescuer:                 ", sr.rescuer());

        require(sr.addressManager() == snapshot.addressManager, "addressManager changed unexpectedly");
        console.log("[OK] Address manager:         ", sr.addressManager());

        // TOKEN is intentionally not asserted: it may be changed by the upgrade.
        // Verify the logged value matches your expectation before confirming the upgrade.
        console.log("[--] TOKEN (informational):   ", address(sr.TOKEN()));
        console.log("[--] Total SMB amount:        ", sr.totalSecondaryMarketBurnedAmount());

        console.log("\nAll validations passed!");
    }
}

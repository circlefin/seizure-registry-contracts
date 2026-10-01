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
import {console} from "forge-std/console.sol";
import {Constants} from "deploy-contracts/shared/Constants.sol";

/// @title DeployedContractStateValidation
/// @notice Standalone post-deploy state checker for the SeizureRegistry UUPS proxy system.
///
/// Reads expected values from env vars and asserts each on-chain field matches.
/// All assertions use `verifyContractStateValue`; any mismatch reverts with a descriptive message.
///
/// Required env vars (shared with deploy and bytecode-validation scripts):
///   SR_PROXY_ADDRESS                    — deployed proxy
///   SR_IMPL_ADDRESS                     — expected implementation behind the EIP-1967 slot
///   DEPLOYER_ADDRESS                    — broadcaster of DeploySeizureRegistry (expected pre-transfer owner)
///   SR_OWNER_ADDRESS                    — designated owner (pendingOwner pre-transfer; owner post-transfer)
///   TOKEN_CONTRACT_ADDRESS              — expected TOKEN() immutable
///   SR_SECONDARY_MARKET_BURNER_ADDRESS  — expected secondaryMarketBurner role
///   SR_HASH_UPDATER_ADDRESS             — expected hashUpdater role
///   SR_RESCUER_ADDRESS                  — expected rescuer role
///   SR_ADDRESS_MANAGER_ADDRESS          — expected addressManager role
///
/// Optional env vars:
///   SR_OWNERSHIP_TRANSFER_COMPLETED     — "true" after AcceptOwnership has run (default: false)
contract DeployedContractStateValidation is Script {
    // ============ Low-level helper ============

    /// @notice Calls the no-arg `functionSignature` on `deployedAddress` and asserts
    ///         the return data equals `expectedValue`. Reverts on call failure or value mismatch.
    /// @param deployedAddress   Contract to query
    /// @param functionSignature Solidity function signature, e.g. "owner()"
    /// @param expectedValue     ABI-encoded expected return value
    function verifyContractStateValue(
        address deployedAddress,
        string memory functionSignature,
        bytes memory expectedValue
    ) public view {
        (bool callSuccess, bytes memory returnData) =
            deployedAddress.staticcall(abi.encodeWithSignature(functionSignature));
        require(callSuccess, string(abi.encodePacked("Function call failed: ", functionSignature)));
        require(
            keccak256(expectedValue) == keccak256(returnData),
            string(abi.encodePacked("Value validation failed: ", functionSignature))
        );
    }

    // ============ Proxy state ============

    /// @notice Asserts all proxy state variables match expected env-var values.
    ///         Ownership assertions are conditioned on `SR_OWNERSHIP_TRANSFER_COMPLETED`:
    ///           - false (default): owner == DEPLOYER_ADDRESS, pendingOwner == designated owner
    ///           - true: owner == designated owner, pendingOwner == address(0)
    /// @param proxyAddress Deployed SeizureRegistry proxy
    function verifyProxyState(address proxyAddress) public {
        console.log("Verifying SeizureRegistry proxy state...");

        bool ownershipTransferCompleted = vm.envOr(Constants.SR_OWNERSHIP_TRANSFER_COMPLETED, false);
        if (ownershipTransferCompleted) {
            verifyContractStateValue(proxyAddress, "owner()", abi.encode(vm.envAddress(Constants.SR_OWNER_ADDRESS)));
            verifyContractStateValue(proxyAddress, "pendingOwner()", abi.encode(address(0)));
        } else {
            verifyContractStateValue(proxyAddress, "owner()", abi.encode(vm.envAddress(Constants.DEPLOYER_ADDRESS)));
            verifyContractStateValue(
                proxyAddress, "pendingOwner()", abi.encode(vm.envAddress(Constants.SR_OWNER_ADDRESS))
            );
        }

        // TOKEN() is an immutable on the implementation; readable through the proxy via delegatecall.
        verifyContractStateValue(proxyAddress, "TOKEN()", abi.encode(vm.envAddress(Constants.TOKEN_CONTRACT_ADDRESS)));

        verifyContractStateValue(
            proxyAddress,
            "secondaryMarketBurner()",
            abi.encode(vm.envAddress(Constants.SR_SECONDARY_MARKET_BURNER_ADDRESS))
        );
        verifyContractStateValue(
            proxyAddress, "hashUpdater()", abi.encode(vm.envAddress(Constants.SR_HASH_UPDATER_ADDRESS))
        );
        verifyContractStateValue(proxyAddress, "rescuer()", abi.encode(vm.envAddress(Constants.SR_RESCUER_ADDRESS)));
        verifyContractStateValue(
            proxyAddress, "addressManager()", abi.encode(vm.envAddress(Constants.SR_ADDRESS_MANAGER_ADDRESS))
        );

        // A freshly-deployed registry has no secondary market burns on record.
        verifyContractStateValue(proxyAddress, "totalSecondaryMarketBurnedAmount()", abi.encode(uint256(0)));

        console.log("[OK] SeizureRegistry proxy state verified");
    }

    // ============ Proxy implementation slot ============

    /// @notice Asserts the EIP-1967 implementation slot on `proxyAddress` equals `expectedImplAddress`.
    /// @param proxyAddress        Deployed SeizureRegistry proxy
    /// @param expectedImplAddress Expected SeizureRegistry implementation address
    function verifyProxyImplementation(address proxyAddress, address expectedImplAddress) public {
        console.log("Verifying proxy implementation address...");
        bytes32 raw = vm.load(proxyAddress, bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
        address actualImplAddress = address(uint160(uint256(raw)));
        require(actualImplAddress == expectedImplAddress, "Proxy implementation address validation failed");
        console.log("[OK] Proxy implementation address verified");
    }

    // ============ Composite ============

    /// @notice Runs all state checks: proxy state variables + EIP-1967 impl slot.
    /// @param proxyAddress Deployed SeizureRegistry proxy
    /// @param implAddress  Expected SeizureRegistry implementation address
    function verifySeizureRegistryContracts(address proxyAddress, address implAddress) public {
        console.log("=== Verifying SeizureRegistry State ===");
        verifyProxyState(proxyAddress);
        verifyProxyImplementation(proxyAddress, implAddress);
        console.log("=== SeizureRegistry State Verification Complete ===");
    }

    // ============ Entry point ============

    /// @notice Reads addresses from env vars and runs all state checks.
    function run() public {
        console.log("Starting SeizureRegistry state validation...");
        address proxyAddress = vm.envAddress(Constants.SR_PROXY_ADDRESS);
        address implAddress = vm.envAddress(Constants.SR_IMPL_ADDRESS);
        verifySeizureRegistryContracts(proxyAddress, implAddress);
        console.log("All state validations completed successfully!");
    }
}

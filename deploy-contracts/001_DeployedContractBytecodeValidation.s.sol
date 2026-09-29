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
import {Constants} from "./shared/Constants.sol";

/// @title DeployedContractBytecodeValidation
/// @notice Script to verify deployed SeizureRegistry contract runtime bytecode against compiled artifacts.
/// @dev SeizureRegistry is deployed via `new`, so only runtime bytecode can be compared.
///      Immutable references (e.g. TOKEN address baked into SeizureRegistry) are handled by reading
///      compiler-emitted immutableReferences from the artifact and substituting actual on-chain values
///      before comparison.
contract DeployedContractBytecodeValidation is Script {
    /// @dev Represents one immutable slot: byte offset and length within deployed bytecode.
    struct ImmutableReference {
        uint256 start;
        uint256 length;
    }

    // ============ Public Verification Functions ============

    /// @notice Compares the runtime bytecode at `deployedAddress` against the compiled artifact for
    ///         `contractName`.  Immutable references are neutralized before comparison.
    /// @param deployedAddress On-chain address to inspect.
    /// @param contractName    Basename of the artifact in compiled-contract-artifacts/.
    /// @return success        True if runtime bytecode matches after immutable-reference substitution.
    function verifyRuntimeBytecode(address deployedAddress, string memory contractName)
        public
        view
        returns (bool success)
    {
        bytes memory actualRuntimeBytecode = deployedAddress.code;

        string memory root = vm.projectRoot();
        string memory path =
            string.concat(root, "/deploy-contracts/compiled-contract-artifacts/", contractName, ".json");
        string memory json = vm.readFile(path);
        bytes memory expectedRuntimeBytecode = abi.decode(vm.parseJson(json, ".deployedBytecode.object"), (bytes));

        // Zero out all occurrences of the deployed address in the actual bytecode so that UUPS
        // address(this) immutables are neutralized symmetrically in both buffers.
        actualRuntimeBytecode = _replaceAddressWithZeros(actualRuntimeBytecode, deployedAddress);

        // Copy actual immutable slots into the expected buffer so length and content match.
        expectedRuntimeBytecode = _swapImmutableReferences(json, expectedRuntimeBytecode, actualRuntimeBytecode);

        bool bytecodeMatches = keccak256(expectedRuntimeBytecode) == keccak256(actualRuntimeBytecode);
        if (!bytecodeMatches) {
            console.log("[ERROR] Runtime bytecode mismatch for contract:", contractName);
            console.log("  Deployed address:", deployedAddress);
            console.log("  Expected length:", expectedRuntimeBytecode.length);
            console.log("  Actual length:", actualRuntimeBytecode.length);
            console.log("  Expected hash:", vm.toString(keccak256(expectedRuntimeBytecode)));
            console.log("  Actual hash:", vm.toString(keccak256(actualRuntimeBytecode)));
        }
        return bytecodeMatches;
    }

    /// @notice Reads the EIP-1967 implementation slot of `proxyAddress` and checks it equals
    ///         `expectedImplAddress`.
    /// @param proxyAddress      Address of the ERC1967 proxy.
    /// @param expectedImplAddress Expected implementation address.
    /// @return success True if the slot value matches.
    function verifyProxyImplementation(address proxyAddress, address expectedImplAddress)
        public
        view
        returns (bool success)
    {
        bytes32 raw = vm.load(proxyAddress, bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
        address actualImpl = address(uint160(uint256(raw)));
        bool matches = actualImpl == expectedImplAddress;
        if (!matches) {
            console.log("[ERROR] Proxy implementation mismatch:");
            console.log("  Proxy:", proxyAddress);
            console.log("  Expected impl:", expectedImplAddress);
            console.log("  Actual impl:", actualImpl);
        }
        return matches;
    }

    /// @notice Verifies the SeizureRegistry constructor was called with the expected token address by
    ///         reading the TOKEN immutable baked into the deployed implementation bytecode.
    /// @param implAddress    Deployed SeizureRegistry implementation address.
    /// @param expectedToken  Expected TOKEN immutable value (passed as constructor arg at deploy time).
    /// @return success True if the on-chain TOKEN immutable matches expectedToken.
    function verifyImplConstructorArgs(address implAddress, address expectedToken) public view returns (bool success) {
        (bool ok, bytes memory data) = implAddress.staticcall(abi.encodeWithSignature("TOKEN()"));
        if (!ok || data.length == 0) {
            console.log("[ERROR] TOKEN() call failed on impl:", implAddress);
            return false;
        }
        address actualToken = abi.decode(data, (address));
        bool matches = actualToken == expectedToken;
        if (!matches) {
            console.log("[ERROR] Constructor arg mismatch - TOKEN immutable:");
            console.log("  Expected:", expectedToken);
            console.log("  Actual:", actualToken);
        }
        return matches;
    }

    /// @notice Orchestrates full bytecode validation of the SeizureRegistry system:
    ///         constructor args, implementation runtime bytecode, placeholder runtime bytecode,
    ///         proxy runtime bytecode, and proxy implementation slot.
    /// @param implAddress         Deployed SeizureRegistry implementation address.
    /// @param upgradeablePlaceholderAddress  Deployed UpgradeablePlaceholder address.
    /// @param proxyAddress        Deployed ERC1967Proxy address.
    /// @param expectedToken       Expected TOKEN constructor arg.
    function verifySeizureRegistryContracts(
        address implAddress,
        address upgradeablePlaceholderAddress,
        address proxyAddress,
        address expectedToken
    ) public view {
        console.log("=== Verifying SeizureRegistry Contracts ===");

        // 1. Verify SeizureRegistry constructor args (TOKEN immutable).
        console.log("Verifying SeizureRegistry constructor args...");
        bool constructorValid = verifyImplConstructorArgs(implAddress, expectedToken);
        require(constructorValid, "SeizureRegistry constructor args verification failed");
        console.log("[OK] SeizureRegistry constructor args verified");

        // 2. Verify SeizureRegistry implementation runtime bytecode.
        console.log("Verifying SeizureRegistry implementation runtime bytecode...");
        bool implRuntimeValid = verifyRuntimeBytecode(implAddress, "SeizureRegistry");
        require(implRuntimeValid, "SeizureRegistry implementation runtime bytecode verification failed");
        console.log("[OK] SeizureRegistry implementation runtime bytecode verified");

        // 3. Verify UpgradeablePlaceholder runtime bytecode.
        console.log("Verifying UpgradeablePlaceholder runtime bytecode...");
        bool upgradeablePlaceholderRuntimeValid =
            verifyRuntimeBytecode(upgradeablePlaceholderAddress, "UpgradeablePlaceholder");
        require(upgradeablePlaceholderRuntimeValid, "UpgradeablePlaceholder runtime bytecode verification failed");
        console.log("[OK] UpgradeablePlaceholder runtime bytecode verified");

        // 4. Verify proxy runtime bytecode.
        console.log("Verifying ERC1967Proxy runtime bytecode...");
        bool proxyRuntimeValid = verifyRuntimeBytecode(proxyAddress, "ERC1967Proxy");
        require(proxyRuntimeValid, "ERC1967Proxy runtime bytecode verification failed");
        console.log("[OK] ERC1967Proxy runtime bytecode verified");

        // 5. Verify proxy implementation slot points to the SeizureRegistry impl.
        console.log("Verifying proxy implementation slot...");
        bool implSlotValid = verifyProxyImplementation(proxyAddress, implAddress);
        require(implSlotValid, "Proxy implementation slot verification failed");
        console.log("[OK] Proxy implementation slot verified");

        console.log("=== SeizureRegistry Bytecode Verification Complete ===");
    }

    /// @notice Entry point for running bytecode validation against live or forked network addresses.
    /// @dev Required env vars: SR_IMPL_ADDRESS, SR_UPGRADEABLE_PLACEHOLDER_IMPL_ADDRESS, SR_PROXY_ADDRESS,
    ///      TOKEN_CONTRACT_ADDRESS.
    function run() public view {
        address implAddress = vm.envAddress(Constants.SR_IMPL_ADDRESS);
        address upgradeablePlaceholderAddress = vm.envAddress(Constants.SR_UPGRADEABLE_PLACEHOLDER_IMPL_ADDRESS);
        address proxyAddress = vm.envAddress(Constants.SR_PROXY_ADDRESS);
        address expectedToken = vm.envAddress(Constants.TOKEN_CONTRACT_ADDRESS);

        verifySeizureRegistryContracts(implAddress, upgradeablePlaceholderAddress, proxyAddress, expectedToken);

        console.log("All bytecode validations completed successfully!");
    }

    // ============ Internal Helpers ============

    /// @dev Copies the actual on-chain bytes into the expected buffer at every immutable-reference
    ///      slot declared in the artifact JSON, making the two buffers comparable.
    function _swapImmutableReferences(
        string memory artifactJson,
        bytes memory expectedBytecode,
        bytes memory actualBytecode
    ) internal pure returns (bytes memory) {
        try vm.parseJsonKeys(artifactJson, ".deployedBytecode.immutableReferences") returns (string[] memory keys) {
            if (keys.length == 0) {
                console.log("[DEBUG] No immutable references found in artifact JSON");
                return expectedBytecode;
            }
            if (actualBytecode.length == 0) {
                console.log("[DEBUG] Actual bytecode is empty, skipping immutable reference swap");
                return expectedBytecode;
            }

            for (uint256 i = 0; i < keys.length; i++) {
                string memory path = string.concat(".deployedBytecode.immutableReferences.", keys[i]);
                bytes memory raw = vm.parseJson(artifactJson, path);
                ImmutableReference[] memory refs = abi.decode(raw, (ImmutableReference[]));

                for (uint256 j = 0; j < refs.length; j++) {
                    uint256 start = refs[j].start;
                    uint256 length = refs[j].length;

                    if (start + length > expectedBytecode.length || start + length > actualBytecode.length) {
                        console.log("[WARNING] Immutable ref out of bounds, skipping");
                        console.log("  start:", start);
                        console.log("  length:", length);
                        console.log("  expected length:", expectedBytecode.length);
                        console.log("  actual length:", actualBytecode.length);
                        continue;
                    }

                    for (uint256 k = 0; k < length; k++) {
                        expectedBytecode[start + k] = actualBytecode[start + k];
                    }
                }
            }
            return expectedBytecode;
        } catch {
            console.log("[WARNING] Failed to parse immutable references from artifact JSON");
            return expectedBytecode;
        }
    }

    /// @dev Replaces every 20-byte occurrence of `targetAddress` in `bytecode` with zero bytes.
    function _replaceAddressWithZeros(bytes memory bytecode, address targetAddress)
        internal
        pure
        returns (bytes memory)
    {
        if (bytecode.length < 20) return bytecode;

        bytes memory target = abi.encodePacked(targetAddress);
        for (uint256 i = 0; i <= bytecode.length - 20; i++) {
            bool matches = true;
            for (uint256 j = 0; j < 20; j++) {
                if (bytecode[i + j] != target[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                for (uint256 k = 0; k < 20; k++) {
                    bytecode[i + k] = bytes1(0);
                }
            }
        }
        return bytecode;
    }
}

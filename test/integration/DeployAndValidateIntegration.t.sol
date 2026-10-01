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

import {Test} from "forge-std/Test.sol";
import {DeploySeizureRegistry} from "deploy-contracts/000_DeploySeizureRegistry.s.sol";
import {DeployedContractBytecodeValidation} from "deploy-contracts/001_DeployedContractBytecodeValidation.s.sol";
import {DeployedContractStateValidation} from "deploy-contracts/002_DeployedContractStateValidation.s.sol";
import {AcceptOwnership} from "deploy-contracts/AcceptOwnership.s.sol";
import {Constants} from "deploy-contracts/shared/Constants.sol";

/// @title DeployAndValidateIntegrationTest
/// @notice Integration test that deploys the SeizureRegistry system then validates bytecode.
///         Mirrors the xReserve DeployAndValidateIntegration pattern: one setUp deploys everything,
///         each test exercises one slice of validation.
contract DeployAndValidateIntegrationTest is Test {
    DeploySeizureRegistry public deployScript;
    DeployedContractBytecodeValidation public bytecodeValidation;
    DeployedContractStateValidation public stateValidation;
    AcceptOwnership public acceptOwnershipScript;

    address public constant DEPLOYER = address(0x1111111111111111111111111111111111111111);
    address public constant TOKEN = address(0x2222222222222222222222222222222222222222);
    address public constant OWNER = address(0x3333333333333333333333333333333333333333);
    address public constant SMB = address(0x4444444444444444444444444444444444444444);
    address public constant HASH_UPDATER = address(0x5555555555555555555555555555555555555555);
    address public constant RESCUER = address(0x6666666666666666666666666666666666666666);
    address public constant ADDRESS_MANAGER = address(0x7777777777777777777777777777777777777777);

    address public implAddress;
    address public upgradeablePlaceholderAddress;
    address public proxyAddress;

    function setUp() public {
        deployScript = new DeploySeizureRegistry();
        bytecodeValidation = new DeployedContractBytecodeValidation();
        stateValidation = new DeployedContractStateValidation();
        acceptOwnershipScript = new AcceptOwnership();

        _setEnvVars();

        (implAddress, upgradeablePlaceholderAddress, proxyAddress) = deployScript.run();

        vm.setEnv(Constants.SR_IMPL_ADDRESS, vm.toString(implAddress));
        vm.setEnv(Constants.SR_UPGRADEABLE_PLACEHOLDER_IMPL_ADDRESS, vm.toString(upgradeablePlaceholderAddress));
        vm.setEnv(Constants.SR_PROXY_ADDRESS, vm.toString(proxyAddress));
    }

    // ============ Deploy sanity ============

    function test_deploy_success() public view {
        assertNotEq(implAddress, address(0), "impl should be deployed");
        assertNotEq(upgradeablePlaceholderAddress, address(0), "upgradeable placeholder should be deployed");
        assertNotEq(proxyAddress, address(0), "proxy should be deployed");
        assertNotEq(implAddress, proxyAddress, "impl and proxy must differ");
        assertGt(implAddress.code.length, 0, "impl must have code");
        assertGt(upgradeablePlaceholderAddress.code.length, 0, "upgradeable placeholder must have code");
        assertGt(proxyAddress.code.length, 0, "proxy must have code");
    }

    // ============ Constructor arg validation ============

    function test_constructorArgs_success() public view {
        bool ok = bytecodeValidation.verifyImplConstructorArgs(implAddress, TOKEN);
        assertTrue(ok, "TOKEN constructor arg should match");
    }

    function test_constructorArgs_wrongToken_fails() public view {
        bool ok = bytecodeValidation.verifyImplConstructorArgs(implAddress, address(0xDEAD));
        assertFalse(ok, "Should fail for wrong TOKEN address");
    }

    function test_constructorArgs_zeroAddress_fails() public view {
        bool ok = bytecodeValidation.verifyImplConstructorArgs(address(0), TOKEN);
        assertFalse(ok, "Should fail when impl address is zero");
    }

    // ============ Bytecode validation — happy paths ============

    function test_bytecodeValidation_seizureRegistryImpl_success() public view {
        bool ok = bytecodeValidation.verifyRuntimeBytecode(implAddress, "SeizureRegistry");
        assertTrue(ok, "SeizureRegistry impl runtime bytecode should match");
    }

    function test_bytecodeValidation_upgradeablePlaceholder_success() public view {
        bool ok = bytecodeValidation.verifyRuntimeBytecode(upgradeablePlaceholderAddress, "UpgradeablePlaceholder");
        assertTrue(ok, "UpgradeablePlaceholder runtime bytecode should match");
    }

    function test_bytecodeValidation_proxy_success() public view {
        bool ok = bytecodeValidation.verifyRuntimeBytecode(proxyAddress, "ERC1967Proxy");
        assertTrue(ok, "ERC1967Proxy runtime bytecode should match");
    }

    function test_bytecodeValidation_proxyImplSlot_success() public view {
        bool ok = bytecodeValidation.verifyProxyImplementation(proxyAddress, implAddress);
        assertTrue(ok, "Proxy impl slot should point to SeizureRegistry impl");
    }

    function test_bytecodeValidation_fullSystem_success() public view {
        bytecodeValidation.verifySeizureRegistryContracts(
            implAddress, upgradeablePlaceholderAddress, proxyAddress, TOKEN
        );
    }

    function test_bytecodeValidation_run_success() public view {
        bytecodeValidation.run();
    }

    // ============ Bytecode validation — failure paths ============

    function test_bytecodeValidation_wrongImplAddress_fails() public view {
        bool ok = bytecodeValidation.verifyRuntimeBytecode(
            address(0x9999999999999999999999999999999999999999), "SeizureRegistry"
        );
        assertFalse(ok, "Should fail for random address with no code");
    }

    function test_bytecodeValidation_zeroImplAddress_fails() public view {
        bool ok = bytecodeValidation.verifyRuntimeBytecode(address(0), "SeizureRegistry");
        assertFalse(ok, "Should fail for address(0)");
    }

    function test_bytecodeValidation_wrongExpectedImpl_fails() public view {
        bool ok = bytecodeValidation.verifyProxyImplementation(proxyAddress, address(0xDEAD));
        assertFalse(ok, "Should fail when expected impl does not match slot");
    }

    function test_bytecodeValidation_fullSystem_wrongConstructorArgs_reverts() public {
        vm.expectRevert(bytes("SeizureRegistry constructor args verification failed"));
        bytecodeValidation.verifySeizureRegistryContracts(
            implAddress, upgradeablePlaceholderAddress, proxyAddress, address(0xDEAD)
        );
    }

    function test_bytecodeValidation_fullSystem_wrongImpl_reverts() public {
        vm.expectRevert(bytes("SeizureRegistry constructor args verification failed"));
        bytecodeValidation.verifySeizureRegistryContracts(
            address(0x9999999999999999999999999999999999999999), upgradeablePlaceholderAddress, proxyAddress, TOKEN
        );
    }

    function test_bytecodeValidation_fullSystem_wrongUpgradeablePlaceholder_reverts() public {
        vm.expectRevert(bytes("UpgradeablePlaceholder runtime bytecode verification failed"));
        bytecodeValidation.verifySeizureRegistryContracts(
            implAddress, address(0x9999999999999999999999999999999999999999), proxyAddress, TOKEN
        );
    }

    function test_bytecodeValidation_fullSystem_wrongProxy_reverts() public {
        vm.expectRevert(bytes("ERC1967Proxy runtime bytecode verification failed"));
        bytecodeValidation.verifySeizureRegistryContracts(
            implAddress, upgradeablePlaceholderAddress, address(0x9999999999999999999999999999999999999999), TOKEN
        );
    }

    // ============ State validation — happy paths ============

    function test_stateValidation_run_success() public {
        // Verify pre-transfer state: owner is still deployer, pendingOwner is designated owner.
        vm.setEnv(Constants.SR_OWNERSHIP_TRANSFER_COMPLETED, "false");
        stateValidation.run();
    }

    function test_acceptOwnership_fullHandoff() public {
        // Complete the 2-step ownership transfer to the designated owner via the AcceptOwnership script.
        acceptOwnershipScript.run();

        // Confirm the handoff: owner is now OWNER, pendingOwner is cleared.
        (bool okOwner, bytes memory ownerData) = proxyAddress.call(abi.encodeWithSignature("owner()"));
        assertTrue(okOwner);
        assertEq(abi.decode(ownerData, (address)), OWNER);

        (bool okPending, bytes memory pendingData) = proxyAddress.call(abi.encodeWithSignature("pendingOwner()"));
        assertTrue(okPending);
        assertEq(abi.decode(pendingData, (address)), address(0));

        // State validation must also pass in the post-transfer configuration.
        vm.setEnv(Constants.SR_OWNERSHIP_TRANSFER_COMPLETED, "true");
        stateValidation.run();
    }

    // ============ State validation — failure cases ============

    function test_verifyContractStateValue_wrongExpectedValue_fails() public {
        vm.expectRevert(bytes("Value validation failed: owner()"));
        stateValidation.verifyContractStateValue(
            proxyAddress, "owner()", abi.encode(address(0x9999999999999999999999999999999999999999))
        );
    }

    function test_verifyContractStateValue_nonExistentFunction_fails() public {
        vm.expectRevert(bytes("Function call failed: nonExistentFunction()"));
        stateValidation.verifyContractStateValue(proxyAddress, "nonExistentFunction()", abi.encode(address(0)));
    }

    function test_verifyContractStateValue_zeroAddress_fails() public {
        // address(0) has no code — call returns (true, "") so the value comparison fails.
        vm.expectRevert(bytes("Value validation failed: owner()"));
        stateValidation.verifyContractStateValue(address(0), "owner()", abi.encode(DEPLOYER));
    }

    function test_verifyContractStateValue_nonExistentContract_fails() public {
        // An EOA/empty address behaves the same as address(0): returns empty bytes.
        vm.expectRevert(bytes("Value validation failed: owner()"));
        stateValidation.verifyContractStateValue(
            address(0x9999999999999999999999999999999999999999), "owner()", abi.encode(DEPLOYER)
        );
    }

    function test_verifyProxyImplementation_wrongExpectedImplementation_fails() public {
        vm.expectRevert(bytes("Proxy implementation address validation failed"));
        stateValidation.verifyProxyImplementation(proxyAddress, address(0xDEADBEEF));
    }

    function test_verifyProxyImplementation_zeroExpectedImplementation_fails() public {
        vm.expectRevert(bytes("Proxy implementation address validation failed"));
        stateValidation.verifyProxyImplementation(proxyAddress, address(0));
    }

    function test_verifyProxyImplementation_wrongProxyAddress_fails() public {
        vm.expectRevert(bytes("Proxy implementation address validation failed"));
        stateValidation.verifyProxyImplementation(address(0x9999999999999999999999999999999999999999), implAddress);
    }

    function test_verifyProxyState_wrongProxyAddress_fails() public {
        vm.setEnv(Constants.SR_OWNERSHIP_TRANSFER_COMPLETED, "false");
        vm.expectRevert(bytes("Value validation failed: owner()"));
        stateValidation.verifyProxyState(address(0x9999999999999999999999999999999999999999));
    }

    function test_verifyProxyState_zeroProxyAddress_fails() public {
        vm.setEnv(Constants.SR_OWNERSHIP_TRANSFER_COMPLETED, "false");
        vm.expectRevert(bytes("Value validation failed: owner()"));
        stateValidation.verifyProxyState(address(0));
    }

    function test_verifySeizureRegistryContracts_wrongImpl_fails() public {
        vm.setEnv(Constants.SR_OWNERSHIP_TRANSFER_COMPLETED, "false");
        vm.expectRevert(bytes("Proxy implementation address validation failed"));
        stateValidation.verifySeizureRegistryContracts(proxyAddress, address(0xDEADBEEF));
    }

    function test_verifySeizureRegistryContracts_wrongProxy_fails() public {
        vm.setEnv(Constants.SR_OWNERSHIP_TRANSFER_COMPLETED, "false");
        vm.expectRevert(bytes("Value validation failed: owner()"));
        stateValidation.verifySeizureRegistryContracts(address(0x9999999999999999999999999999999999999999), implAddress);
    }

    // ============ Internal helpers ============

    function _setEnvVars() internal {
        vm.setEnv(Constants.DEPLOYER_ADDRESS, vm.toString(DEPLOYER));
        vm.setEnv(Constants.TOKEN_CONTRACT_ADDRESS, vm.toString(TOKEN));
        vm.setEnv(Constants.SR_OWNER_ADDRESS, vm.toString(OWNER));
        vm.setEnv(Constants.SR_SECONDARY_MARKET_BURNER_ADDRESS, vm.toString(SMB));
        vm.setEnv(Constants.SR_HASH_UPDATER_ADDRESS, vm.toString(HASH_UPDATER));
        vm.setEnv(Constants.SR_RESCUER_ADDRESS, vm.toString(RESCUER));
        vm.setEnv(Constants.SR_ADDRESS_MANAGER_ADDRESS, vm.toString(ADDRESS_MANAGER));
        // Reset explicitly: vm.setEnv is not rolled back between tests, so a test that sets
        // SR_OWNERSHIP_TRANSFER_COMPLETED=true would otherwise pollute subsequent tests.
        vm.setEnv(Constants.SR_OWNERSHIP_TRANSFER_COMPLETED, "false");
    }
}

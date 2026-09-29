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
import {Constants} from "deploy-contracts/shared/Constants.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";

/// @dev Harness that overrides _readAddress to use in-storage values instead of env vars.
///      Foundry's EVM snapshot preserves storage, making cross-test isolation reliable.
contract DeploySeizureRegistryHarness is DeploySeizureRegistry {
    mapping(string => address) private _env;

    function setAddr(string memory key, address val) external {
        _env[key] = val;
    }

    function _readAddress(string memory envKey) internal view override returns (address addr) {
        addr = _env[envKey];
        require(addr != address(0), string.concat(envKey, " is zero"));
    }
}

contract DeploySeizureRegistryTest is Test {
    // EIP-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    DeploySeizureRegistryHarness private _script;

    address private _deployerAddress;
    address private _tokenAddress;
    address private _owner;
    address private _secondaryMarketBurner;
    address private _hashUpdater;
    address private _rescuer;
    address private _addressManager;

    function setUp() public {
        _deployerAddress = makeAddr("deployer");
        _owner = makeAddr("owner");
        _secondaryMarketBurner = makeAddr("secondaryMarketBurner");
        _hashUpdater = makeAddr("hashUpdater");
        _rescuer = makeAddr("rescuer");
        _addressManager = makeAddr("addressManager");
        // Deploy script only checks TOKEN_CONTRACT_ADDRESS is non-zero (Immutables constructor).
        // No token functions are called, so any non-zero address is sufficient.
        _tokenAddress = makeAddr("token");

        _script = new DeploySeizureRegistryHarness();
        _script.setAddr(Constants.DEPLOYER_ADDRESS, _deployerAddress);
        _script.setAddr(Constants.TOKEN_CONTRACT_ADDRESS, _tokenAddress);
        _script.setAddr(Constants.SR_SECONDARY_MARKET_BURNER_ADDRESS, _secondaryMarketBurner);
        _script.setAddr(Constants.SR_HASH_UPDATER_ADDRESS, _hashUpdater);
        _script.setAddr(Constants.SR_RESCUER_ADDRESS, _rescuer);
        _script.setAddr(Constants.SR_ADDRESS_MANAGER_ADDRESS, _addressManager);
        _script.setAddr(Constants.SR_OWNER_ADDRESS, _owner);
    }

    // ============ Happy path ============

    function test_run_success() public {
        (address implAddress, address upgradeablePlaceholderAddress, address proxyAddress) = _script.run();

        // All three contracts deployed
        assertNotEq(implAddress, address(0));
        assertNotEq(upgradeablePlaceholderAddress, address(0));
        assertNotEq(proxyAddress, address(0));
        assertNotEq(implAddress, proxyAddress);
        assertGt(implAddress.code.length, 0);
        assertGt(upgradeablePlaceholderAddress.code.length, 0);
        assertGt(proxyAddress.code.length, 0);

        // ERC1967 impl slot points at our implementation
        address storedImpl = address(uint160(uint256(vm.load(proxyAddress, _ERC1967_IMPL_SLOT))));
        assertEq(storedImpl, implAddress);

        SeizureRegistry registry = SeizureRegistry(proxyAddress);

        // Immutable wired correctly
        assertEq(address(registry.TOKEN()), _tokenAddress);

        // All four roles initialized
        assertEq(registry.secondaryMarketBurner(), _secondaryMarketBurner);
        assertEq(registry.hashUpdater(), _hashUpdater);
        assertEq(registry.rescuer(), _rescuer);
        assertEq(registry.addressManager(), _addressManager);

        // Deployer is current owner; designated owner is pending (must call acceptOwnership)
        assertEq(registry.owner(), _deployerAddress);
        assertEq(registry.pendingOwner(), _owner);
    }

    // ============ Zero-address guards ============

    function test_run_revertsWhen_zeroDeployer() public {
        _script.setAddr(Constants.DEPLOYER_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(Constants.DEPLOYER_ADDRESS, " is zero")));
        _script.run();
    }

    function test_run_revertsWhen_zeroTokenContract() public {
        _script.setAddr(Constants.TOKEN_CONTRACT_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(Constants.TOKEN_CONTRACT_ADDRESS, " is zero")));
        _script.run();
    }

    function test_run_revertsWhen_zeroSecondaryMarketBurner() public {
        _script.setAddr(Constants.SR_SECONDARY_MARKET_BURNER_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(Constants.SR_SECONDARY_MARKET_BURNER_ADDRESS, " is zero")));
        _script.run();
    }

    function test_run_revertsWhen_zeroHashUpdater() public {
        _script.setAddr(Constants.SR_HASH_UPDATER_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(Constants.SR_HASH_UPDATER_ADDRESS, " is zero")));
        _script.run();
    }

    function test_run_revertsWhen_zeroRescuer() public {
        _script.setAddr(Constants.SR_RESCUER_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(Constants.SR_RESCUER_ADDRESS, " is zero")));
        _script.run();
    }

    function test_run_revertsWhen_zeroAddressManager() public {
        _script.setAddr(Constants.SR_ADDRESS_MANAGER_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(Constants.SR_ADDRESS_MANAGER_ADDRESS, " is zero")));
        _script.run();
    }

    function test_run_revertsWhen_zeroOwner() public {
        _script.setAddr(Constants.SR_OWNER_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(Constants.SR_OWNER_ADDRESS, " is zero")));
        _script.run();
    }
}

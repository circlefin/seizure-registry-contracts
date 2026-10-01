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

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {UpgradeSeizureRegistry} from "deploy-contracts/upgrade/001_UpgradeSeizureRegistry.s.sol";
import {UpgradeConstants} from "deploy-contracts/upgrade/UpgradeConstants.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";

/// @dev Harness that replaces env-var reads with in-memory maps so the upgrade script
///      can be exercised in tests without real environment setup.
contract UpgradeSeizureRegistryHarness is UpgradeSeizureRegistry {
    mapping(string => address) private _addrEnv;

    function setAddr(string memory key, address val) external {
        _addrEnv[key] = val;
    }

    function _readAddress(string memory envKey) internal view override returns (address addr) {
        addr = _addrEnv[envKey];
        require(addr != address(0), string.concat(envKey, " is zero"));
    }
}

contract UpgradeSeizureRegistryTest is Test {
    // EIP-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    UpgradeSeizureRegistryHarness private _script;

    address private _owner;
    address private _tokenAddress;
    address private _secondaryMarketBurner;
    address private _hashUpdater;
    address private _rescuer;
    address private _addressManager;

    address private _proxyAddress;
    address private _v1ImplAddress;

    function setUp() public {
        _owner = makeAddr("owner");
        _tokenAddress = makeAddr("token");
        _secondaryMarketBurner = makeAddr("secondaryMarketBurner");
        _hashUpdater = makeAddr("hashUpdater");
        _rescuer = makeAddr("rescuer");
        _addressManager = makeAddr("addressManager");

        // Deploy V1 proxy (same inline pattern as SeizureRegistryIntegrationTest)
        _v1ImplAddress = address(new SeizureRegistry(_tokenAddress));
        UpgradeablePlaceholder placeholder = new UpgradeablePlaceholder();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(placeholder), abi.encodeCall(UpgradeablePlaceholder.initialize, (address(this))));
        UpgradeablePlaceholder(address(proxy))
            .upgradeToAndCall(
                _v1ImplAddress,
                abi.encodeCall(
                    SeizureRegistry.initialize, (_secondaryMarketBurner, _hashUpdater, _rescuer, _addressManager)
                )
            );
        _proxyAddress = address(proxy);

        // Complete 2-step ownership transfer so _owner is the active proxy owner
        SeizureRegistry(_proxyAddress).transferOwnership(_owner);
        vm.prank(_owner);
        SeizureRegistry(_proxyAddress).acceptOwnership();

        // Wire harness — OWNER_ADDRESS must be the proxy owner (authorizes the upgrade)
        _script = new UpgradeSeizureRegistryHarness();
        _script.setAddr(UpgradeConstants.OWNER_ADDRESS, _owner);
        _script.setAddr(UpgradeConstants.SR_PROXY_ADDRESS, _proxyAddress);
        _script.setAddr(UpgradeConstants.SR_OLD_IMPL_ADDRESS, _v1ImplAddress);
    }

    // ============ Happy path ============

    /// @notice Storage-compatible upgrade: new impl with different TOKEN immutable, no initData.
    function test_run_success() public {
        address newTokenAddress = makeAddr("newToken");
        address newImpl = address(new SeizureRegistry(newTokenAddress));
        _script.setAddr(UpgradeConstants.SR_NEW_IMPL_ADDRESS, newImpl);

        (address proxyOut, address implOut) = _script.run();

        assertEq(proxyOut, _proxyAddress);
        assertEq(implOut, newImpl);

        // ERC-1967 impl slot points at new impl
        address storedImpl = address(uint160(uint256(vm.load(_proxyAddress, _ERC1967_IMPL_SLOT))));
        assertEq(storedImpl, newImpl, "ERC-1967 impl slot should point at new impl");

        SeizureRegistry registry = SeizureRegistry(_proxyAddress);

        assertEq(address(registry.TOKEN()), newTokenAddress, "TOKEN should reflect new impl's constructor arg");

        // All four roles preserved
        assertEq(registry.secondaryMarketBurner(), _secondaryMarketBurner, "secondaryMarketBurner should be preserved");
        assertEq(registry.hashUpdater(), _hashUpdater, "hashUpdater should be preserved");
        assertEq(registry.rescuer(), _rescuer, "rescuer should be preserved");
        assertEq(registry.addressManager(), _addressManager, "addressManager should be preserved");

        // Ownership preserved
        assertEq(registry.owner(), _owner, "owner should be preserved");

        // Total SMB amount is zero — no SMBs were executed in this test, so this only confirms the
        // getter is reachable post-upgrade. Non-zero preservation is covered by the integration tests.
        assertEq(registry.totalSecondaryMarketBurnedAmount(), 0, "totalSecondaryMarketBurnedAmount should be zero");
    }

    // ============ Zero-address guards ============

    function test_run_revertsWhen_zeroOwner() public {
        _script.setAddr(UpgradeConstants.OWNER_ADDRESS, address(0));
        _script.setAddr(UpgradeConstants.SR_NEW_IMPL_ADDRESS, _v1ImplAddress);
        vm.expectRevert(bytes(string.concat(UpgradeConstants.OWNER_ADDRESS, " is zero")));
        _script.run();
    }

    function test_run_revertsWhen_zeroProxy() public {
        _script.setAddr(UpgradeConstants.SR_PROXY_ADDRESS, address(0));
        _script.setAddr(UpgradeConstants.SR_NEW_IMPL_ADDRESS, _v1ImplAddress);
        vm.expectRevert(bytes(string.concat(UpgradeConstants.SR_PROXY_ADDRESS, " is zero")));
        _script.run();
    }

    function test_run_revertsWhen_zeroNewImpl() public {
        _script.setAddr(UpgradeConstants.SR_NEW_IMPL_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(UpgradeConstants.SR_NEW_IMPL_ADDRESS, " is zero")));
        _script.run();
    }

    // ============ Pre-condition guards ============

    function test_run_revertsWhen_proxyHasNoCode() public {
        address emptyAddr = makeAddr("empty");
        _script.setAddr(UpgradeConstants.SR_PROXY_ADDRESS, emptyAddr);
        _script.setAddr(UpgradeConstants.SR_NEW_IMPL_ADDRESS, _v1ImplAddress);
        vm.expectRevert(bytes(string.concat(UpgradeConstants.SR_PROXY_ADDRESS, " has no code")));
        _script.run();
    }

    function test_run_revertsWhen_newImplHasNoCode() public {
        address emptyAddr = makeAddr("empty");
        _script.setAddr(UpgradeConstants.SR_NEW_IMPL_ADDRESS, emptyAddr);
        vm.expectRevert(bytes(string.concat(UpgradeConstants.SR_NEW_IMPL_ADDRESS, " has no code")));
        _script.run();
    }

    function test_run_revertsWhen_implMismatch() public {
        address wrongOldImpl = makeAddr("wrongOldImpl");
        _script.setAddr(UpgradeConstants.SR_OLD_IMPL_ADDRESS, wrongOldImpl);
        address newImpl = address(new SeizureRegistry(makeAddr("newToken")));
        _script.setAddr(UpgradeConstants.SR_NEW_IMPL_ADDRESS, newImpl);
        vm.expectRevert(bytes("Current implementation does not match SR_OLD_IMPL_ADDRESS"));
        _script.run();
    }
}

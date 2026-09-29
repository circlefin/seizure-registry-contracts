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
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AcceptOwnership} from "deploy-contracts/AcceptOwnership.s.sol";
import {Constants} from "deploy-contracts/shared/Constants.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";

/// @dev Harness that overrides _readAddress to use in-storage values instead of env vars.
contract AcceptOwnershipScriptHarness is AcceptOwnership {
    mapping(string => address) private _env;

    function setAddr(string memory key, address val) external {
        _env[key] = val;
    }

    function _readAddress(string memory envKey) internal view override returns (address addr) {
        addr = _env[envKey];
        require(addr != address(0), string.concat(envKey, " is zero"));
    }
}

contract AcceptOwnershipTest is Test {
    AcceptOwnershipScriptHarness private _script;

    address private _deployer;
    address private _designatedOwner;
    address private _proxyAddress;

    function setUp() public {
        _deployer = makeAddr("deployer");
        _designatedOwner = makeAddr("designatedOwner");
        address token = makeAddr("token");
        address smb = makeAddr("smb");
        address hashUpdater = makeAddr("hashUpdater");
        address rescuer = makeAddr("rescuer");
        address addressManager = makeAddr("addressManager");

        // Replicate the deploy script sequence so tests start with a live proxy
        // that has a pending ownership transfer to _designatedOwner.
        vm.startPrank(_deployer);
        SeizureRegistry impl = new SeizureRegistry(token);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(new UpgradeablePlaceholder()), abi.encodeCall(UpgradeablePlaceholder.initialize, (_deployer))
        );
        _proxyAddress = address(proxy);
        UpgradeablePlaceholder(_proxyAddress)
            .upgradeToAndCall(
                address(impl), abi.encodeCall(SeizureRegistry.initialize, (smb, hashUpdater, rescuer, addressManager))
            );
        SeizureRegistry(_proxyAddress).transferOwnership(_designatedOwner);
        vm.stopPrank();

        _script = new AcceptOwnershipScriptHarness();
        _script.setAddr(Constants.SR_PROXY_ADDRESS, _proxyAddress);
        _script.setAddr(Constants.SR_OWNER_ADDRESS, _designatedOwner);
    }

    // ============ Happy path ============

    function test_run_success() public {
        SeizureRegistry registry = SeizureRegistry(_proxyAddress);

        assertEq(registry.owner(), _deployer, "Initial owner should be the deployer");
        assertEq(registry.pendingOwner(), _designatedOwner, "Pending owner should be the designated owner");

        _script.run();

        assertEq(registry.owner(), _designatedOwner, "Owner should be the designated owner");
        assertEq(registry.pendingOwner(), address(0), "Pending owner should not be set");
    }

    // ============ Zero-address guards ============

    function test_run_revertsWhen_zeroProxyAddress() public {
        _script.setAddr(Constants.SR_PROXY_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(Constants.SR_PROXY_ADDRESS, " is zero")));
        _script.run();
    }

    function test_run_revertsWhen_zeroOwner() public {
        _script.setAddr(Constants.SR_OWNER_ADDRESS, address(0));
        vm.expectRevert(bytes(string.concat(Constants.SR_OWNER_ADDRESS, " is zero")));
        _script.run();
    }

    // ============ Pre-flight checks ============

    function test_run_revertsWhen_ownerAddressMismatchesPendingOwner() public {
        _script.setAddr(Constants.SR_OWNER_ADDRESS, makeAddr("notPendingOwner"));
        vm.expectRevert(bytes("SR_OWNER_ADDRESS does not match pendingOwner on proxy"));
        _script.run();
    }
}

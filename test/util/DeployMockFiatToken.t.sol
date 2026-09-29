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
import {MasterMinter} from "test/mocks/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "test/mocks/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "test/mocks/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployMockFiatToken} from "test/util/DeployMockFiatToken.sol";
import {ForkTestUtils} from "test/util/ForkTestUtils.sol";

contract TestDeployMockFiatToken is Test {
    DeployMockFiatToken private mockTokenDeployer;

    function setUp() public {
        mockTokenDeployer = new DeployMockFiatToken();
    }

    function test_deployMockFiatToken() public {
        vm.skip(block.chainid != ForkTestUtils.LOCAL_CHAIN_ID);
        (FiatTokenV2_2 fiatToken, MasterMinter masterMinter, FiatTokenProxy proxy) = mockTokenDeployer.deploy();

        validateImpl(fiatToken);
        validateMasterMinter(masterMinter, address(proxy));
        validateProxy(proxy, address(fiatToken), address(masterMinter));
    }

    function validateImpl(FiatTokenV2_2 impl) internal view {
        assertEq(impl.name(), "");
        assertEq(impl.symbol(), "");
        assertEq(impl.currency(), "");
        assert(impl.decimals() == 0);
        assertEq(impl.owner(), address(1));
        assertEq(impl.masterMinter(), address(1));
        assertEq(impl.pauser(), address(1));
        assertEq(impl.blacklister(), address(1));
    }

    function validateProxy(FiatTokenProxy proxy, address _impl, address _masterMinter) internal view {
        assertEq(proxy.admin(), mockTokenDeployer.proxyAdmin());
        assertEq(proxy.implementation(), _impl);

        FiatTokenV2_2 proxyAsFiatToken = FiatTokenV2_2(address(proxy));
        assertEq(proxyAsFiatToken.name(), "USDC");
        assertEq(proxyAsFiatToken.symbol(), "USDC");
        assertEq(proxyAsFiatToken.currency(), "USD");
        assert(proxyAsFiatToken.decimals() == 6);
        assertEq(proxyAsFiatToken.owner(), mockTokenDeployer.owner());
        assertEq(proxyAsFiatToken.pauser(), mockTokenDeployer.pauser());
        assertEq(proxyAsFiatToken.blacklister(), mockTokenDeployer.blacklister());
        assertEq(proxyAsFiatToken.masterMinter(), _masterMinter);
    }

    function validateMasterMinter(MasterMinter masterMinter, address _proxy) internal view {
        assertEq(masterMinter.owner(), mockTokenDeployer.masterMinterOwner());
        assertEq(address(masterMinter.getMinterManager()), _proxy);
    }
}

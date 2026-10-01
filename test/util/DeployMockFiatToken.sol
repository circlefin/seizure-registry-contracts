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

import {CommonBase} from "forge-std/Base.sol";
import {MasterMinter} from "test/mocks/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "test/mocks/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "test/mocks/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployFiatToken} from "test/mocks/mock_fiattoken/deploy-fiat-token.s.sol";

// Contract to deploy mock FiatToken (USDC) contract for local testing. Copied with minor modification from @circlefin/stablecoin-evm/test/scripts/deploy/TestUtils.sol
// solhint-disable-next-line max-states-count
contract DeployMockFiatToken is CommonBase {
    uint256 internal deployerPrivateKey = 1;
    uint256 internal proxyAdminPrivateKey = 2;
    uint256 internal masterMinterOwnerPrivateKey = 3;
    uint256 internal ownerPrivateKey = 4;
    uint256 internal pauserPrivateKey = 5;
    uint256 internal blacklisterPrivateKey = 6;

    address public deployer = vm.addr(deployerPrivateKey);
    address public proxyAdmin = vm.addr(proxyAdminPrivateKey);
    address public masterMinterOwner = vm.addr(masterMinterOwnerPrivateKey);
    address public owner = vm.addr(ownerPrivateKey);
    address public pauser = vm.addr(pauserPrivateKey);
    address public blacklister = vm.addr(blacklisterPrivateKey);

    uint8 internal decimals = 6;
    string internal tokenName = "USDC";
    string internal tokenSymbol = "USDC";
    string internal tokenCurrency = "USD";

    DeployFiatToken private deployScript;

    function setUpMockFiatTokenConfig() private {
        vm.setEnv("TOKEN_NAME", tokenName);
        vm.setEnv("TOKEN_SYMBOL", tokenSymbol);
        vm.setEnv("TOKEN_CURRENCY", tokenCurrency);
        vm.setEnv("TOKEN_DECIMALS", "6");
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("PROXY_ADMIN_ADDRESS", vm.toString(proxyAdmin));
        vm.setEnv("MASTER_MINTER_OWNER_ADDRESS", vm.toString(masterMinterOwner));
        vm.setEnv("OWNER_ADDRESS", vm.toString(owner));
        vm.setEnv("PAUSER_ADDRESS", vm.toString(pauser));
        vm.setEnv("BLACKLISTER_ADDRESS", vm.toString(blacklister));

        // Deploy an instance of proxy contract to configure contract address in env
        vm.prank(deployer);
        FiatTokenV2_2 fiatToken = new FiatTokenV2_2();

        vm.prank(proxyAdmin);
        FiatTokenProxy proxy = new FiatTokenProxy(address(fiatToken));

        vm.startPrank(deployer);
        MasterMinter masterMinter = new MasterMinter(address(proxy));
        masterMinter.transferOwnership(masterMinterOwner);

        FiatTokenV2_2 proxyAsFiatToken = FiatTokenV2_2(address(proxy));

        proxyAsFiatToken.initialize(
            tokenName,
            tokenSymbol,
            "USD",
            decimals,
            address(masterMinter),
            pauser,
            blacklister,
            vm.addr(ownerPrivateKey)
        );
        proxyAsFiatToken.initializeV2(tokenName);
        proxyAsFiatToken.initializeV2_1(owner);
        proxyAsFiatToken.initializeV2_2(new address[](0), tokenSymbol);
        vm.setEnv("FIAT_TOKEN_PROXY_ADDRESS", vm.toString(address(proxy)));

        vm.stopPrank();
    }

    function deploy() public returns (FiatTokenV2_2, MasterMinter, FiatTokenProxy) {
        setUpMockFiatTokenConfig();

        vm.prank(deployer);
        deployScript = new DeployFiatToken();
        deployScript.setUp();
        return deployScript.run();
    }
}

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
import {ForkTestUtils} from "test/util/ForkTestUtils.sol";

contract TestForkTestUtils is Test {
    function test_forkVars_ethereum() external {
        vm.chainId(ForkTestUtils.ETHEREUM_CHAIN_ID);
        ForkTestUtils.ForkVars memory vars = ForkTestUtils.forkVars();
        assertEq(vars.usdc, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    }

    function test_forkVars_local() external {
        vm.skip(block.chainid != ForkTestUtils.LOCAL_CHAIN_ID);
        vm.chainId(ForkTestUtils.LOCAL_CHAIN_ID);
        ForkTestUtils.ForkVars memory vars = ForkTestUtils.forkVars();

        // Gas reports affect the deployment address of FiatTokenV2_2 for some reason, so detect this and assert the
        // correct address. Must use this environment variable to run gas reports, not --gas-report (`yarn test:gas`)
        if (vm.envOr("FORGE_GAS_REPORT", false)) {
            assertEq(vars.usdc, 0xB9816fC57977D5A786E654c7CF76767be63b966e);
        } else {
            assertEq(vars.usdc, 0x63f58053c9499E1104a6f6c6d2581d6D83067EEB);
        }
    }

    function test_forkVars_unknown() external {
        vm.chainId(123);
        vm.expectRevert(abi.encodeWithSelector(ForkTestUtils.UnknownChain.selector, 123));
        ForkTestUtils.forkVars();
    }
}

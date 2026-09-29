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

import {FiatTokenProxy} from "test/mocks/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {DeployMockFiatToken} from "test/util/DeployMockFiatToken.sol";

/// Helpers for managing values and dependencies between forks
library ForkTestUtils {
    error UnknownChain(uint256 id);

    uint32 public constant LOCAL_DOMAIN = 99;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 public constant ETHEREUM_CHAIN_ID = 1;
    uint256 public constant ETHEREUM_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ARBITRUM_CHAIN_ID = 42161;
    uint256 public constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    uint256 public constant BASE_CHAIN_ID = 8453;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;

    struct ForkVars {
        address usdc;
        uint32 domain;
    }

    /// @notice Returns the USDC address and domain for the current chain
    /// @dev Domain values are defined by Circle and can be found at https://developers.circle.com/stablecoins/supported-domains
    /// @return ForkVars struct containing:
    ///         - usdc: The USDC contract address for the current chain
    ///         - domain: The Circle-defined domain ID for the current chain
    function forkVars() public returns (ForkVars memory) {
        if (block.chainid == LOCAL_CHAIN_ID) {
            return deployLocalDependencies();
        }

        if (block.chainid == ETHEREUM_CHAIN_ID) {
            return ForkVars({usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, domain: 0});
        }

        if (block.chainid == ETHEREUM_SEPOLIA_CHAIN_ID) {
            return ForkVars({usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, domain: 0});
        }

        if (block.chainid == ARBITRUM_CHAIN_ID) {
            return ForkVars({usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831, domain: 3});
        }

        if (block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID) {
            return ForkVars({usdc: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d, domain: 3});
        }

        if (block.chainid == BASE_CHAIN_ID) {
            return ForkVars({usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, domain: 6});
        }

        if (block.chainid == BASE_SEPOLIA_CHAIN_ID) {
            return ForkVars({usdc: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, domain: 6});
        }

        revert UnknownChain(block.chainid);
    }

    function deployLocalDependencies() public returns (ForkVars memory) {
        DeployMockFiatToken mockTokenDeployer = new DeployMockFiatToken();
        (,, FiatTokenProxy proxy) = mockTokenDeployer.deploy();
        return ForkVars({usdc: address(proxy), domain: LOCAL_DOMAIN});
    }
}

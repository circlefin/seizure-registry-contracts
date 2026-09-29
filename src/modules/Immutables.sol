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

import {ZeroAddress} from "../common/Errors.sol";
import {IMintableToken} from "../interfaces/IMintableToken.sol";

/// @title Immutables
/// @notice Holds the immutable external contract addresses set at deploy time.
///         Inherited by the main SeizureRegistry contract.
contract Immutables {
    /// @notice The FiatToken contract used to re-mint Secondary Market Burned balances
    IMintableToken public immutable TOKEN; // solhint-disable-line immutable-vars-naming

    /// @notice Initializes the immutable token address
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param token_ The FiatToken contract address
    constructor(address token_) {
        if (token_ == address(0)) revert ZeroAddress();
        TOKEN = IMintableToken(token_);
    }
}

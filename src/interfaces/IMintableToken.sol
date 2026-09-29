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

/// @title IMintableToken
/// @notice Minimal interface for the FiatToken entrypoints used by the Seizure Registry
interface IMintableToken {
    /// @notice Mints new tokens to a recipient
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    /// @return True if the mint succeeded
    function mint(address to, uint256 amount) external returns (bool);
}

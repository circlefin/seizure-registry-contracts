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
import {ZeroAddress} from "src/common/Errors.sol";
import {Immutables} from "src/modules/Immutables.sol";

contract ImmutablesTest is Test, Immutables {
    address internal constant TOKEN_ADDRESS = address(0x1111);

    constructor() Immutables(TOKEN_ADDRESS) {}

    function test_immutablesAreSetCorrectly() public view {
        assertEq(address(TOKEN), TOKEN_ADDRESS, "token not set correctly");
    }

    function test_revertsOnZeroToken() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        new Immutables(address(0));
    }
}

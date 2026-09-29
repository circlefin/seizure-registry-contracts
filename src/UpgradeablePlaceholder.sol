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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/// @title UpgradeablePlaceholder
/// @notice No-op UUPS implementation deployed before the real contract to establish proxy ownership
///         atomically at proxy deploy time.
/// @dev Standard placeholder contract for UUPS proxies. Unlike `SeizureRegistry`, this contract does
///      not override `renounceOwnership`; ownership can be renounced while the placeholder occupies
///      the proxy. The ownerless-proxy invariant is only enforced once the proxy is upgraded to
///      `SeizureRegistry`.
contract UpgradeablePlaceholder is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable {
    /// @notice Thrown when the owner address is zero.
    error NullOwnerNotAllowed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the placeholder, setting the proxy owner before the real implementation exists.
    /// @param newOwner The initial owner address
    function initialize(address newOwner) external initializer {
        if (newOwner == address(0)) revert NullOwnerNotAllowed();
        __Ownable_init(newOwner);
        __Ownable2Step_init();
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

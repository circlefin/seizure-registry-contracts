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

/// @title UpgradeConstants
/// @notice Environment variable key names used by SeizureRegistry upgrade scripts.
library UpgradeConstants {
    // ============ Env var keys ============

    /// @notice The transaction broadcaster for the upgrade. Must be the current proxy owner.
    string internal constant OWNER_ADDRESS = "OWNER_ADDRESS";

    /// @notice The deployed SeizureRegistry proxy address to upgrade.
    string internal constant SR_PROXY_ADDRESS = "SR_PROXY_ADDRESS";

    /// @notice The current implementation address behind the proxy (pre-upgrade).
    ///         Used to assert the proxy is in the expected state before broadcasting.
    string internal constant SR_OLD_IMPL_ADDRESS = "SR_OLD_IMPL_ADDRESS";

    /// @notice The newly deployed SeizureRegistry implementation address to upgrade to.
    string internal constant SR_NEW_IMPL_ADDRESS = "SR_NEW_IMPL_ADDRESS";
}

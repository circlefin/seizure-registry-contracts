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

/// @title Constants
/// @notice Environment variable key names used by SeizureRegistry deploy scripts.
///         All addresses come from env vars; no per-env salts
library Constants {
    // ============ Env var keys ============

    string internal constant DEPLOYER_ADDRESS = "DEPLOYER_ADDRESS";
    string internal constant TOKEN_CONTRACT_ADDRESS = "TOKEN_CONTRACT_ADDRESS";
    string internal constant SR_OWNER_ADDRESS = "SR_OWNER_ADDRESS";
    string internal constant SR_SECONDARY_MARKET_BURNER_ADDRESS = "SR_SECONDARY_MARKET_BURNER_ADDRESS";
    string internal constant SR_HASH_UPDATER_ADDRESS = "SR_HASH_UPDATER_ADDRESS";
    string internal constant SR_RESCUER_ADDRESS = "SR_RESCUER_ADDRESS";
    string internal constant SR_ADDRESS_MANAGER_ADDRESS = "SR_ADDRESS_MANAGER_ADDRESS";

    // ============ Bytecode validation env var keys ============

    string internal constant SR_IMPL_ADDRESS = "SR_IMPL_ADDRESS";
    string internal constant SR_UPGRADEABLE_PLACEHOLDER_IMPL_ADDRESS = "SR_UPGRADEABLE_PLACEHOLDER_IMPL_ADDRESS";
    string internal constant SR_PROXY_ADDRESS = "SR_PROXY_ADDRESS";

    // ============ State validation env var keys ============

    /// @dev Set to "true" after AcceptOwnership runs. Shifts ownership assertions from
    ///      (owner=deployer, pendingOwner=designatedOwner) to (owner=designatedOwner, pendingOwner=zero).
    string internal constant SR_OWNERSHIP_TRANSFER_COMPLETED = "SR_OWNERSHIP_TRANSFER_COMPLETED";
}

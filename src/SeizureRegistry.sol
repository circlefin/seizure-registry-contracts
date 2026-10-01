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
import {HashUpdatable, HashUpdatableStorage} from "./modules/HashUpdatable.sol";
import {Rescuable} from "./modules/Rescuable.sol";
import {Immutables} from "./modules/Immutables.sol";
import {SecondaryMarketBurnableStorage} from "./modules/SecondaryMarketBurnable.sol";

/// @title SeizureRegistry
/// @notice On-chain seizure audit trail and re-mint orchestration for stablecoin asset recovery.
///         Composes SecondaryMarketBurnable, HashUpdatable, Allowlistable, and Rescuable modules.
/// @dev UUPS upgradeable proxy; ownership is 2-step. `renounceOwnership` is disabled. The
///      `tokenContract` immutable is set once in the constructor; the proxy is initialized via
///      `initialize`.
///      Note on `transferOwnership`: the inherited implementation does not validate that `newOwner`
///      is nonzero; passing the zero address is permitted by the base contract and silently cancels
///      any pending handover while emitting the same `OwnershipTransferStarted` event as a
///      legitimate nomination. Callers are responsible for ensuring `newOwner` is the intended address.
contract SeizureRegistry is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable, HashUpdatable, Rescuable {
    // ============ Errors ============

    /// @notice Thrown when `renounceOwnership` is called; disabled to prevent bricking the proxy.
    error RenounceOwnershipDisabled();

    // ============ Constructor ============

    /// @notice Sets the immutable token contract address and disables initializers on the implementation.
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param tokenContract_ The FiatToken contract address; reverts on zero address (via Immutables)
    constructor(address tokenContract_) Immutables(tokenContract_) {
        _disableInitializers();
    }

    // ============ Initialization ============

    /// @notice Initializes the proxy modules. Ownership is established at v1 by UpgradeablePlaceholder;
    ///         this function (v2) only initializes the four role modules. It is intended to be called
    ///         exclusively by the proxy owner via `upgradeToAndCall`. This constraint is procedural
    ///         (the upgrade path itself is owner-gated).
    /// @param secondaryMarketBurner_ The initial SecondaryMarketBurner role address
    /// @param hashUpdater_           The initial HashUpdater role address
    /// @param rescuer_               The initial Rescuer role address
    /// @param addressManager_        The initial AddressManager role address
    function initialize(address secondaryMarketBurner_, address hashUpdater_, address rescuer_, address addressManager_)
        external
        reinitializer(2)
    {
        __SecondaryMarketBurnable_init(secondaryMarketBurner_);
        __HashUpdatable_init(hashUpdater_);
        __Allowlistable_init(addressManager_);
        __Rescuable_init(rescuer_);
    }

    // ============ View Functions ============

    /// @notice Returns the combined SecondaryMarketBurned record and remint tx hash for a cross-chain address.
    /// @param secondaryMarketBurnedAddress The raw cross-chain address to query
    /// @param domain                       The domain on which the address resides
    /// @return burnedAddress   The queried raw cross-chain address, echoed from the caller's input
    /// @return domain_         The queried domain, echoed from the caller's input, and defines where the secondary market burned address resides
    /// @return balance         The blocklisted balance that was burned and re-minted; zero if not yet recorded
    /// @return remintRecipient The allowlisted recipient that received the re-minted balance; zero if not yet recorded
    /// @return remintTxHash    The on-chain transaction hash of the remint; zero if not yet set
    function getSecondaryMarketBurnRecord(bytes calldata secondaryMarketBurnedAddress, uint32 domain)
        public
        view
        returns (
            bytes memory burnedAddress,
            uint32 domain_,
            uint256 balance,
            address remintRecipient,
            bytes32 remintTxHash
        )
    {
        SecondaryMarketBurnableStorage.RemintRecord memory smb = SecondaryMarketBurnableStorage.get()
        .records[domain][secondaryMarketBurnedAddress];
        return (
            secondaryMarketBurnedAddress,
            domain,
            smb.balance,
            smb.remintRecipient,
            HashUpdatableStorage.get().remintTxHashes[domain][secondaryMarketBurnedAddress]
        );
    }

    /// @notice Returns the combined SecondaryMarketBurned record and remint tx hash for an EVM address.
    /// @param secondaryMarketBurnedAddress The EVM address to query
    /// @param domain                       The domain on which the address resides
    /// @return burnedAddress   The queried EVM address, echoed from the caller's input
    /// @return domain_         The queried domain, echoed from the caller's input, and defines where the secondary market burned address resides
    /// @return balance         The blocklisted balance that was burned and re-minted; zero if not yet recorded
    /// @return remintRecipient The allowlisted recipient that received the re-minted balance; zero if not yet recorded
    /// @return remintTxHash    The on-chain transaction hash of the remint; zero if not yet set
    function getSecondaryMarketBurnRecord(address secondaryMarketBurnedAddress, uint32 domain)
        public
        view
        returns (address burnedAddress, uint32 domain_, uint256 balance, address remintRecipient, bytes32 remintTxHash)
    {
        bytes memory addr = abi.encodePacked(secondaryMarketBurnedAddress);
        SecondaryMarketBurnableStorage.RemintRecord memory smb =
            SecondaryMarketBurnableStorage.get().records[domain][addr];
        return (
            secondaryMarketBurnedAddress,
            domain,
            smb.balance,
            smb.remintRecipient,
            HashUpdatableStorage.get().remintTxHashes[domain][addr]
        );
    }

    // ============ Ownership ============

    /// @notice Disabled — irreversible ownership loss would brick the proxy.
    function renounceOwnership() public override onlyOwner {
        revert RenounceOwnershipDisabled();
    }

    // ============ Upgrade ============

    /// @inheritdoc UUPSUpgradeable
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

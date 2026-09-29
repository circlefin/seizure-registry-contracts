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

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {UnauthorizedCaller} from "src/common/Errors.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {SecondaryMarketBurnable} from "src/modules/SecondaryMarketBurnable.sol";
import {Allowlistable} from "src/modules/Allowlistable.sol";
import {HashUpdatable} from "src/modules/HashUpdatable.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";
import {MasterMinter} from "test/mocks/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "test/mocks/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "test/mocks/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployMockFiatToken} from "test/util/DeployMockFiatToken.sol";

contract SeizureRegistryFuzzTest is Test {
    // Maximum address byte length across all supported chains (Stellar: 33 bytes is the largest real case;
    // 64 is a generous upper bound that keeps gas predictable and avoids pathological mapping key hashing).
    uint256 internal constant _MAX_ADDR_LEN = 64;

    SeizureRegistry internal _registry;

    DeployMockFiatToken private _usdc;
    FiatTokenV2_2 internal _token;
    MasterMinter internal _masterMinter;

    address internal _owner = makeAddr("owner");
    address internal _secondaryMarketBurner = makeAddr("secondaryMarketBurner");
    address internal _hashUpdater = makeAddr("hashUpdater");
    address internal _rescuer = makeAddr("rescuer");
    address internal _addressManager = makeAddr("addressManager");
    address internal _recipient = makeAddr("recipient");

    function setUp() public {
        _usdc = new DeployMockFiatToken();
        FiatTokenProxy proxy;
        (, _masterMinter, proxy) = _usdc.deploy();
        _token = FiatTokenV2_2(address(proxy));

        address impl = address(new SeizureRegistry(address(_token)));
        UpgradeablePlaceholder placeholder = new UpgradeablePlaceholder();
        ERC1967Proxy registryProxy =
            new ERC1967Proxy(address(placeholder), abi.encodeCall(UpgradeablePlaceholder.initialize, (address(this))));
        UpgradeablePlaceholder(address(registryProxy))
            .upgradeToAndCall(
                impl,
                abi.encodeCall(
                    SeizureRegistry.initialize, (_secondaryMarketBurner, _hashUpdater, _rescuer, _addressManager)
                )
            );
        _registry = SeizureRegistry(address(registryProxy));

        _registry.transferOwnership(_owner);
        vm.prank(_owner);
        _registry.acceptOwnership();

        vm.startPrank(_usdc.masterMinterOwner());
        _masterMinter.configureController(_usdc.masterMinterOwner(), address(_registry));
        _masterMinter.configureMinter(0);
        vm.stopPrank();

        vm.prank(_addressManager);
        _registry.addAllowedRecipient(_recipient);
    }

    // ============ Helpers ============

    function _grantMintAllowance(uint256 amount) private {
        vm.prank(_usdc.masterMinterOwner());
        _masterMinter.incrementMinterAllowance(amount);
    }

    function _secondaryMarketBurn(bytes memory addr, uint32 domain, uint256 balance) private {
        _grantMintAllowance(balance);
        vm.prank(_secondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(addr, domain, balance, _recipient);
    }

    // ============ Fuzz: arbitrary cross-chain addresses ============

    /// @dev Any non-empty byte sequence up to _MAX_ADDR_LEN with non-zero balance burns correctly
    ///      and records state consistently across all view functions.
    function testFuzz_burnAndRemint_arbitraryAddress(bytes calldata addr, uint32 domain, uint256 balance) external {
        vm.assume(addr.length > 0 && addr.length <= _MAX_ADDR_LEN);
        balance = bound(balance, 1, type(uint128).max);

        _secondaryMarketBurn(addr, domain, balance);

        assertTrue(_registry.isSecondaryMarketBurned(addr, domain), "isSecondaryMarketBurned false after burn");
        assertEq(_registry.secondaryMarketBurnedBalance(addr, domain), balance, "Balance mismatch");
        assertEq(_registry.totalSecondaryMarketBurnedAmount(), balance, "Global total mismatch");
        assertEq(_registry.totalSecondaryMarketBurnedAmount(domain), balance, "Domain total mismatch");
    }

    // ============ Fuzz: SMB idempotency ============

    /// @dev Once burned, any subsequent burn attempt for the same (addr, domain) pair reverts,
    ///      regardless of the address encoding or domain value. secondBalance is intentionally
    ///      omitted — AlreadySecondaryMarketBurned fires before balance is read.
    function testFuzz_burnIdempotency_reburnReverts(bytes calldata addr, uint32 domain, uint256 balance) external {
        vm.assume(addr.length > 0 && addr.length <= _MAX_ADDR_LEN);
        balance = bound(balance, 1, type(uint128).max);

        _secondaryMarketBurn(addr, domain, balance);

        _grantMintAllowance(balance);
        vm.expectRevert(
            abi.encodeWithSelector(SecondaryMarketBurnable.AlreadySecondaryMarketBurned.selector, addr, domain)
        );
        vm.prank(_secondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(addr, domain, balance, _recipient);
    }
}

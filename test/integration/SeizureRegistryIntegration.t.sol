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

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {SecondaryMarketBurnable} from "src/modules/SecondaryMarketBurnable.sol";
import {SeizureRegistry} from "src/SeizureRegistry.sol";
import {UpgradeablePlaceholder} from "src/UpgradeablePlaceholder.sol";
import {MasterMinter} from "test/mocks/mock_fiattoken/contracts/minting/MasterMinter.sol";
import {FiatTokenProxy} from "test/mocks/mock_fiattoken/contracts/v1/FiatTokenProxy.sol";
import {FiatTokenV2_2} from "test/mocks/mock_fiattoken/contracts/v2/FiatTokenV2_2.sol";
import {DeployMockFiatToken} from "test/util/DeployMockFiatToken.sol";

contract SeizureRegistryIntegrationTest is Test {
    SeizureRegistry internal _registry;

    DeployMockFiatToken private _usdc;
    FiatTokenV2_2 internal _token;
    MasterMinter internal _masterMinter;

    address internal _owner = makeAddr("owner");
    address internal _secondaryMarketBurner = makeAddr("secondaryMarketBurner");
    address internal _hashUpdater = makeAddr("hashUpdater");
    address internal _rescuer = makeAddr("rescuer");
    address internal _addressManager = makeAddr("addressManager");

    bytes internal constant _BURNED_ADDR = abi.encodePacked(address(0xbeef));
    uint32 internal constant _DOMAIN = 1;

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
    }

    // ============ Helpers ============

    function _grantAllowance(uint256 amount) internal {
        vm.prank(_usdc.masterMinterOwner());
        _masterMinter.incrementMinterAllowance(amount);
    }

    function _allowlist(address recipient) internal {
        vm.prank(_addressManager);
        _registry.addAllowedRecipient(recipient);
    }

    // ============ Tests ============

    /// @notice Full allowance lifecycle: allowance granted → burn+remint → allowance fully consumed.
    function test_fullAllowanceLifecycle() public {
        address leRecipient = makeAddr("leRecipient");
        uint256 balance = 1_000e6;

        assertEq(address(_registry.TOKEN()), address(_token));
        assertEq(_registry.owner(), _owner);
        assertEq(_registry.secondaryMarketBurner(), _secondaryMarketBurner);
        assertEq(_registry.addressManager(), _addressManager);

        _allowlist(leRecipient);

        assertEq(
            _token.minterAllowance(address(_registry)), 0, "Registry minter allowance should be zero before funding"
        );
        _grantAllowance(balance);
        assertEq(
            _token.minterAllowance(address(_registry)),
            balance,
            "Registry minter allowance should equal the funded amount"
        );

        vm.expectEmit(true, true, false, true, address(_registry));
        emit SecondaryMarketBurnable.SecondaryMarketBurnRecorded(_BURNED_ADDR, _DOMAIN, balance, leRecipient);
        vm.prank(_secondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(_BURNED_ADDR, _DOMAIN, balance, leRecipient);

        assertEq(
            _token.minterAllowance(address(_registry)), 0, "Registry minter allowance should be consumed after mint"
        );
        assertEq(_token.balanceOf(leRecipient), balance, "Recipient should receive the reminted balance");
        assertTrue(
            _registry.isSecondaryMarketBurned(_BURNED_ADDR, _DOMAIN),
            "SecondaryMarketBurn record should exist after mint"
        );
        assertEq(_registry.totalSecondaryMarketBurnedAmount(), balance);
        assertEq(_registry.totalSecondaryMarketBurnedAmount(_DOMAIN), balance);
    }

    /// @notice removeMinter circuit-breaker: blocks minting with no partial state, and is fully reversible.
    function test_removeMinter_pauseAndResume() public {
        address leRecipient = makeAddr("leRecipient");
        uint256 balance = 500e6;

        _allowlist(leRecipient);
        _grantAllowance(balance);

        // Remove registry as minter — simulates the circuit-breaker being pulled
        vm.prank(_usdc.masterMinterOwner());
        _masterMinter.removeMinter();
        assertFalse(_token.isMinter(address(_registry)));
        assertEq(_token.minterAllowance(address(_registry)), 0);

        // Burn attempt must revert; no partial state written
        vm.expectRevert("FiatToken: caller is not a minter");
        vm.prank(_secondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(_BURNED_ADDR, _DOMAIN, balance, leRecipient);

        assertFalse(_registry.isSecondaryMarketBurned(_BURNED_ADDR, _DOMAIN));
        assertEq(_registry.totalSecondaryMarketBurnedAmount(), 0);
        assertEq(_token.balanceOf(leRecipient), 0);

        // Re-add: the controller→worker mapping persists; only re-configure minter status
        vm.startPrank(_usdc.masterMinterOwner());
        _masterMinter.configureMinter(0);
        vm.stopPrank();
        assertTrue(_token.isMinter(address(_registry)));
        assertEq(_token.minterAllowance(address(_registry)), 0);

        _grantAllowance(balance);
        vm.prank(_secondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(_BURNED_ADDR, _DOMAIN, balance, leRecipient);

        assertEq(_token.balanceOf(leRecipient), balance, "Recipient should receive the reminted balance after resume");
        assertTrue(
            _registry.isSecondaryMarketBurned(_BURNED_ADDR, _DOMAIN),
            "SecondaryMarketBurn record should exist after resume"
        );
        assertEq(
            _registry.secondaryMarketBurnedBalance(_BURNED_ADDR, _DOMAIN),
            balance,
            "Recorded SecondaryMarketBurned balance should be restored after resume"
        );
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(_DOMAIN),
            balance,
            "Per-domain SecondaryMarketBurned total should be restored after resume"
        );
        assertEq(
            _registry.totalSecondaryMarketBurnedAmount(),
            balance,
            "Global SecondaryMarketBurned total should be restored after resume"
        );

        (bytes memory burnedAddress, uint32 domain, uint256 recordedBalance, address recipient, bytes32 remintTxHash) =
            _registry.getSecondaryMarketBurnRecord(_BURNED_ADDR, _DOMAIN);
        assertEq(burnedAddress, _BURNED_ADDR, "Record should retain the SecondaryMarketBurned address");
        assertEq(domain, _DOMAIN, "Record should retain the source domain");
        assertEq(recordedBalance, balance, "Record should retain the reminted balance");
        assertEq(recipient, leRecipient, "Record should retain the remint recipient");
        assertEq(remintTxHash, bytes32(0), "Remint transaction hash should be unset");
    }

    /// @notice Same address burned on 3 domains: per-domain records are independent and global total is correct.
    function test_multiDomain_sameAddress() public {
        bytes memory burnedAddr = abi.encodePacked(makeAddr("victim"));
        uint32[] memory domains = new uint32[](3);
        domains[0] = 1;
        domains[1] = 2;
        domains[2] = 3;
        uint256[] memory balances = new uint256[](3);
        balances[0] = 100e6;
        balances[1] = 200e6;
        balances[2] = 300e6;
        address[] memory leRecipients = new address[](3);
        leRecipients[0] = makeAddr("le1");
        leRecipients[1] = makeAddr("le2");
        leRecipients[2] = makeAddr("le3");

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(_addressManager);
            _registry.addAllowedRecipient(leRecipients[i]);
        }

        for (uint256 i = 0; i < 3; i++) {
            _grantAllowance(balances[i]);
            vm.prank(_secondaryMarketBurner);
            _registry.secondaryMarketBurnAndRemint(burnedAddr, domains[i], balances[i], leRecipients[i]);
        }

        assertTrue(_registry.isSecondaryMarketBurned(burnedAddr, 1));
        assertTrue(_registry.isSecondaryMarketBurned(burnedAddr, 2));
        assertTrue(_registry.isSecondaryMarketBurned(burnedAddr, 3));
        assertFalse(_registry.isSecondaryMarketBurned(burnedAddr, 4));

        assertEq(_registry.totalSecondaryMarketBurnedAmount(1), 100e6);
        assertEq(_registry.totalSecondaryMarketBurnedAmount(2), 200e6);
        assertEq(_registry.totalSecondaryMarketBurnedAmount(3), 300e6);
        assertEq(_registry.totalSecondaryMarketBurnedAmount(), 600e6);

        assertEq(_token.balanceOf(leRecipients[0]), 100e6);
        assertEq(_token.balanceOf(leRecipients[1]), 200e6);
        assertEq(_token.balanceOf(leRecipients[2]), 300e6);

        for (uint256 i = 0; i < 3; i++) {
            (bytes memory retAddr, uint32 retDomain, uint256 retBalance, address retRecipient, bytes32 retHash) =
                _registry.getSecondaryMarketBurnRecord(burnedAddr, domains[i]);
            assertEq(retAddr, burnedAddr);
            assertEq(retDomain, domains[i]);
            assertEq(retBalance, balances[i]);
            assertEq(retRecipient, leRecipients[i]);
            assertEq(retHash, bytes32(0));
        }

        // 4th domain succeeds — proves no cross-domain interference
        _grantAllowance(50e6);
        vm.prank(_secondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(burnedAddr, 4, 50e6, leRecipients[0]);

        assertTrue(_registry.isSecondaryMarketBurned(burnedAddr, 4));
        assertEq(_registry.totalSecondaryMarketBurnedAmount(), 650e6);
    }

    /// @notice Gas baseline for secondaryMarketBurnAndRemint — no assertion, captured via --gas-report.
    function test_gasBaseline_secondaryMarketBurnAndRemint() public {
        address leRecipient = makeAddr("leRecipient");
        _allowlist(leRecipient);
        _grantAllowance(1e6);
        vm.prank(_secondaryMarketBurner);
        _registry.secondaryMarketBurnAndRemint(_BURNED_ADDR, _DOMAIN, 1e6, leRecipient);
    }
}

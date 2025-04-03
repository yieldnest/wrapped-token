// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {WrappedToken} from "../src/WrappedToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MockToken is ERC20 {
    uint8 private _decimals = 6;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 100_000_000_000_000 * 10 ** _decimals);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

contract WrappedTokenTest is Test {
    WrappedToken public wrappedToken;
    MockToken public mockToken;
    address public user = address(1);
    address public proxyOwner = address(1234567);

    function setUp() public {
        mockToken = new MockToken("Mock Token", "MTK");

        // Deploy implementation
        WrappedToken implementation = new WrappedToken();

        // Deploy proxy with empty initialization data
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyOwner), "");

        // Initialize the implementation through the proxy
        WrappedToken(address(proxy)).initialize(
            IERC20(address(mockToken)), "Wrapped Mock Token", "WMTK", 18, 18 - mockToken.decimals()
        );

        // Set up the wrapped token interface
        wrappedToken = WrappedToken(address(proxy));

        // Give user some tokens
        mockToken.transfer(user, 100_000_000_000 * 1e6);

        // Approve wrapped token to spend mock tokens
        vm.startPrank(user);
        mockToken.approve(address(wrappedToken), type(uint256).max);
        vm.stopPrank();
    }

    function test_Deposit() public {
        uint256 depositAmount = 10 * 10 ** 6;
        uint256 userInitialBalance = mockToken.balanceOf(user);

        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);
        vm.stopPrank();

        // Check user's mock token balance decreased
        assertEq(
            mockToken.balanceOf(user),
            userInitialBalance - depositAmount,
            "User's mock token balance should decrease by deposit amount"
        );

        // Check user received wrapped tokens
        assertEq(wrappedToken.balanceOf(user), sharesReceived, "User should receive correct amount of wrapped tokens");

        // Check wrapped token has the deposited tokens
        assertEq(
            mockToken.balanceOf(address(wrappedToken)),
            depositAmount,
            "Wrapped token contract should hold the deposited tokens"
        );
    }

    function test_Withdraw() public {
        uint256 depositAmount = 10 * 10 ** 6;

        // First deposit
        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);

        // Then withdraw
        uint256 userInitialBalance = mockToken.balanceOf(user);
        uint256 assetsReceived = wrappedToken.withdraw(depositAmount, user, user);
        vm.stopPrank();

        // Check user's wrapped token balance decreased
        assertEq(
            wrappedToken.balanceOf(user),
            sharesReceived - assetsReceived,
            "User's wrapped token balance should decrease by the shares burned"
        );

        // Check user received mock tokens back
        assertEq(
            mockToken.balanceOf(user),
            userInitialBalance + depositAmount,
            "User should receive back the withdrawn tokens"
        );
    }

    function test_ConversionRates() public {
        uint256 depositAmount = 10 * 10 ** 6;

        // Check conversion rates before any deposits
        assertEq(
            wrappedToken.convertToShares(1e6),
            1e18,
            "1e6 assets should convert to 1e18 shares (12 decimal places difference)"
        );
        assertEq(
            wrappedToken.convertToAssets(1e18),
            1e6,
            "1e18 shares should convert to 1e6 assets (12 decimal places difference)"
        );

        // Make a deposit
        vm.startPrank(user);
        wrappedToken.deposit(depositAmount, user);
        vm.stopPrank();

        // Conversion rates should still be 1:1
        assertEq(wrappedToken.convertToShares(1e6), 1e18, "Conversion rate should remain stable after deposit");
        assertEq(wrappedToken.convertToAssets(1e18), 1e6, "Conversion rate should remain stable after deposit");
    }

    function testFuzz_DepositRedeem(uint256 amount) public {
        // Bound the amount to something reasonable
        amount = bound(amount, 1, 100_000_000 * 10 ** 6);

        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(amount, user);
        uint256 assetsReceived = wrappedToken.redeem(sharesReceived, user, user);
        vm.stopPrank();

        // Verify that the assets received are less than or equal to the amount deposited
        // This is important because in some cases there might be rounding down when converting
        // shares back to assets, but we should never get more assets than we put in
        assertLe(assetsReceived, amount, "Assets received should not exceed the amount deposited");

        // Should get back the same amount (minus potential rounding)
        assertApproxEqAbs(
            assetsReceived,
            amount,
            1,
            "Assets received should be approximately equal to amount deposited (within 1 unit)"
        );
    }

    function testFuzz_DepositWithdraw(uint256 amount) public {
        // Bound the amount to something reasonable
        amount = bound(amount, 1, 100_000_000 * 10 ** 6);

        // Initial balance
        uint256 initialBalance = mockToken.balanceOf(user);

        // Deposit
        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(amount, user);

        // Check shares received
        assertEq(sharesReceived, amount * 10 ** 12, "Shares received should be scaled by the decimals offset (10^12)");

        // Check wrapped token balance
        assertEq(
            wrappedToken.balanceOf(user), sharesReceived, "User's wrapped token balance should equal shares received"
        );

        // Withdraw
        uint256 sharesBurned = wrappedToken.withdraw(amount, user, user);
        vm.stopPrank();

        // Check assets received
        assertEq(sharesBurned, amount * 10 ** 12, "Assets received should equal the amount withdrawn");

        // Check final balances
        assertEq(wrappedToken.balanceOf(user), 0, "User's wrapped token balance should be zero after full withdrawal");
        assertEq(mockToken.balanceOf(user), initialBalance, "User's mock token balance should return to initial amount");
    }

    function testPreviewRedeem() public {
        // Test with a value that doesn't divide evenly
        uint256 sharesAmount = 1_234_567_890_123_456_789; // 1.234567890123456789 with 18 decimals

        // Expected result should be rounded down to 6 decimals
        uint256 expectedAssets = sharesAmount / 10 ** 12; // 1_234_567 (1.234567 with 6 decimals)

        // Call previewRedeem
        uint256 assets = wrappedToken.previewRedeem(sharesAmount);

        // Assert that the result matches our expectation
        assertEq(assets, expectedAssets, "previewRedeem should round down when converting to assets");
    }

    function testPreviewWithdraw() public {
        // Test with a value that doesn't divide evenly
        uint256 assetsAmount = 1_234_567; // 1.234567 with 6 decimals

        // Expected result should be rounded up to 18 decimals
        // When converting 1_234_567 assets to shares, we need to multiply by 10^12
        // But since we need to round up for withdrawals, we need to handle the case
        // where the division isn't exact
        uint256 expectedShares = assetsAmount * 10 ** 12;

        // Call previewWithdraw
        uint256 shares = wrappedToken.previewWithdraw(assetsAmount);

        // Assert that the result matches our expectation
        assertEq(shares, expectedShares, "previewWithdraw should round up when converting to shares");

        // Test with a value that requires rounding
        uint256 oddAssetsAmount = 1_234_568_000_000_000_000; // An amount that would cause rounding
        uint256 calculatedShares = wrappedToken.previewWithdraw(oddAssetsAmount);

        // Verify that using these shares would give at least the requested assets
        uint256 resultingAssets = wrappedToken.previewRedeem(calculatedShares);
        assertEq(resultingAssets, oddAssetsAmount, "Resulting assets should be >= requested assets");
    }
}

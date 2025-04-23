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

    function test_Redeem() public {
        uint256 depositAmount = 10 * 1e6;

        // First deposit
        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);

        // Then redeem
        uint256 userInitialBalance = mockToken.balanceOf(user);
        uint256 assetsReceived = wrappedToken.redeem(sharesReceived, user, user);
        vm.stopPrank();

        // Check user's wrapped token balance decreased
        assertEq(
            wrappedToken.balanceOf(user), 0, "User's wrapped token balance should be zero after redeeming all shares"
        );

        // Check user received mock tokens back
        assertEq(
            mockToken.balanceOf(user),
            userInitialBalance + assetsReceived,
            "User should receive back the correct amount of underlying tokens"
        );

        // Check that assets received match the original deposit (accounting for potential rounding)
        assertEq(
            assetsReceived,
            depositAmount,
            "Assets received should be approximately equal to amount deposited (within 1 unit)"
        );
    }

    function test_RedeemWithPreciseDecimals() public {
        // Record initial balance before any operations
        uint256 userInitialBalance = mockToken.balanceOf(user);

        // Deposit a round number
        uint256 depositAmount = 10 * 1e6; // 10 tokens with 6 decimals

        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);

        uint256 sharesToRedeem = sharesReceived / 3; // 3.333333333333333333

        // Record balances before redemption
        uint256 userInitialWrappedBalance = wrappedToken.balanceOf(user);
        uint256 userInitialTokenBalance = mockToken.balanceOf(user);

        // Redeem the precise amount
        uint256 assetsReceived = wrappedToken.redeem(sharesToRedeem, user, user);
        vm.stopPrank();

        // Check wrapped token balance decreased by the correct amount
        assertEq(
            wrappedToken.balanceOf(user),
            userInitialWrappedBalance - sharesToRedeem,
            "User's wrapped token balance should decrease by the redeemed shares"
        );

        // Check underlying token balance increased
        assertEq(
            mockToken.balanceOf(user),
            userInitialTokenBalance + assetsReceived,
            "User should receive the correct amount of underlying tokens"
        );

        // Verify the conversion was done correctly
        uint256 expectedAssets = sharesToRedeem * 1e6 / 1e18;
        assertEq(assetsReceived, expectedAssets, "Assets received should match the expected conversion");

        // Verify that the conversion from shares to assets handles decimals correctly
        // The expected assets should be approximately depositAmount / 3 (accounting for potential rounding)
        assertEq(
            assetsReceived,
            depositAmount / 3,
            "Assets received should be approximately equal to 1/3 of deposit (within 1 unit)"
        );

        // Verify that the sum of wrapped token supply and user's mock token balance
        // is less than or equal to the initial balance
        uint256 remainingWrappedValue = wrappedToken.balanceOf(user);
        uint256 currentMockBalance = mockToken.balanceOf(user);

        // Calculate the value of remaining wrapped tokens in terms of mock tokens
        uint256 remainingWrappedValueInMockTokens = wrappedToken.convertToAssets(remainingWrappedValue);

        // Calculate the total value the user has (current mock balance + equivalent value of wrapped tokens)
        uint256 totalUserValue = currentMockBalance + remainingWrappedValueInMockTokens;

        // Due to rounding down in the conversion, the total value should be at most 1 wei less than initial
        assertEq(
            totalUserValue,
            userInitialBalance - 1,
            "Total user value (mock tokens + wrapped value) should be 1 wei less than initial due to rounding"
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
        vm.assume(amount > 0 && amount <= 100_000_000 * 10 ** 6);

        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(amount, user);
        uint256 assetsReceived = wrappedToken.redeem(sharesReceived, user, user);
        vm.stopPrank();

        // Verify that the assets received are less than or equal to the amount deposited
        // This is important because in some cases there might be rounding down when converting
        // shares back to assets, but we should never get more assets than we put in
        assertLe(assetsReceived, amount, "Assets received should not exceed the amount deposited");

        // Should get back the same amount (minus potential rounding)
        assertEq(
            assetsReceived, amount, "Assets received should be approximately equal to amount deposited (within 1 unit)"
        );
    }
}

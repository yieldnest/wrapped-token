// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {WrappedToken} from "../src/WrappedToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000 * 10**18);
    }
}

contract WrappedTokenTest is Test {
    WrappedToken public wrappedToken;
    MockToken public mockToken;
    address public user = address(1);

    function setUp() public {
        mockToken = new MockToken("Mock Token", "MTK");
        wrappedToken = new WrappedToken(mockToken, "Wrapped Mock Token", "WMTK", 18);
        
        // Give user some tokens
        mockToken.transfer(user, 100 * 10**18);
        
        // Approve wrapped token to spend mock tokens
        vm.startPrank(user);
        mockToken.approve(address(wrappedToken), type(uint256).max);
        vm.stopPrank();
    }

    function test_Deposit() public {
        uint256 depositAmount = 10 * 10**18;
        uint256 userInitialBalance = mockToken.balanceOf(user);
        
        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Check user's mock token balance decreased
        assertEq(mockToken.balanceOf(user), userInitialBalance - depositAmount);
        
        // Check user received wrapped tokens
        assertEq(wrappedToken.balanceOf(user), sharesReceived);
        
        // Check wrapped token has the deposited tokens
        assertEq(mockToken.balanceOf(address(wrappedToken)), depositAmount);
    }

    function test_Withdraw() public {
        uint256 depositAmount = 10 * 10**18;
        
        // First deposit
        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(depositAmount, user);
        
        // Then withdraw
        uint256 userInitialBalance = mockToken.balanceOf(user);
        uint256 assetsReceived = wrappedToken.withdraw(depositAmount, user, user);
        vm.stopPrank();
        
        // Check user's wrapped token balance decreased
        assertEq(wrappedToken.balanceOf(user), sharesReceived - assetsReceived);
        
        // Check user received mock tokens back
        assertEq(mockToken.balanceOf(user), userInitialBalance + depositAmount);
    }

    function test_ConversionRates() public {
        uint256 depositAmount = 10 * 10**18;
        
        // Check conversion rates before any deposits
        assertEq(wrappedToken.convertToShares(depositAmount), depositAmount);
        assertEq(wrappedToken.convertToAssets(depositAmount), depositAmount);
        
        // Make a deposit
        vm.startPrank(user);
        wrappedToken.deposit(depositAmount, user);
        vm.stopPrank();
        
        // Conversion rates should still be 1:1
        assertEq(wrappedToken.convertToShares(depositAmount), depositAmount);
        assertEq(wrappedToken.convertToAssets(depositAmount), depositAmount);
    }

    function testFuzz_DepositWithdraw(uint256 amount) public {
        // Bound the amount to something reasonable
        amount = bound(amount, 1, 100 * 10**18);
        
        vm.startPrank(user);
        uint256 sharesReceived = wrappedToken.deposit(amount, user);
        uint256 assetsReceived = wrappedToken.redeem(sharesReceived, user, user);
        vm.stopPrank();
        
        // Should get back the same amount (minus potential rounding)
        assertApproxEqAbs(assetsReceived, amount, 1);
    }
}

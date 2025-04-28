// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {WrappedToken} from "./WrappedToken.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title GovernedWrappedToken
 * @dev An extension of WrappedToken that allows authorized allocators to transfer
 * underlying tokens out of the contract for management purposes.
 */
contract GovernedWrappedToken is WrappedToken {

    /**
     * @dev Error thrown when a zero address is provided where a valid address is required.
     */
    error ZeroAddress();

    /**
     * @dev Role for governors who can manage token allocations
     */
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /**
     * @dev Emitted when a governor transfers underlying tokens out of the contract.
     */
    event UnderlyingWithdrawn(address indexed allocator, address indexed recipient, uint256 amount);

    /**
     * @dev Transfers a specified amount of the underlying token to a recipient.
     * Can only be called by accounts with the governor role.
     * @param recipient The address that will receive the tokens
     * @param amount The amount of underlying tokens to transfer
     */
    function withdrawUnderlying(address recipient, uint256 amount) external onlyRole(GOVERNOR_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();

        // Transfer the tokens to the recipient
        SafeERC20.safeTransfer(IERC20(asset()), recipient, amount);

        emit UnderlyingWithdrawn(msg.sender, recipient, amount);
    }
}

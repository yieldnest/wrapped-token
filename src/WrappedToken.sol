// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract WrappedToken is Initializable, ERC20Upgradeable {
    struct TokenStorage {
        IERC20 underlying;
        uint8 decimals;
        uint8 decimalsOffset;
    }
    
    // keccak256(abi.encode(uint256(keccak256("WrappedToken.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TOKEN_STORAGE_LOCATION = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382b00;
    
    /**
     * @dev The underlying token couldn't be wrapped.
     */
    error ERC20InvalidUnderlying(address token);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function _getTokenStorage() private pure returns (TokenStorage storage ts) {
        bytes32 position = TOKEN_STORAGE_LOCATION;
        assembly {
            ts.slot := position
        }
    }

    function initialize(IERC20 underlyingToken, string memory name, string memory symbol, uint8 decimalsValue, uint8 decimalsOffset) public initializer {
        __ERC20_init(name, symbol);
        
        if (address(underlyingToken) == address(this)) {
            revert ERC20InvalidUnderlying(address(this));
        }
        
        TokenStorage storage ts = _getTokenStorage();
        ts.underlying = underlyingToken;
        ts.decimals = decimalsValue;
        ts.decimalsOffset = decimalsOffset;
    }

    /**
     * @dev See {ERC20-decimals}.
     */
    function decimals() public view virtual override returns (uint8) {
        TokenStorage storage ts = _getTokenStorage();
        return ts.decimals;
    }

    /**
     * @dev Returns the address of the underlying ERC-20 token that is being wrapped.
     */
    function underlying() public view returns (IERC20) {
        TokenStorage storage ts = _getTokenStorage();
        return ts.underlying;
    }

    /**
     * @dev Returns the decimals offset used for scaling deposits and withdrawals.
     */
    function decimalsOffset() public view returns (uint8) {
        TokenStorage storage ts = _getTokenStorage();
        return ts.decimalsOffset;
    }

    /**
     * @dev Converts an amount from underlying token to wrapped token based on the decimals offset.
     */
    function _toWrappedAmount(uint256 underlyingAmount) internal view returns (uint256) {
        TokenStorage storage ts = _getTokenStorage();
        return underlyingAmount * (10 ** ts.decimalsOffset);
    }

    /**
     * @dev Converts an amount from wrapped token to underlying token based on the decimals offset.
     */
    function _toUnderlyingAmount(uint256 wrappedAmount) internal view returns (uint256) {
        TokenStorage storage ts = _getTokenStorage();
        return wrappedAmount / (10 ** ts.decimalsOffset);
    }

    /**
     * @dev Allow a user to deposit underlying tokens and mint the corresponding number of wrapped tokens.
     */
    function depositFor(address account, uint256 value) public virtual returns (bool) {
        TokenStorage storage ts = _getTokenStorage();
        
        address sender = _msgSender();
        if (sender == address(this)) {
            revert ERC20InvalidSender(address(this));
        }
        if (account == address(this)) {
            revert ERC20InvalidReceiver(account);
        }
        
        SafeERC20.safeTransferFrom(ts.underlying, sender, address(this), value);
        uint256 wrappedAmount = _toWrappedAmount(value);
        _mint(account, wrappedAmount);
        return true;
    }

    /**
     * @dev Allow a user to burn a number of wrapped tokens and withdraw the corresponding number of underlying tokens.
     */
    function withdrawTo(address account, uint256 value) public virtual returns (bool) {
        TokenStorage storage ts = _getTokenStorage();
        
        if (account == address(this)) {
            revert ERC20InvalidReceiver(account);
        }
        
        _burn(_msgSender(), value);
        uint256 underlyingAmount = _toUnderlyingAmount(value);
        SafeERC20.safeTransfer(ts.underlying, account, underlyingAmount);
        return true;
    }

    /**
     * @dev Mint wrapped token to cover any underlyingTokens that would have been transferred by mistake or acquired from
     * rebasing mechanisms. Internal function that can be exposed with access control if desired.
     */
    function _recover(address account) internal virtual returns (uint256) {
        TokenStorage storage ts = _getTokenStorage();
        
        uint256 underlyingBalance = ts.underlying.balanceOf(address(this));
        uint256 expectedUnderlyingBalance = _toUnderlyingAmount(totalSupply());
        
        if (underlyingBalance > expectedUnderlyingBalance) {
            uint256 underlyingExcess = underlyingBalance - expectedUnderlyingBalance;
            uint256 wrappedExcess = _toWrappedAmount(underlyingExcess);
            _mint(account, wrappedExcess);
            return wrappedExcess;
        }
        
        return 0;
    }
}
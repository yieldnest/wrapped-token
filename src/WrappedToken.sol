// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

contract WrappedToken is Initializable, ERC4626Upgradeable {

    /**
     * @dev The underlying token couldn't be wrapped.
     */
    error ERC20InvalidUnderlying(address token);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20 underlyingToken,
        string memory name,
        string memory symbol,
        uint8 decimalsValue,
        uint8 tokenDecimalsOffset
    ) public initializer {
        if (address(underlyingToken) == address(this)) {
            revert ERC20InvalidUnderlying(address(this));
        }

        __ERC4626_init(underlyingToken);
        __ERC20_init(name, symbol);

        ERC4626Storage storage $ = getERC4626Storage();
        $._underlyingDecimals = decimalsValue;

        TokenStorage storage ts = _getTokenStorage();
        ts.decimalsOffset = tokenDecimalsOffset;
    }

    /**
     * @dev See {ERC20-decimals}.
     */
    function decimals() public view virtual override(ERC4626Upgradeable) returns (uint8) {
        return super.decimals();
    }

    /**
     * @dev Converts an amount from underlying token to wrapped token based on the decimals offset.
     */
    function _convertToShares(uint256 assets, Math.Rounding /* rounding */)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        TokenStorage storage ts = _getTokenStorage();
        return assets * (10 ** ts.decimalsOffset);
    }

    /**
     * @dev Converts an amount from wrapped token to underlying token based on the decimals offset.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        TokenStorage storage ts = _getTokenStorage();
        return Math.mulDiv(shares, 1, 10 ** ts.decimalsOffset, rounding);
    }

    /**
     * @dev Returns the decimals offset used for scaling deposits and withdrawals.
     */
    function _decimalsOffset() internal view override returns (uint8) {
        TokenStorage storage ts = _getTokenStorage();
        return ts.decimalsOffset;
    }

    /**
     * @dev Returns the decimals offset used for scaling deposits and withdrawals.
     * This is a public accessor for the internal _decimalsOffset function.
     */
    function decimalsOffset() public view returns (uint8) {
        return _decimalsOffset();
    }

    /// Storage ///

    struct TokenStorage {
        uint8 decimalsOffset;
    }

    // keccak256(abi.encode(uint256(keccak256("WrappedToken.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TokenStorageLocation = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382b00;

    function _getTokenStorage() internal pure returns (TokenStorage storage ts) {
        bytes32 position = TokenStorageLocation;
        assembly {
            ts.slot := position
        }
    }

    /// ERC4626 Storage ///

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC4626")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant ERC4626StorageLocation =
        0x0773e532dfede91f04b12a73d3d2acd361424f41f76b4fb79f090161e36b4e00;

    function getERC4626Storage() internal pure returns (ERC4626Storage storage $) {
        assembly {
            $.slot := ERC4626StorageLocation
        }
    }
}

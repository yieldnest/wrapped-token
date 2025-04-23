// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "src/interface/IWrappedToken.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/**
 * @title ERC4626Adapter
 * @dev Adapter contract that allows users to interact with an ERC4626 vault using the underlying token
 * of a WrappedToken that serves as the vault's asset.
 */
contract ERC4626Adapter is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // The ERC4626 vault this adapter interacts with
    IERC4626 public vault;

    // The wrapped token used as the vault's asset
    IWrappedToken public wrappedToken;

    // The underlying token of the wrapped token
    IERC20 public underlyingToken;

    /**
     * @dev Emitted when assets are deposited into the adapter
     */
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /**
     * @dev Emitted when assets are withdrawn from the adapter
     */
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /**
     * @dev Initializes the adapter with the vault and wrapped token
     * @param _vault The ERC4626 vault to interact with
     * @param _wrappedToken The wrapped token used as the vault's asset
     */
    function initialize(IERC4626 _vault, IWrappedToken _wrappedToken, string memory name, string memory symbol)
        public
        initializer
    {
        __ERC20_init(name, symbol);
        __ReentrancyGuard_init();

        // Verify that the wrapped token is the vault's asset
        require(address(_wrappedToken) == _vault.asset(), "Wrapped token must be vault's asset");

        vault = _vault;
        wrappedToken = _wrappedToken;
        underlyingToken = IERC20(_wrappedToken.asset());
    }

    /**
     * @dev Deposits underlying tokens and receives adapter shares
     * @param assets Amount of underlying tokens to deposit
     * @param receiver Address to receive the adapter shares
     * @return shares Amount of adapter shares minted
     */
    function deposit(uint256 assets, address receiver) public nonReentrant returns (uint256 shares) {
        // Calculate shares to mint based on assets
        shares = previewDeposit(assets);
        require(shares > 0, "Cannot deposit 0 shares");

        // Transfer underlying tokens from user to this contract
        underlyingToken.safeTransferFrom(msg.sender, address(this), assets);

        // Approve underlying tokens to wrapped token
        underlyingToken.forceApprove(address(wrappedToken), assets);

        // Deposit underlying into wrapped token
        uint256 wrappedShares = wrappedToken.deposit(assets, address(this));

        // Approve wrapped tokens to vault
        IERC20(address(wrappedToken)).forceApprove(address(vault), wrappedShares);

        // Deposit wrapped tokens into vault
        vault.deposit(wrappedShares, address(this));

        // Mint adapter shares to receiver
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    /**
     * @dev Withdraws underlying tokens by burning adapter shares
     * @param shares Amount of adapter shares to burn
     * @param receiver Address to receive the underlying tokens
     * @param owner Address that owns the adapter shares
     * @return assets Amount of underlying tokens withdrawn
     */
    function redeem(uint256 shares, address receiver, address owner) public nonReentrant returns (uint256 assets) {
        require(shares > 0, "Cannot redeem 0 shares");

        // If caller is not the owner, check allowance
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Calculate assets to withdraw
        assets = previewRedeem(shares);

        // Burn adapter shares
        _burn(owner, shares);

        // Calculate vault shares to redeem
        uint256 vaultShares = _convertAdapterSharesToVaultShares(shares);

        // Redeem wrapped tokens from vault
        uint256 wrappedAmount = vault.redeem(vaultShares, address(this), address(this));

        // Redeem underlying tokens from wrapped token
        uint256 underlyingAmount = wrappedToken.redeem(wrappedAmount, receiver, address(this));

        // Verify expected amount was received
        require(underlyingAmount >= assets, "Insufficient underlying tokens received");

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return assets;
    }

    /**
     * @dev Withdraws a specific amount of underlying tokens
     * @param assets Amount of underlying tokens to withdraw
     * @param receiver Address to receive the underlying tokens
     * @param owner Address that owns the adapter shares
     * @return shares Amount of adapter shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) public nonReentrant returns (uint256 shares) {
        require(assets > 0, "Cannot withdraw 0 assets");

        // Calculate shares to burn
        shares = previewWithdraw(assets);

        // If caller is not the owner, check allowance
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Burn adapter shares
        _burn(owner, shares);

        // Calculate vault shares to redeem
        uint256 vaultShares = _convertAdapterSharesToVaultShares(shares);

        // Withdraw wrapped tokens from vault
        uint256 wrappedAmount = vault.redeem(vaultShares, address(this), address(this));

        // Redeem underlying tokens from wrapped token
        uint256 underlyingAmount = wrappedToken.redeem(wrappedAmount, receiver, address(this));

        // Verify expected amount was received
        require(underlyingAmount >= assets, "Insufficient underlying tokens received");

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    /**
     * @dev Previews the amount of adapter shares that would be minted for a given deposit
     * @param assets Amount of underlying tokens to deposit
     * @return Amount of adapter shares that would be minted
     */
    function previewDeposit(uint256 assets) public view returns (uint256) {
        if (totalSupply() == 0) {
            return assets;
        }

        // Convert underlying to wrapped tokens
        uint256 wrappedAmount = wrappedToken.convertToShares(assets);

        // Convert wrapped tokens to vault shares
        uint256 vaultShares = vault.convertToShares(wrappedAmount);

        // Convert vault shares to adapter shares
        return _convertVaultSharesToAdapterShares(vaultShares);
    }

    /**
     * @dev Previews the amount of underlying tokens that would be withdrawn for a given redemption
     * @param shares Amount of adapter shares to redeem
     * @return Amount of underlying tokens that would be withdrawn
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }

        // Convert adapter shares to vault shares
        uint256 vaultShares = _convertAdapterSharesToVaultShares(shares);

        // Convert vault shares to wrapped tokens
        uint256 wrappedAmount = vault.convertToAssets(vaultShares);

        // Convert wrapped tokens to underlying tokens
        return wrappedToken.convertToAssets(wrappedAmount);
    }

    /**
     * @dev Previews the amount of adapter shares that would be burned for a given withdrawal
     * @param assets Amount of underlying tokens to withdraw
     * @return Amount of adapter shares that would be burned
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }

        // Convert underlying to wrapped tokens
        uint256 wrappedAmount = wrappedToken.convertToShares(assets);

        // Convert wrapped tokens to vault shares
        uint256 vaultShares = vault.convertToShares(wrappedAmount);

        // Convert vault shares to adapter shares
        return _convertVaultSharesToAdapterShares(vaultShares);
    }

    /**
     * @dev Converts adapter shares to vault shares
     * @param adapterShares Amount of adapter shares
     * @return Amount of vault shares
     */
    function _convertAdapterSharesToVaultShares(uint256 adapterShares) internal view returns (uint256) {
        uint256 totalVaultShares = IERC20(address(vault)).balanceOf(address(this));
        return Math.mulDiv(adapterShares, totalVaultShares, totalSupply(), Math.Rounding.Floor);
    }

    /**
     * @dev Converts vault shares to adapter shares
     * @param vaultShares Amount of vault shares
     * @return Amount of adapter shares
     */
    function _convertVaultSharesToAdapterShares(uint256 vaultShares) internal view returns (uint256) {
        uint256 totalVaultShares = IERC20(address(vault)).balanceOf(address(this));
        if (totalVaultShares == 0) {
            return vaultShares;
        }
        return Math.mulDiv(vaultShares, totalSupply(), totalVaultShares, Math.Rounding.Floor);
    }

    /**
     * @dev Returns the total assets managed by this adapter in terms of underlying tokens
     * @return Total underlying tokens
     */
    function totalAssets() public view returns (uint256) {
        uint256 vaultShares = IERC20(address(vault)).balanceOf(address(this));
        uint256 wrappedAmount = vault.convertToAssets(vaultShares);
        return wrappedToken.convertToAssets(wrappedAmount);
    }
}

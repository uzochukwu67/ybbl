/// Common strategy interface — IStrategy trait
/// Both EkuboLP and VesuLending implement this trait.
/// The Vault calls strategies through this common interface.
///
/// Design decision: `deposit` and `withdraw` take u256 amount in asset terms.
/// EkuboLP internally converts to dual-sided liquidity via deposit_ratio.
/// VesuLending passes through directly to modify_position.

use starknet::ContractAddress;

#[starknet::interface]
pub trait IStrategy<TContractState> {
    /// Deploy assets into the strategy's underlying protocol.
    /// amount: asset amount in wBTC wei (u256)
    fn deposit(ref self: TContractState, amount: u256);

    /// Withdraw assets from the strategy's underlying protocol.
    /// amount: asset amount in wBTC wei (u256) to withdraw
    fn withdraw(ref self: TContractState, amount: u256);

    /// Returns the total value of assets held by this strategy,
    /// denominated in the vault's underlying asset (wBTC).
    fn total_assets(self: @TContractState) -> u256;

    /// Returns the vault address that owns this strategy.
    fn vault(self: @TContractState) -> ContractAddress;
}

/// Extended interface for EkuboLP-specific operations.
/// Not part of the common IStrategy trait because these are protocol-specific.
#[starknet::interface]
pub trait IEkuboLPStrategyExt<TContractState> {
    /// Deposit dual-sided liquidity (BTC + USDC amounts).
    fn deposit_liquidity(ref self: TContractState, amount0: u256, amount1: u256);

    /// Withdraw a percentage of liquidity (ratio in WAD = 1e18 = 100%).
    fn withdraw_liquidity(
        ref self: TContractState, ratio_wad: u256, min_token0: u128, min_token1: u128,
    );

    /// Collect accumulated trading fees from the LP position.
    fn collect_fees(ref self: TContractState) -> (u128, u128);

    /// Set the tick bounds for the LP position (only when no active position).
    fn set_bounds(ref self: TContractState, lower_mag: u128, lower_sign: bool, upper_mag: u128, upper_sign: bool);

    /// Get the current deposit ratio (how much of each token is needed).
    fn get_deposit_ratio(self: @TContractState) -> (u256, u256);

    /// Get the underlying balance of both tokens.
    fn underlying_balance(self: @TContractState) -> (u256, u256);

    /// Get pending uncollected fees.
    fn pending_fees(self: @TContractState) -> (u256, u256);

    /// Get total liquidity in the position.
    fn total_liquidity(self: @TContractState) -> u128;

    /// Get the NFT token ID for the LP position.
    fn nft_id(self: @TContractState) -> u64;

    /// Owner-only: update manager address (breaks constructor dependency cycle).
    fn set_manager(ref self: TContractState, new_manager: ContractAddress);

    /// Owner-only: sweep retained token1 (USDC) to a destination address.
    /// Used to recover token1 that accumulates from Ekubo withdrawals
    /// (vault is wBTC-only so token1 cannot be deposited there).
    fn sweep_token1(ref self: TContractState, to: ContractAddress) -> u256;
}

/// Extended interface for VesuLending-specific operations.
#[starknet::interface]
pub trait IVesuLendingStrategyExt<TContractState> {
    /// Supply collateral to Vesu V2 pool.
    fn supply(ref self: TContractState, amount: u256);

    /// Withdraw collateral from Vesu V2 pool.
    fn withdraw_collateral(ref self: TContractState, amount: u256);

    /// Get the current APY estimate (in BPS, e.g., 350 = 3.5%).
    fn current_apy(self: @TContractState) -> u256;

    /// Owner-only: update manager address (breaks constructor dependency cycle).
    fn set_manager(ref self: TContractState, new_manager: ContractAddress);
}
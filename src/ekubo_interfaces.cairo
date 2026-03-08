/// Minimal Ekubo Positions interface for the YBBC launchpad.
/// Types extracted from the Ekubo protocol ABI.
use starknet::ContractAddress;

// ── Primitive: signed 128-bit integer ─────────────────────────────────────────
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct i129 {
    pub mag: u128,
    pub sign: bool, // true = negative
}

// ── Pool identification ────────────────────────────────────────────────────────
#[derive(Copy, Drop, Serde)]
pub struct PoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub tick_spacing: u128,
    pub extension: ContractAddress,
}

// ── Tick range for LP position ─────────────────────────────────────────────────
#[derive(Copy, Drop, Serde)]
pub struct Bounds {
    pub lower: i129,
    pub upper: i129,
}

// ── Return type of get_token_info ──────────────────────────────────────────────
#[derive(Copy, Drop, Serde)]
pub struct GetTokenInfoResult {
    pub liquidity: u128,
    pub amount0: u128,
    pub amount1: u128,
    pub fees0: u128,
    pub fees1: u128,
}

// ── Ekubo Core singleton interface ────────────────────────────────────────────
/// Mainnet: 0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b
#[starknet::interface]
pub trait IEkuboCore<TContractState> {
    /// Initialize a new pool with a starting price (encoded as a tick).
    /// Returns the pool's initial sqrt_ratio.
    fn initialize_pool(
        ref self: TContractState,
        pool_key: PoolKey,
        initial_tick: i129,
    ) -> u256;
}

// ── Ekubo Positions NFT interface ─────────────────────────────────────────────
/// Mainnet: 0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067
#[starknet::interface]
pub trait IEkuboPositions<TContractState> {
    /// Mint a new NFT position and deposit tokens.
    /// Returns (nft_id, liquidity_minted).
    fn mint_and_deposit(
        ref self: TContractState,
        pool_key: PoolKey,
        bounds: Bounds,
        min_liquidity: u128,
    ) -> (u64, u128);

    /// Mint + deposit + clear both token balances back to caller.
    /// Returns (nft_id, liquidity, amount0_cleared, amount1_cleared).
    /// Requires caller to approve Positions for both tokens before calling.
    /// This is the correct function for graduation: it calls transferFrom on our tokens.
    fn mint_and_deposit_and_clear_both(
        ref self: TContractState,
        pool_key: PoolKey,
        bounds: Bounds,
        min_liquidity: u128,
    ) -> (u64, u128, u256, u256);

    /// Add liquidity to an existing NFT position.
    fn deposit(
        ref self: TContractState,
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
        min_liquidity: u128,
    ) -> u128;

    /// Remove liquidity from a position.
    /// Returns (amount0, amount1) received.
    fn withdraw(
        ref self: TContractState,
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        min_token0: u128,
        min_token1: u128,
        collect_fees: bool,
    ) -> (u128, u128);

    /// Collect accrued trading fees for a position.
    /// Returns (fees0, fees1).
    fn collect_fees(
        ref self: TContractState,
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
    ) -> (u128, u128);

    /// Query token amounts and pending fees for a position.
    fn get_token_info(
        self: @TContractState,
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
    ) -> GetTokenInfoResult;
}

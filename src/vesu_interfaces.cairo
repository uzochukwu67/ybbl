/// Minimal Vesu V2 pool interface for the YBBC launchpad.
/// Vesu mainnet Singleton: 0x02545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef
use starknet::ContractAddress;

// ── Signed 257-bit integer (same representation Vesu expects) ─────────────────
#[derive(Copy, Drop, Serde)]
pub struct I257 {
    pub mag: u256,
    pub sign: bool, // true = negative
}

#[derive(Copy, Drop, Serde)]
pub enum AmountDenomination {
    Native,
    Assets,
}

#[derive(Copy, Drop, Serde)]
pub struct Amount {
    pub denomination: AmountDenomination,
    pub value: I257,
}

/// Parameters for modifying a collateral/debt position in Vesu.
#[derive(Copy, Drop, Serde)]
pub struct ModifyPositionParams {
    pub pool_id: felt252,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub collateral: Amount,
    pub debt: Amount,
    pub data: Span<felt252>,
}

/// Represents an on-chain position (simplified).
#[derive(Copy, Drop, Serde)]
pub struct Position {
    pub collateral_shares: u256,
    pub debt_shares: u256,
}

/// Vesu Singleton pool interface.
/// Only the functions needed by the YBBC launchpad are declared here.
#[starknet::interface]
pub trait IVesuSingleton<TContractState> {
    /// Supply collateral (positive collateral, zero debt).
    /// Returns (position, collateral_delta, debt_delta, bad_debt).
    fn modify_position(
        ref self: TContractState,
        params: ModifyPositionParams,
    ) -> (Position, Amount, Amount, u256);

    /// Query an existing position.
    fn position(
        self: @TContractState,
        pool_id: felt252,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
    ) -> (Position, Amount, Amount);
}

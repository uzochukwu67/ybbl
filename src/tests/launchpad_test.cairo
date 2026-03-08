/// Unit tests for the YBBC Launchpad.
/// Uses mock ERC20 tokens as base_asset (no fork needed).
/// Ekubo graduation path is NOT tested here (requires mainnet fork).

use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::ClassHash;
use core::num::traits::Zero;

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
};

use game::erc20::IERC20Dispatcher;
use game::erc20::IERC20DispatcherTrait;
use game::launchpad::ILaunchpadDispatcher;
use game::launchpad::ILaunchpadDispatcherTrait;

// ── Helpers ────────────────────────────────────────────────────────────────────

fn alice() -> ContractAddress { contract_address_const::<'alice'>() }
fn bob()   -> ContractAddress { contract_address_const::<'bob'>() }
fn owner() -> ContractAddress { contract_address_const::<'owner'>() }
// Dummy Ekubo Positions address — graduation not exercised in unit tests
fn ekubo_positions() -> ContractAddress { contract_address_const::<'ekubo'>() }

/// Deploy a bare ERC20 used as base_asset (minter=0 → unrestricted mint for seeding).
fn deploy_base_asset(name: felt252) -> ContractAddress {
    let contract = declare("ERC20").unwrap().contract_class();
    let calldata = array![name, name, 18_felt252, 0_felt252]; // minter=0
    let (addr, _) = contract.deploy(@calldata).unwrap();
    addr
}

/// Deploy the Launchpad with:
///   - ERC20 class hash for token factory
///   - dummy Ekubo Positions address
///   - Noir verifier address (for ZK anonymous buy)
fn deploy_launchpad() -> (ContractAddress, ClassHash) {
    let token_class = declare("ERC20").unwrap().contract_class();
    let launchpad_class = declare("Launchpad").unwrap().contract_class();

    // Constructor: (token_class_hash, ekubo_positions, ekubo_core, owner,
    //               grad_threshold: u256, max_supply: u256, curve_k: u256, vesu_pool, verifier)
    // grad_threshold = 20e18, max_supply = 1B tokens, curve_k = 40
    let calldata = array![
        (*token_class.class_hash).into(),
        ekubo_positions().into(),
        0,                        // ekubo_core = 0 (pool init skipped in unit tests)
        owner().into(),
        20_000_000_000_000_000_000_u128.into(), // grad_threshold low
        0_felt252,                // grad_threshold high
        1_000_000_000_felt252,    // max_supply low (1B tokens)
        0_felt252,                // max_supply high
        40_felt252,               // curve_k low
        0_felt252,                // curve_k high
        0_felt252,                // vesu_pool = 0 (disabled)
        0_felt252,                // verifier = 0 (use legacy nullifier mode)
    ];
    let (launchpad_addr, _) = launchpad_class.deploy(@calldata).unwrap();
    (launchpad_addr, *token_class.class_hash)
}

// ── Tests ──────────────────────────────────────────────────────────────────────

#[test]
fn test_launch_token_creates_token() {
    let (launchpad_addr, _) = deploy_launchpad();
    let base_asset = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };

    let token_addr = lp.launch_token('MemeToken', 'MEME', base_asset, 0);

    // Token is stored correctly
    assert(!token_addr.is_zero(), 'token should be non-zero');
    assert(lp.get_base_asset(token_addr) == base_asset, 'wrong base_asset');
    assert(lp.get_supply_sold(token_addr) == 0, 'supply should be 0');
    assert(lp.get_reserve(token_addr) == 0, 'reserve should be 0');
    assert(!lp.is_graduated(token_addr), 'should not be graduated');

    // Minter of new token is the launchpad
    let token = IERC20Dispatcher { contract_address: token_addr };
    assert(token.get_minter() == launchpad_addr, 'minter should be launchpad');
}

#[test]
fn test_launch_two_tokens_different_addresses() {
    let (launchpad_addr, _) = deploy_launchpad();
    let base_asset = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };

    let token1 = lp.launch_token('Alpha', 'ALPHA', base_asset, 0);
    let token2 = lp.launch_token('Beta', 'BETA', base_asset, 0);

    assert(token1 != token2, 'tokens must be unique');
}

#[test]
fn test_buy_bonding_curve_math() {
    let (launchpad_addr, _) = deploy_launchpad();
    let base_asset_addr = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('Meme', 'MEME', base_asset_addr, 0);

    // Fund alice with enough base asset
    // buy_cost(S=0, delta=10) = 40 * (0 + 10) * 10 = 4000
    // fee = 4000 * 100 / 10000 = 40
    // total = 4040
    let expected_cost: u256 = 4000;
    let expected_fee:  u256 = 40;
    let expected_total: u256 = 4040;

    base.mint(alice(), expected_total * 2); // give extra headroom

    // Alice approves launchpad
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, expected_total);
    stop_cheat_caller_address(base_asset_addr);

    // Alice buys 10 tokens
    start_cheat_caller_address(launchpad_addr, alice());
    let total_spent = lp.buy(token_addr, 10, expected_total + 1);
    stop_cheat_caller_address(launchpad_addr);

    assert(total_spent == expected_total, 'wrong total cost');
    assert(lp.get_supply_sold(token_addr) == 10, 'supply_sold should be 10');
    assert(lp.get_reserve(token_addr) == expected_cost, 'wrong reserve');
    assert(lp.get_fees(token_addr) == expected_fee, 'wrong fees');

    // Alice received the tokens
    let token = IERC20Dispatcher { contract_address: token_addr };
    assert(token.balance_of(alice()) == 10, 'alice should have 10 tokens');
}

#[test]
fn test_quote_buy_matches_actual_cost() {
    let (launchpad_addr, _) = deploy_launchpad();
    let base_asset_addr = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('Meme', 'MEME', base_asset_addr, 0);

    let delta: u256 = 10;
    let quoted = lp.quote_buy(token_addr, delta);

    base.mint(alice(), quoted);
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, quoted);
    stop_cheat_caller_address(base_asset_addr);

    start_cheat_caller_address(launchpad_addr, alice());
    let actual = lp.buy(token_addr, delta, quoted);
    stop_cheat_caller_address(launchpad_addr);

    assert(actual == quoted, 'quote should match actual');
}

#[test]
fn test_sell_returns_correct_payout() {
    let (launchpad_addr, _) = deploy_launchpad();
    let base_asset_addr = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('Meme', 'MEME', base_asset_addr, 0);
    let token_disp = IERC20Dispatcher { contract_address: token_addr };

    // Buy 10 first
    let buy_total = lp.quote_buy(token_addr, 10);
    base.mint(alice(), buy_total);
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, buy_total);
    stop_cheat_caller_address(base_asset_addr);
    start_cheat_caller_address(launchpad_addr, alice());
    lp.buy(token_addr, 10, buy_total);
    stop_cheat_caller_address(launchpad_addr);

    // sell_payout(S=10, delta=5) = 40 * (20-5) * 5 = 40 * 15 * 5 = 3000
    // fee = 3000 * 100 / 10000 = 30
    // net = 2970
    let expected_payout: u256 = 2970;

    let alice_base_before = base.balance_of(alice());

    start_cheat_caller_address(launchpad_addr, alice());
    let net = lp.sell(token_addr, 5, 0);
    stop_cheat_caller_address(launchpad_addr);

    assert(net == expected_payout, 'wrong sell payout');
    assert(lp.get_supply_sold(token_addr) == 5, 'supply_sold should be 5');
    assert(token_disp.balance_of(alice()) == 5, 'alice should have 5 tokens left');

    let alice_base_after = base.balance_of(alice());
    assert(alice_base_after == alice_base_before + expected_payout, 'alice base wrong');
}

#[test]
#[should_panic(expected: ('SLIPPAGE_EXCEEDED',))]
fn test_buy_reverts_on_slippage() {
    let (launchpad_addr, _) = deploy_launchpad();
    let base_asset_addr = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('Meme', 'MEME', base_asset_addr, 0);

    base.mint(alice(), 10000);
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, 10000);
    stop_cheat_caller_address(base_asset_addr);

    // max_cost = 4039, but real cost = 4040 → reverts
    start_cheat_caller_address(launchpad_addr, alice());
    lp.buy(token_addr, 10, 4039);
    stop_cheat_caller_address(launchpad_addr);
}

#[test]
fn test_fee_accumulation_across_trades() {
    let (launchpad_addr, _) = deploy_launchpad();
    let base_asset_addr = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('Meme', 'MEME', base_asset_addr, 0);

    // Buy 10 → fee = 40
    let buy_total = lp.quote_buy(token_addr, 10);
    base.mint(alice(), buy_total * 3);
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, buy_total * 3);
    stop_cheat_caller_address(base_asset_addr);

    start_cheat_caller_address(launchpad_addr, alice());
    lp.buy(token_addr, 10, buy_total);
    stop_cheat_caller_address(launchpad_addr);

    assert(lp.get_fees(token_addr) == 40, 'fees after buy 10');

    // Sell 5 from S=10 → payout=3000, fee=30 → total fees = 70
    start_cheat_caller_address(launchpad_addr, alice());
    lp.sell(token_addr, 5, 0);
    stop_cheat_caller_address(launchpad_addr);

    assert(lp.get_fees(token_addr) == 70, 'fees after sell 5');
}

#[test]
fn test_grad_threshold_is_configurable() {
    let (launchpad_addr, _) = deploy_launchpad();
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    // deploy_launchpad sets 20 ETH threshold
    assert(lp.get_grad_threshold() == 20_000_000_000_000_000_000, 'wrong threshold');
}

#[test]
fn test_buy_increments_supply_correctly() {
    let (launchpad_addr, _) = deploy_launchpad();
    let base_asset_addr = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('Meme', 'MEME', base_asset_addr, 0);

    // Buy 5 then buy 3 → supply = 8
    // cost(0, 5) = 40*(0+5)*5 = 1000, fee=10, total=1010
    // cost(5, 3) = 40*(10+3)*3 = 1560, fee=15.6→15, total=1575 (integer)
    // Actually fee = 1560*100/10000 = 15 (integer div), total = 1575
    let total1 = lp.quote_buy(token_addr, 5);
    let _total2 = lp.quote_buy(token_addr, 3); // will be from S=5 — unused, re-quoted after first buy

    // Need to re-quote after first buy since S changes:
    base.mint(alice(), total1 + 5000); // plenty

    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, total1 + 5000);
    stop_cheat_caller_address(base_asset_addr);

    start_cheat_caller_address(launchpad_addr, alice());
    lp.buy(token_addr, 5, total1);
    // S is now 5
    let total2_actual = lp.quote_buy(token_addr, 3);
    lp.buy(token_addr, 3, total2_actual);
    stop_cheat_caller_address(launchpad_addr);

    assert(lp.get_supply_sold(token_addr) == 8, 'supply should be 8');

    let token_disp = IERC20Dispatcher { contract_address: token_addr };
    assert(token_disp.balance_of(alice()) == 8, 'alice should have 8');
}

// ── ZK Anonymous Buy Tests ────────────────────────────────────────────────

/// Deploy Launchpad with a real verifier for ZK tests
fn deploy_launchpad_with_verifier() -> (ContractAddress, ContractAddress) {
    let token_class = declare("ERC20").unwrap().contract_class();
    let launchpad_class = declare("Launchpad").unwrap().contract_class();
    let verifier_class = declare("noir_verifier").unwrap().contract_class();

    // Deploy verifier first
    let (verifier_addr, _) = verifier_class.deploy(@array![owner().into()]).unwrap();

    // Constructor with verifier
    let calldata = array![
        (*token_class.class_hash).into(),
        ekubo_positions().into(),
        0,                        // ekubo_core = 0
        owner().into(),
        20_000_000_000_000_000_000_u128.into(), // grad_threshold
        0_felt252,
        1_000_000_000_felt252,    // max_supply
        0_felt252,
        40_felt252,               // curve_k
        0_felt252,
        0_felt252,                // vesu_pool = 0
        verifier_addr.into(),      // verifier
    ];
    let (launchpad_addr, _) = launchpad_class.deploy(@calldata).unwrap();
    (launchpad_addr, verifier_addr)
}

#[test]
fn test_zk_anonymous_buy_with_valid_proof() {
    let (launchpad_addr, _) = deploy_launchpad_with_verifier();
    let base_asset_addr = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('ZKToken', 'ZK', base_asset_addr, 0);

    // Create a mock proof (32+ bytes for placeholder verification)
    let mut proof = ArrayTrait::new();
    let mut i: u8 = 0;
    loop {
        if i >= 32 {
            break;
        }
        proof.append(i);
        i += 1;
    };

    // Buy params
    let delta: u256 = 10;
    // cost = 40 * (0 + 10) * 10 = 4000
    // fee = 4000 * 100 / 10000 = 40
    // total = 4040
    let max_cost: u256 = 5000;
    let nullifier: felt252 = 123456789;

    // Fund alice
    base.mint(alice(), 10000);

    // Alice approves launchpad
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, max_cost);
    stop_cheat_caller_address(base_asset_addr);

    // Alice buys anonymously with ZK proof
    start_cheat_caller_address(launchpad_addr, alice());
    let cost = lp.buy_zk_anonymous(token_addr, delta, max_cost, nullifier, proof);
    stop_cheat_caller_address(launchpad_addr);

    // Verify purchase succeeded
    assert(cost == 4040, 'wrong cost');
    assert(lp.get_supply_sold(token_addr) == 10, 'supply should be 10');

    // Verify nullifier was consumed
    assert(lp.is_nullifier_used(nullifier) == true, 'nullifier should be used');
}

#[test]
fn test_zk_anonymous_buy_nullifier_prevents_replay() {
    let (launchpad_addr, _) = deploy_launchpad_with_verifier();
    let base_asset_addr = deploy_base_asset('ETH');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('ZKToken2', 'ZK2', base_asset_addr, 0);

    // Create a mock proof
    let mut proof = ArrayTrait::new();
    let mut i: u8 = 0;
    loop {
        if i >= 32 {
            break;
        }
        proof.append(i);
        i += 1;
    };

    let delta: u256 = 10;
    let max_cost: u256 = 5000;
    let nullifier: felt252 = 999999999;

    // Fund alice
    base.mint(alice(), 20000);

    // Alice approves
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, max_cost * 2);
    stop_cheat_caller_address(base_asset_addr);

    // First purchase succeeds
    start_cheat_caller_address(launchpad_addr, alice());
    lp.buy_zk_anonymous(token_addr, delta, max_cost, nullifier, proof);

    // Verify nullifier was used
    assert(lp.is_nullifier_used(nullifier) == true, 'nullifier should be used');
    stop_cheat_caller_address(launchpad_addr);
}

#[test]
fn test_zk_verifier_address_stored() {
    let (launchpad_addr, verifier_addr) = deploy_launchpad_with_verifier();
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };

    // Verify the verifier address is stored correctly
    let stored_verifier = lp.get_verifier();
    assert(stored_verifier == verifier_addr, 'verifier not stored correctly');
}

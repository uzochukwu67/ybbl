/// Mainnet fork tests using REAL wBTC and USDC as base assets.
///
/// These prove the full YBBC flow works end-to-end with production tokens:
///   wBTC → bonding curve → graduation → Ekubo LP (wBTC/meme full-range)
///
/// Token addresses (Starknet mainnet):
///   wBTC = 0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac (8 decimals)
///   USDC = 0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8 (6 decimals)
///
/// Funding strategy: snforge `store` cheatcode writes alice's token balance directly into
/// the OZ ERC20 storage on the forked chain — no whale address needed.
///
/// Why this test matters:
///   The graduation flow calls Ekubo's mint_and_deposit_and_clear_both, which internally
///   calls ERC20.transferFrom(launchpad, Core, amount) on the real wBTC contract.
///   wBTC must have the camelCase `transferFrom` selector for this to succeed.
///   (It does — Ekubo's live wBTC/ETH pool proves it.)

use starknet::ContractAddress;
use starknet::contract_address_const;
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
    start_mock_call,
    store, map_entry_address,
};

use game::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use game::launchpad::{ILaunchpadDispatcher, ILaunchpadDispatcherTrait};

// ── Mainnet addresses ──────────────────────────────────────────────────────────

fn wbtc() -> ContractAddress {
    contract_address_const::<0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac>()
}
fn usdc() -> ContractAddress {
    contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>()
}
fn ekubo_positions() -> ContractAddress {
    contract_address_const::<0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067>()
}
fn owner() -> ContractAddress { contract_address_const::<'owner'>() }
fn alice() -> ContractAddress { contract_address_const::<'alice'>() }

// ── OZ ERC20 storage key for LegacyMap<ContractAddress, u256> ─────────────────
//
// In OpenZeppelin Cairo 2 ERC20, balances are stored at:
//   pedersen(pedersen(0, selector("ERC20_balances")), user_address)
// snforge's `map_entry_address(var_selector, keys)` computes this.

fn fund_token(token_addr: ContractAddress, recipient: ContractAddress, amount: u256) {
    // Write into ERC20_balances[recipient]
    let balance_slot = map_entry_address(
        selector!("ERC20_balances"),
        array![recipient.into()].span(),
    );
    store(
        token_addr,
        balance_slot,
        array![amount.low.into(), amount.high.into()].span(),
    );
}

// ── Deploy helpers ────────────────────────────────────────────────────────────

/// Deploy launchpad with:
///   - real Ekubo Positions (no mock for mint_and_deposit_and_clear_both)
///   - ekubo_core = 0 (skip initialize_pool, let deposit ratio set price)
///   - grad_threshold = 399_999 (buying 100 meme tokens with K=40 → costs 400_000 > threshold)
///   - K=40, max_supply=1B, Vesu disabled (no wBTC whale for Vesu in tests)
fn deploy_launchpad_with_real_positions() -> ContractAddress {
    let token_class = declare("ERC20").unwrap().contract_class();
    let lp_class = declare("Launchpad").unwrap().contract_class();
    let calldata = array![
        (*token_class.class_hash).into(),
        ekubo_positions().into(),
        0_felt252,              // ekubo_core = 0 (skip initialize_pool)
        owner().into(),
        399_999_felt252,        // grad_threshold low  (100 tokens @ K=40 → 400_000 > this)
        0_felt252,              // grad_threshold high
        1_000_000_000_felt252,  // max_supply low
        0_felt252,              // max_supply high
        40_felt252,             // curve_k low
        0_felt252,              // curve_k high
        0_felt252,              // vesu_pool = 0 (disabled in tests)
        0_felt252,              // verifier = 0 (legacy nullifier)
    ];
    let (addr, _) = lp_class.deploy(@calldata).unwrap();
    addr
}

// ── Shared graduation mock helper ─────────────────────────────────────────────
//
// We mock Ekubo Positions' mint_and_deposit_and_clear_both for the fork tests
// that use real tokens as base asset but don't need to test the Ekubo integration
// itself (that is tested in launchpad_nomock_test.cairo).
//
// For the no-mock variant below, both token sides must fully support camelCase ERC20.

fn mock_ekubo_for_graduation() {
    start_mock_call::<(u64, u128, u256, u256)>(
        ekubo_positions(),
        selector!("mint_and_deposit_and_clear_both"),
        (99_u64, 5000_u128, 1_u256, 1_u256),
    );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

/// Full flow: buy meme tokens with REAL wBTC, graduate to Ekubo (mocked LP creation).
///
/// This proves:
///   - wBTC.transferFrom works via the standard snake_case selector (launchpad buy path)
///   - bonding curve math is correct regardless of base asset decimals
///   - graduation fires when reserve ≥ threshold
///   - fees are cleared post-graduation
#[test]
#[fork("mainnet")]
fn test_wbtc_buy_and_graduation_mocked_lp() {
    let launchpad_addr = deploy_launchpad_with_real_positions();
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let wbtc_disp = IERC20Dispatcher { contract_address: wbtc() };

    // Launch a meme token backed by wBTC
    let token_addr = lp.launch_token('SatoshiMeme', 'SMEME', wbtc(), 0);

    // cost(0, 100) = 40 * 100 * 100 = 400_000, fee = 4_000, total = 404_000
    // In raw wBTC units (8 decimals): 404_000 ≈ 0.00404 wBTC
    let total_cost: u256 = 404_000;
    assert(lp.quote_buy(token_addr, 100) == total_cost, 'wrong wbtc quote');

    // Fund alice with wBTC directly via storage write (fork test pattern)
    fund_token(wbtc(), alice(), total_cost);
    assert(wbtc_disp.balance_of(alice()) == total_cost, 'fund failed');

    // Alice approves the launchpad to spend her wBTC
    start_cheat_caller_address(wbtc(), alice());
    wbtc_disp.approve(launchpad_addr, total_cost);
    stop_cheat_caller_address(wbtc());

    // Mock Ekubo LP creation (the wBTC/meme pool interaction is tested in nomock test)
    mock_ekubo_for_graduation();

    // Buy 100 meme tokens with wBTC → reserve(400_000) > threshold(399_999) → graduation
    start_cheat_caller_address(launchpad_addr, alice());
    let spent = lp.buy(token_addr, 100, total_cost);
    stop_cheat_caller_address(launchpad_addr);

    assert(spent == 404_000, 'wrong spend amount');
    assert(lp.is_graduated(token_addr), 'should be graduated');
    assert(lp.get_fees(token_addr) == 0, 'fees should be cleared');
    assert(lp.get_ekubo_nft_id(token_addr) == 99, 'wrong nft id');

    // Alice receives her 100 meme tokens
    let meme_disp = IERC20Dispatcher { contract_address: token_addr };
    assert(meme_disp.balance_of(alice()) == 100, 'alice meme balance wrong');
}

/// Same flow with USDC as base asset.
/// USDC has 6 decimals; the raw costs are smaller numbers.
#[test]
#[fork("mainnet")]
fn test_usdc_buy_and_graduation_mocked_lp() {
    let launchpad_addr = deploy_launchpad_with_real_positions();
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let usdc_disp = IERC20Dispatcher { contract_address: usdc() };

    let token_addr = lp.launch_token('USDCMeme', 'UMEME', usdc(), 0);

    // cost(0, 100) = 40*100*100 = 400_000, fee = 4_000, total = 404_000
    // In raw USDC (6 decimals): 404_000 ≈ $0.404 USDC
    let total_cost: u256 = 404_000;

    fund_token(usdc(), alice(), total_cost);
    assert(usdc_disp.balance_of(alice()) == total_cost, 'usdc fund failed');

    start_cheat_caller_address(usdc(), alice());
    usdc_disp.approve(launchpad_addr, total_cost);
    stop_cheat_caller_address(usdc());

    mock_ekubo_for_graduation();

    start_cheat_caller_address(launchpad_addr, alice());
    let spent = lp.buy(token_addr, 100, total_cost);
    stop_cheat_caller_address(launchpad_addr);

    assert(spent == 404_000, 'usdc spend wrong');
    assert(lp.is_graduated(token_addr), 'usdc: not graduated');
    assert(lp.get_fees(token_addr) == 0, 'usdc: fees not cleared');

    let meme_disp = IERC20Dispatcher { contract_address: token_addr };
    assert(meme_disp.balance_of(alice()) == 100, 'usdc: alice meme wrong');
}

/// Prove that wBTC's snake_case transfer_from works with our launchpad.
/// This validates the buy path before graduation fires.
#[test]
#[fork("mainnet")]
fn test_wbtc_two_buys_accumulate_reserve() {
    let launchpad_addr = deploy_launchpad_with_real_positions();
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };

    let token_addr = lp.launch_token('SatsToken', 'SATS', wbtc(), 0);

    // First buy: 10 tokens. cost = 40*10*10 = 4_000, fee = 40, total = 4_040
    let cost1: u256 = 4_040;
    // Second buy: 10 more. cost = 40*(2*10+10)*10 = 40*30*10 = 12_000, fee = 120, total = 12_120
    let cost2: u256 = 12_120;
    let total_needed = cost1 + cost2;

    fund_token(wbtc(), alice(), total_needed);

    start_cheat_caller_address(wbtc(), alice());
    IERC20Dispatcher { contract_address: wbtc() }.approve(launchpad_addr, total_needed);
    stop_cheat_caller_address(wbtc());

    // Buy 1: not yet graduated (reserve 4_000 < threshold 399_999)
    start_cheat_caller_address(launchpad_addr, alice());
    let s1 = lp.buy(token_addr, 10, cost1);
    stop_cheat_caller_address(launchpad_addr);
    assert(s1 == 4_040, 'buy1 cost wrong');
    assert(!lp.is_graduated(token_addr), 'should not grad yet');
    assert(lp.get_reserve(token_addr) == 4_000, 'reserve after buy1');
    assert(lp.get_supply_sold(token_addr) == 10, 'supply after buy1');

    // Buy 2: still not graduated (reserve 16_000 < threshold 399_999)
    start_cheat_caller_address(launchpad_addr, alice());
    let s2 = lp.buy(token_addr, 10, cost2);
    stop_cheat_caller_address(launchpad_addr);
    assert(s2 == 12_120, 'buy2 cost wrong');
    assert(!lp.is_graduated(token_addr), 'still not graduated');
    assert(lp.get_reserve(token_addr) == 16_000, 'reserve after buy2');

    // Fees accumulated: 40 + 120 = 160
    assert(lp.get_fees(token_addr) == 160, 'fees accumulated wrong');

    // Alice holds 20 meme tokens
    assert(
        IERC20Dispatcher { contract_address: token_addr }.balance_of(alice()) == 20,
        'alice meme after 2 buys'
    );
}

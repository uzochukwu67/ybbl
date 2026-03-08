/// Mainnet fork tests for YBBC Launchpad graduation.
///
/// Strategy:
///   - Use OUR OWN ERC20 as base asset (freely mintable — no whale needed)
///   - Mock Ekubo Core::initialize_pool (address not verified yet)
///   - Mock Ekubo Positions::mint_and_deposit (returns fake NFT id=42)
///   - Tests verify ALL graduation state transitions on real mainnet fork state
///   - When the real Ekubo Core address is confirmed, replace mock with real call
///
/// Mainnet Ekubo Positions: 0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067

use starknet::ContractAddress;
use starknet::contract_address_const;

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
    start_mock_call, stop_mock_call,
};

use game::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use game::launchpad::{ILaunchpadDispatcher, ILaunchpadDispatcherTrait};

// ── Known mainnet addresses ───────────────────────────────────────────────────
fn ekubo_positions_mainnet() -> ContractAddress {
    contract_address_const::<0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067>()
}
/// Using a placeholder Core address — mocked below so real address doesn't matter.
fn ekubo_core_placeholder() -> ContractAddress {
    contract_address_const::<0x01>() // dummy — real calls are mocked
}
fn owner() -> ContractAddress { contract_address_const::<'owner'>() }
fn alice() -> ContractAddress { contract_address_const::<'alice'>() }

// ── Helpers ────────────────────────────────────────────────────────────────────

fn deploy_base_asset(name: felt252) -> ContractAddress {
    let contract = declare("ERC20").unwrap().contract_class();
    let calldata = array![name, name, 18_felt252, 0_felt252]; // minter=0 → free mint
    let (addr, _) = contract.deploy(@calldata).unwrap();
    addr
}

/// Deploy Launchpad with:
///   - threshold = 100 wei (tiny — 2 tokens triggers graduation)
///   - Real Ekubo Positions (0x02e0af…)
///   - Placeholder Core (real calls mocked)
///   - Vesu disabled
fn deploy_fork_launchpad() -> ContractAddress {
    let token_class = declare("ERC20").unwrap().contract_class();
    let lp_class = declare("Launchpad").unwrap().contract_class();
    let calldata = array![
        (*token_class.class_hash).into(),
        ekubo_positions_mainnet().into(),
        ekubo_core_placeholder().into(),
        owner().into(),
        100_felt252,          // grad_threshold low  (100 wei)
        0_felt252,            // grad_threshold high
        1_000_000_000_felt252,// max_supply low (1B)
        0_felt252,            // max_supply high
        40_felt252,           // curve_k low
        0_felt252,            // curve_k high
        0_felt252,            // vesu_pool = disabled
        0_felt252,            // verifier = 0 (legacy nullifier mode)
    ];
    let (addr, _) = lp_class.deploy(@calldata).unwrap();
    addr
}

/// Mock Ekubo Positions::mint_and_deposit_and_clear_both → (nft_id=42, liq=1000, a0=1, a1=1).
fn mock_ekubo_mint_and_deposit() {
    // returns (u64, u128, u256, u256) serialized as [42, 1000, 1, 0, 1, 0]
    start_mock_call::<(u64, u128, u256, u256)>(
        ekubo_positions_mainnet(),
        selector!("mint_and_deposit_and_clear_both"),
        (42_u64, 1000_u128, 1_u256, 1_u256),
    );
}

/// Mock Ekubo Core::initialize_pool to return sqrt_ratio=1 (success).
fn mock_ekubo_initialize_pool() {
    // initialize_pool returns u256 → serialized as [1_felt252, 0_felt252]
    start_mock_call::<u256>(
        ekubo_core_placeholder(),
        selector!("initialize_pool"),
        1_u256,
    );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

/// Graduation test on mainnet fork.
///
/// Flow:
///   1. Deploy base_asset (our own ERC20, free to mint)
///   2. Deploy Launchpad with tiny threshold (100) + mocked Ekubo
///   3. Launch a meme token
///   4. Alice buys 2 tokens:
///      cost(0,2) = 40*(0+2)*2 = 160, fee = 1, total = 161
///      reserve = 160 ≥ threshold(100) → auto-graduation triggers
///   5. Graduation mocks:
///      - Core::initialize_pool → mocked (pool init)
///      - Positions::mint_and_deposit → mocked → returns nft_id=42
///   6. Assert: is_graduated=true, ekubo_nft_id=42, fees=0
#[test]
#[fork("mainnet")]
fn test_fork_graduation_creates_ekubo_lp() {
    mock_ekubo_initialize_pool();
    mock_ekubo_mint_and_deposit();

    let launchpad_addr = deploy_fork_launchpad();
    let base_asset_addr = deploy_base_asset('BASE');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('MemeForked', 'MFORK', base_asset_addr, 0);

    // cost(0,2)=160, fee=160*100/10000=1, total=161
    let total_cost = lp.quote_buy(token_addr, 2);
    assert(total_cost == 161, 'wrong quote');

    base.mint(alice(), total_cost);
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, total_cost);
    stop_cheat_caller_address(base_asset_addr);

    // Buy 2 → auto-graduates (reserve=160 ≥ 100)
    start_cheat_caller_address(launchpad_addr, alice());
    let spent = lp.buy(token_addr, 2, total_cost);
    stop_cheat_caller_address(launchpad_addr);

    assert(spent == 161, 'wrong amount spent');

    // Verify graduation state
    assert(lp.is_graduated(token_addr), 'should be graduated');
    assert(lp.get_ekubo_nft_id(token_addr) == 42, 'nft_id should be 42');
    assert(lp.get_fees(token_addr) == 0, 'fees 0 after grad');

    // Alice received the launched tokens
    let token_disp = IERC20Dispatcher { contract_address: token_addr };
    assert(token_disp.balance_of(alice()) == 2, 'alice should have 2');

    stop_mock_call(ekubo_positions_mainnet(), selector!("mint_and_deposit_and_clear_both"));
    stop_mock_call(ekubo_core_placeholder(), selector!("initialize_pool"));
}

/// Two-buy graduation test: first buy doesn't graduate, second does.
/// Also tests that the reserve math is correct across multiple buys.
#[test]
#[fork("mainnet")]
fn test_fork_two_buys_then_graduation() {
    mock_ekubo_initialize_pool();
    mock_ekubo_mint_and_deposit();

    let launchpad_addr = deploy_fork_launchpad();
    let base_asset_addr = deploy_base_asset('BASE2');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('ManualGrad', 'MGRAD', base_asset_addr, 0);

    // Buy 1 token: cost(0,1)=40, fee=0 (40*100/10000=0), total=40
    let total1 = lp.quote_buy(token_addr, 1);
    assert(total1 == 40, 'wrong first quote');
    // reserve(40) < threshold(100) → no graduation

    // Second buy: cost(1,2) = 40*(2+2)*2 = 320, fee=3, total=323
    // After both: reserve = 40+320 = 360 ≥ 100 → graduates on second buy
    let total2_estimate: u256 = 323; // pre-calculated
    let total_needed = total1 + total2_estimate + 10; // small buffer

    base.mint(alice(), total_needed);
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, total_needed);
    stop_cheat_caller_address(base_asset_addr);

    // First buy — no graduation
    start_cheat_caller_address(launchpad_addr, alice());
    lp.buy(token_addr, 1, total1);
    stop_cheat_caller_address(launchpad_addr);

    assert(!lp.is_graduated(token_addr), 'not graduated yet');
    assert(lp.get_reserve(token_addr) == 40, 'reserve=40 after 1st buy');
    assert(lp.get_supply_sold(token_addr) == 1, 'supply=1');

    // Second buy — triggers graduation
    let total2 = lp.quote_buy(token_addr, 2);
    assert(total2 == 323, 'wrong 2nd quote');

    start_cheat_caller_address(launchpad_addr, alice());
    lp.buy(token_addr, 2, total2);
    stop_cheat_caller_address(launchpad_addr);

    assert(lp.is_graduated(token_addr), 'should graduate 2nd buy');
    assert(lp.get_ekubo_nft_id(token_addr) == 42, 'nft_id=42 from mock');
    assert(lp.get_supply_sold(token_addr) == 3, 'supply=3 after all buys');

    stop_mock_call(ekubo_positions_mainnet(), selector!("mint_and_deposit_and_clear_both"));
    stop_mock_call(ekubo_core_placeholder(), selector!("initialize_pool"));
}

/// Verify collect_lp_fees works on a graduated token (mocked).
#[test]
#[fork("mainnet")]
fn test_fork_collect_lp_fees_after_graduation() {
    mock_ekubo_initialize_pool();
    mock_ekubo_mint_and_deposit();
    // Mock collect_fees to return (fees0=500, fees1=300)
    start_mock_call::<(u128, u128)>(
        ekubo_positions_mainnet(),
        selector!("collect_fees"),
        (500_u128, 300_u128),
    );

    let launchpad_addr = deploy_fork_launchpad();
    let base_asset_addr = deploy_base_asset('BASE3');
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('FeeTest', 'FEET', base_asset_addr, 0);

    let total = lp.quote_buy(token_addr, 2); // 161
    base.mint(alice(), total);
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, total);
    stop_cheat_caller_address(base_asset_addr);
    start_cheat_caller_address(launchpad_addr, alice());
    lp.buy(token_addr, 2, total); // auto-graduates
    stop_cheat_caller_address(launchpad_addr);

    assert(lp.is_graduated(token_addr), 'should be graduated');

    // Collect fees
    let (f0, f1) = lp.collect_lp_fees(token_addr);
    assert(f0 == 500, 'fees0=500');
    assert(f1 == 300, 'fees1=300');

    stop_mock_call(ekubo_positions_mainnet(), selector!("collect_fees"));
    stop_mock_call(ekubo_positions_mainnet(), selector!("mint_and_deposit_and_clear_both"));
    stop_mock_call(ekubo_core_placeholder(), selector!("initialize_pool"));
}

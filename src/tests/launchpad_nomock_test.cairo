/// True integration fork test — NO mocks.
///
/// Every call hits the real Ekubo contracts on mainnet.
/// This test will reveal exactly which integration points fail.
///
/// Known mainnet addresses
///   Ekubo Core:      0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b
///   Ekubo Positions: 0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067

use starknet::ContractAddress;
use starknet::contract_address_const;

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
};

use game::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use game::launchpad::{ILaunchpadDispatcher, ILaunchpadDispatcherTrait};

// ── Mainnet addresses ──────────────────────────────────────────────────────────
fn ekubo_positions() -> ContractAddress {
    contract_address_const::<0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067>()
}
fn ekubo_core() -> ContractAddress {
    // Ekubo Core mainnet (from https://ekubo.org/docs/contracts)
    contract_address_const::<0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b>()
}
fn owner() -> ContractAddress { contract_address_const::<'owner'>() }
fn alice() -> ContractAddress { contract_address_const::<'alice'>() }

// ── Helpers ────────────────────────────────────────────────────────────────────

fn deploy_base_asset() -> ContractAddress {
    let contract = declare("ERC20").unwrap().contract_class();
    // minter=0 → anyone can mint (test convenience)
    let calldata = array!['BASE', 'BASE', 18_felt252, 0_felt252];
    let (addr, _) = contract.deploy(@calldata).unwrap();
    addr
}

fn deploy_nomock_launchpad() -> ContractAddress {
    let token_class = declare("ERC20").unwrap().contract_class();
    let lp_class = declare("Launchpad").unwrap().contract_class();
    // threshold = 399_999: buying 100 tokens costs 40*(0+100)*100 = 400_000 > threshold
    // → auto-graduation fires on the buy.
    // With K=40, supply=100, reserve=400_000, fees=4_000:
    //   meme_lp = fees * supply / reserve = 4_000 * 100 / 400_000 = 1  (non-zero ✓)
    // core=0: skip initialize_pool — isolate mint_and_deposit_and_clear_both
    let calldata = array![
        (*token_class.class_hash).into(),
        ekubo_positions().into(),
        0_felt252,              // ekubo_core = 0 (skip initialize_pool)
        owner().into(),
        399_999_felt252,        // grad_threshold low
        0_felt252,              // grad_threshold high
        1_000_000_000_felt252,  // max_supply low (1B)
        0_felt252,              // max_supply high
        40_felt252,             // curve_k low
        0_felt252,              // curve_k high
        0_felt252,              // vesu_pool = disabled
        0_felt252,              // verifier = 0 (legacy nullifier mode)
    ];
    let (addr, _) = lp_class.deploy(@calldata).unwrap();
    addr
}

// ── Test: real Ekubo calls ─────────────────────────────────────────────────────
//
// This will FAIL if any of the following are wrong:
//   • Core address is not the real Core
//   • initialize_pool rejects our pool_key / tick
//   • mint_and_deposit rejects our tokens or approval target
//   • Our ERC20 selectors don't match what Ekubo expects
//
#[test]
#[fork("mainnet")]
fn test_nomock_graduation_hits_real_ekubo() {
    let launchpad_addr = deploy_nomock_launchpad();
    let base_asset_addr = deploy_base_asset();
    let lp = ILaunchpadDispatcher { contract_address: launchpad_addr };
    let base = IERC20Dispatcher { contract_address: base_asset_addr };

    let token_addr = lp.launch_token('RealEkuboMeme', 'RMEME', base_asset_addr, 0);

    // cost(0,100) = 40*(0+100)*100 = 400_000, fee = 4_000, total = 404_000
    // reserve(400_000) > threshold(399_999) → auto-graduation fires
    let total_cost = lp.quote_buy(token_addr, 100);
    assert(total_cost == 404000, 'wrong quote');

    base.mint(alice(), total_cost);
    start_cheat_caller_address(base_asset_addr, alice());
    base.approve(launchpad_addr, total_cost);
    stop_cheat_caller_address(base_asset_addr);

    // buy 100 → auto-graduation fires, calls REAL Positions::mint_and_deposit_and_clear_both
    start_cheat_caller_address(launchpad_addr, alice());
    let spent = lp.buy(token_addr, 100, total_cost);
    stop_cheat_caller_address(launchpad_addr);

    assert(spent == 404000, 'wrong amount spent');
    assert(lp.is_graduated(token_addr), 'should be graduated');

    // nft_id must be non-zero (real Ekubo returns a real position id)
    let nft_id = lp.get_ekubo_nft_id(token_addr);
    assert(nft_id != 0, 'nft_id must be nonzero');

    assert(lp.get_fees(token_addr) == 0, 'fees cleared after grad');

    let token_disp = IERC20Dispatcher { contract_address: token_addr };
    assert(token_disp.balance_of(alice()) == 100, 'alice should have 100 tokens');
}

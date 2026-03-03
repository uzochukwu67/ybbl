use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::Felt252TryIntoContractAddress;
use array::ArrayTrait;
use traits::Into;
use traits::TryInto;
use result::ResultTrait;
use option::OptionTrait;
use serde::Serde;

use snforge_std::{
    declare, ContractClassTrait,
    start_prank, stop_prank,
    start_mock_call, stop_mock_call,
};

use reddio_cairo::strategies::strategy_manager::IStrategyManagerDispatcher;
use reddio_cairo::strategies::strategy_manager::IStrategyManagerDispatcherTrait;

// ============================================================================
// Addresses
// ============================================================================
fn CURATOR() -> ContractAddress {
    contract_address_const::<0x1234>()
}

fn VAULT() -> ContractAddress {
    contract_address_const::<0xAAAA>()
}

fn TOKEN() -> ContractAddress {
    contract_address_const::<0xBBBB>()
}

fn VESU_ADAPTER() -> ContractAddress {
    contract_address_const::<0x100>()
}

fn EKUBO_ADAPTER() -> ContractAddress {
    contract_address_const::<0x200>()
}

fn NOSTRA_ADAPTER() -> ContractAddress {
    contract_address_const::<0x300>()
}

fn ATTACKER() -> ContractAddress {
    contract_address_const::<0xDEAD>()
}

// ============================================================================
// Helper: Deploy and initialize a StrategyManager
// ============================================================================
fn deploy_manager() -> (ContractAddress, IStrategyManagerDispatcher) {
    let contract = declare('StrategyManager');
    let calldata = array![];
    let addr = contract.deploy(@calldata).unwrap();
    let manager = IStrategyManagerDispatcher { contract_address: addr };

    start_prank(addr, CURATOR());
    manager.initialize(VAULT(), CURATOR(), TOKEN(), VESU_ADAPTER(), EKUBO_ADAPTER(), NOSTRA_ADAPTER());
    stop_prank(addr);

    (addr, manager)
}

// ============================================================================
// TEST GROUP 1: Strategy Manager Initialization
// ============================================================================

#[test]
fn test_sm_initialization() {
    let (_, manager) = deploy_manager();

    // Default allocation: 40/30/30
    assert(manager.get_target_allocation(0) == 4000, 'Vesu should be 4000');
    assert(manager.get_target_allocation(1) == 3000, 'Ekubo should be 3000');
    assert(manager.get_target_allocation(2) == 3000, 'Nostra should be 3000');

    // Adapters
    assert(manager.get_adapter_address(0) == VESU_ADAPTER(), 'Wrong vesu adapter');
    assert(manager.get_adapter_address(1) == EKUBO_ADAPTER(), 'Wrong ekubo adapter');
    assert(manager.get_adapter_address(2) == NOSTRA_ADAPTER(), 'Wrong nostra adapter');

    // None paused
    assert(!manager.is_strategy_paused(0), 'Vesu should not be paused');
    assert(!manager.is_strategy_paused(1), 'Ekubo should not be paused');
    assert(!manager.is_strategy_paused(2), 'Nostra should not be paused');
}

#[test]
#[should_panic(expected: ('Already initialized', ))]
fn test_sm_double_init() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, CURATOR());
    manager.initialize(VAULT(), CURATOR(), TOKEN(), VESU_ADAPTER(), EKUBO_ADAPTER(), NOSTRA_ADAPTER());
    stop_prank(addr);
}

#[test]
#[should_panic(expected: ('Invalid vault', ))]
fn test_sm_init_zero_vault() {
    let contract = declare('StrategyManager');
    let calldata = array![];
    let addr = contract.deploy(@calldata).unwrap();
    let manager = IStrategyManagerDispatcher { contract_address: addr };

    manager.initialize(
        contract_address_const::<0>(),
        CURATOR(),
        TOKEN(),
        VESU_ADAPTER(),
        EKUBO_ADAPTER(),
        NOSTRA_ADAPTER(),
    );
}

// ============================================================================
// TEST GROUP 2: Allocation Management
// ============================================================================

#[test]
fn test_sm_set_allocations_custom() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, CURATOR());
    manager.set_target_allocations(5000, 2500, 2500);
    stop_prank(addr);

    assert(manager.get_target_allocation(0) == 5000, 'Vesu should be 5000');
    assert(manager.get_target_allocation(1) == 2500, 'Ekubo should be 2500');
    assert(manager.get_target_allocation(2) == 2500, 'Nostra should be 2500');
}

#[test]
fn test_sm_partial_allocation() {
    let (addr, manager) = deploy_manager();

    // Only 60% allocated, 40% stays idle
    start_prank(addr, CURATOR());
    manager.set_target_allocations(3000, 2000, 1000);
    stop_prank(addr);

    let total = manager.get_target_allocation(0)
        + manager.get_target_allocation(1)
        + manager.get_target_allocation(2);
    assert(total == 6000, 'Total should be 6000 bps');
}

#[test]
fn test_sm_zero_allocation() {
    let (addr, manager) = deploy_manager();

    // All funds idle
    start_prank(addr, CURATOR());
    manager.set_target_allocations(0, 0, 0);
    stop_prank(addr);

    assert(manager.get_target_allocation(0) == 0, 'Vesu should be 0');
    assert(manager.get_target_allocation(1) == 0, 'Ekubo should be 0');
    assert(manager.get_target_allocation(2) == 0, 'Nostra should be 0');
}

#[test]
#[should_panic(expected: ('Total exceeds 100%', ))]
fn test_sm_over_allocation() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, CURATOR());
    manager.set_target_allocations(5000, 3000, 3000); // 110%
    stop_prank(addr);
}

#[test]
fn test_sm_max_allocation() {
    let (addr, manager) = deploy_manager();

    // Exactly 100%
    start_prank(addr, CURATOR());
    manager.set_target_allocations(5000, 3000, 2000);
    stop_prank(addr);

    let total = manager.get_target_allocation(0)
        + manager.get_target_allocation(1)
        + manager.get_target_allocation(2);
    assert(total == 10000, 'Should equal 10000 bps');
}

// ============================================================================
// TEST GROUP 3: Access Control
// ============================================================================

#[test]
#[should_panic(expected: ('Only curator', ))]
fn test_sm_non_curator_set_alloc() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, ATTACKER());
    manager.set_target_allocations(5000, 2500, 2500);
    stop_prank(addr);
}

#[test]
#[should_panic(expected: ('Only curator', ))]
fn test_sm_non_curator_pause() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, ATTACKER());
    manager.pause_strategy(0);
    stop_prank(addr);
}

#[test]
#[should_panic(expected: ('Only curator', ))]
fn test_sm_non_curator_unpause() {
    let (addr, manager) = deploy_manager();

    // First pause as curator
    start_prank(addr, CURATOR());
    manager.pause_strategy(0);
    stop_prank(addr);

    // Attacker tries to unpause
    start_prank(addr, ATTACKER());
    manager.unpause_strategy(0);
    stop_prank(addr);
}

// ============================================================================
// TEST GROUP 4: Pause / Unpause
// ============================================================================

#[test]
fn test_sm_pause_unpause_cycle() {
    let (addr, manager) = deploy_manager();

    // Initially unpaused
    assert(!manager.is_strategy_paused(0), 'Should start unpaused');

    // Pause vesu
    start_prank(addr, CURATOR());
    manager.pause_strategy(0);
    stop_prank(addr);
    assert(manager.is_strategy_paused(0), 'Should be paused');
    assert(!manager.is_strategy_paused(1), 'Ekubo unaffected');

    // Unpause vesu
    start_prank(addr, CURATOR());
    manager.unpause_strategy(0);
    stop_prank(addr);
    assert(!manager.is_strategy_paused(0), 'Should be unpaused');
}

#[test]
fn test_sm_pause_all_strategies() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, CURATOR());
    manager.pause_strategy(0);
    manager.pause_strategy(1);
    manager.pause_strategy(2);
    stop_prank(addr);

    assert(manager.is_strategy_paused(0), 'Vesu should be paused');
    assert(manager.is_strategy_paused(1), 'Ekubo should be paused');
    assert(manager.is_strategy_paused(2), 'Nostra should be paused');
}

#[test]
#[should_panic(expected: ('Vesu strategy paused', ))]
fn test_sm_deploy_to_paused_vesu() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, CURATOR());
    manager.pause_strategy(0);
    stop_prank(addr);

    // Try to deploy to paused strategy (as vault)
    start_prank(addr, VAULT());
    manager.deploy_to_vesu(1000);
    stop_prank(addr);
}

#[test]
#[should_panic(expected: ('Ekubo strategy paused', ))]
fn test_sm_deploy_to_paused_ekubo() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, CURATOR());
    manager.pause_strategy(1);
    stop_prank(addr);

    start_prank(addr, VAULT());
    manager.deploy_to_ekubo(1000);
    stop_prank(addr);
}

#[test]
#[should_panic(expected: ('Nostra strategy paused', ))]
fn test_sm_deploy_to_paused_nostra() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, CURATOR());
    manager.pause_strategy(2);
    stop_prank(addr);

    start_prank(addr, VAULT());
    manager.deploy_to_nostra(1000);
    stop_prank(addr);
}

// ============================================================================
// TEST GROUP 5: Invalid Strategy IDs
// ============================================================================

#[test]
fn test_sm_invalid_strategy_id_allocation() {
    let (_, manager) = deploy_manager();
    assert(manager.get_target_allocation(99) == 0, 'Invalid should be 0');
}

#[test]
fn test_sm_invalid_strategy_id_adapter() {
    let (_, manager) = deploy_manager();
    assert(
        manager.get_adapter_address(99) == contract_address_const::<0>(),
        'Invalid should be zero addr',
    );
}

#[test]
fn test_sm_invalid_strategy_id_paused() {
    let (_, manager) = deploy_manager();
    assert(manager.is_strategy_paused(99), 'Invalid should be paused');
}

// ============================================================================
// TEST GROUP 6: Deploy/Withdraw with Mocked Adapters
// ============================================================================

#[test]
fn test_sm_deploy_to_vesu_mocked() {
    let (addr, manager) = deploy_manager();
    let amount: u256 = 500000;

    // Mock: token.transfer returns true
    start_mock_call(TOKEN(), 'transfer', true);
    // Mock: adapter.deposit succeeds (void return)
    start_mock_call(VESU_ADAPTER(), 'deposit', ());

    start_prank(addr, VAULT());
    manager.deploy_to_vesu(amount);
    stop_prank(addr);

    stop_mock_call(TOKEN(), 'transfer');
    stop_mock_call(VESU_ADAPTER(), 'deposit');
}

#[test]
fn test_sm_deploy_to_ekubo_mocked() {
    let (addr, manager) = deploy_manager();

    start_mock_call(TOKEN(), 'transfer', true);
    start_mock_call(EKUBO_ADAPTER(), 'deposit', ());

    start_prank(addr, VAULT());
    manager.deploy_to_ekubo(250000);
    stop_prank(addr);

    stop_mock_call(TOKEN(), 'transfer');
    stop_mock_call(EKUBO_ADAPTER(), 'deposit');
}

#[test]
fn test_sm_deploy_to_nostra_mocked() {
    let (addr, manager) = deploy_manager();

    start_mock_call(TOKEN(), 'transfer', true);
    start_mock_call(NOSTRA_ADAPTER(), 'deposit', ());

    start_prank(addr, VAULT());
    manager.deploy_to_nostra(250000);
    stop_prank(addr);

    stop_mock_call(TOKEN(), 'transfer');
    stop_mock_call(NOSTRA_ADAPTER(), 'deposit');
}

#[test]
fn test_sm_withdraw_from_vesu_mocked() {
    let (addr, manager) = deploy_manager();

    // First deploy
    start_mock_call(TOKEN(), 'transfer', true);
    start_mock_call(VESU_ADAPTER(), 'deposit', ());
    start_prank(addr, VAULT());
    manager.deploy_to_vesu(500000);
    stop_prank(addr);

    // Then withdraw
    start_mock_call(VESU_ADAPTER(), 'withdraw', ());
    start_prank(addr, VAULT());
    manager.withdraw_from_vesu(200000);
    stop_prank(addr);

    stop_mock_call(TOKEN(), 'transfer');
    stop_mock_call(VESU_ADAPTER(), 'deposit');
    stop_mock_call(VESU_ADAPTER(), 'withdraw');
}

// ============================================================================
// TEST GROUP 7: Harvest with Mocked Adapters
// ============================================================================

#[test]
fn test_sm_harvest_all_mocked() {
    let (addr, manager) = deploy_manager();

    // Mock each adapter's harvest returning yield amounts
    let vesu_yield: u256 = 1000;
    let ekubo_yield: u256 = 500;
    let nostra_yield: u256 = 750;

    start_mock_call(VESU_ADAPTER(), 'harvest', vesu_yield);
    start_mock_call(EKUBO_ADAPTER(), 'harvest', ekubo_yield);
    start_mock_call(NOSTRA_ADAPTER(), 'harvest', nostra_yield);

    start_prank(addr, CURATOR());
    let total_yield = manager.harvest_all();
    stop_prank(addr);

    assert(total_yield == vesu_yield + ekubo_yield + nostra_yield, 'Wrong total yield');

    stop_mock_call(VESU_ADAPTER(), 'harvest');
    stop_mock_call(EKUBO_ADAPTER(), 'harvest');
    stop_mock_call(NOSTRA_ADAPTER(), 'harvest');
}

#[test]
fn test_sm_harvest_individual_mocked() {
    let (addr, manager) = deploy_manager();

    start_mock_call(VESU_ADAPTER(), 'harvest', 1234_u256);
    start_prank(addr, CURATOR());
    let y = manager.harvest_vesu();
    stop_prank(addr);
    assert(y == 1234, 'Wrong vesu yield');
    stop_mock_call(VESU_ADAPTER(), 'harvest');

    start_mock_call(EKUBO_ADAPTER(), 'harvest', 5678_u256);
    start_prank(addr, CURATOR());
    let y2 = manager.harvest_ekubo();
    stop_prank(addr);
    assert(y2 == 5678, 'Wrong ekubo yield');
    stop_mock_call(EKUBO_ADAPTER(), 'harvest');

    start_mock_call(NOSTRA_ADAPTER(), 'harvest', 9999_u256);
    start_prank(addr, CURATOR());
    let y3 = manager.harvest_nostra();
    stop_prank(addr);
    assert(y3 == 9999, 'Wrong nostra yield');
    stop_mock_call(NOSTRA_ADAPTER(), 'harvest');
}

// ============================================================================
// TEST GROUP 8: View functions with Mocked Adapters
// ============================================================================

#[test]
fn test_sm_total_deployed_mocked() {
    let (_, manager) = deploy_manager();

    start_mock_call(VESU_ADAPTER(), 'get_total_balance', 100000_u256);
    start_mock_call(EKUBO_ADAPTER(), 'get_total_balance', 200000_u256);
    start_mock_call(NOSTRA_ADAPTER(), 'get_total_balance', 300000_u256);

    let total = manager.get_total_deployed();
    assert(total == 600000, 'Wrong total deployed');

    stop_mock_call(VESU_ADAPTER(), 'get_total_balance');
    stop_mock_call(EKUBO_ADAPTER(), 'get_total_balance');
    stop_mock_call(NOSTRA_ADAPTER(), 'get_total_balance');
}

#[test]
fn test_sm_total_pending_yield_mocked() {
    let (_, manager) = deploy_manager();

    start_mock_call(VESU_ADAPTER(), 'get_pending_yield', 100_u256);
    start_mock_call(EKUBO_ADAPTER(), 'get_pending_yield', 200_u256);
    start_mock_call(NOSTRA_ADAPTER(), 'get_pending_yield', 300_u256);

    let total = manager.get_total_pending_yield();
    assert(total == 600, 'Wrong total yield');

    stop_mock_call(VESU_ADAPTER(), 'get_pending_yield');
    stop_mock_call(EKUBO_ADAPTER(), 'get_pending_yield');
    stop_mock_call(NOSTRA_ADAPTER(), 'get_pending_yield');
}

#[test]
fn test_sm_individual_balances_mocked() {
    let (_, manager) = deploy_manager();

    start_mock_call(VESU_ADAPTER(), 'get_total_balance', 111_u256);
    assert(manager.get_vesu_balance() == 111, 'Wrong vesu balance');
    stop_mock_call(VESU_ADAPTER(), 'get_total_balance');

    start_mock_call(EKUBO_ADAPTER(), 'get_total_balance', 222_u256);
    assert(manager.get_ekubo_balance() == 222, 'Wrong ekubo balance');
    stop_mock_call(EKUBO_ADAPTER(), 'get_total_balance');

    start_mock_call(NOSTRA_ADAPTER(), 'get_total_balance', 333_u256);
    assert(manager.get_nostra_balance() == 333, 'Wrong nostra balance');
    stop_mock_call(NOSTRA_ADAPTER(), 'get_total_balance');
}

// ============================================================================
// TEST GROUP 9: Emergency Withdraw
// ============================================================================

#[test]
fn test_sm_emergency_withdraw_all_mocked() {
    let (addr, manager) = deploy_manager();

    start_mock_call(VESU_ADAPTER(), 'emergency_withdraw', 10000_u256);
    start_mock_call(EKUBO_ADAPTER(), 'emergency_withdraw', 20000_u256);
    start_mock_call(NOSTRA_ADAPTER(), 'emergency_withdraw', 30000_u256);

    start_prank(addr, CURATOR());
    let total = manager.emergency_withdraw_all();
    stop_prank(addr);

    assert(total == 60000, 'Wrong total recovered');

    // All strategies should be paused after emergency
    assert(manager.is_strategy_paused(0), 'Vesu should be paused');
    assert(manager.is_strategy_paused(1), 'Ekubo should be paused');
    assert(manager.is_strategy_paused(2), 'Nostra should be paused');

    stop_mock_call(VESU_ADAPTER(), 'emergency_withdraw');
    stop_mock_call(EKUBO_ADAPTER(), 'emergency_withdraw');
    stop_mock_call(NOSTRA_ADAPTER(), 'emergency_withdraw');
}

#[test]
#[should_panic(expected: ('Only curator', ))]
fn test_sm_emergency_withdraw_non_curator() {
    let (addr, manager) = deploy_manager();

    start_prank(addr, ATTACKER());
    manager.emergency_withdraw_all();
    stop_prank(addr);
}

// ============================================================================
// TEST GROUP 10: Rebalance with Mocked Adapters
// ============================================================================

#[test]
fn test_sm_rebalance_mocked() {
    let (addr, manager) = deploy_manager();

    // Mock current balances
    start_mock_call(VESU_ADAPTER(), 'get_total_balance', 500000_u256);
    start_mock_call(EKUBO_ADAPTER(), 'get_total_balance', 300000_u256);
    start_mock_call(NOSTRA_ADAPTER(), 'get_total_balance', 200000_u256);

    start_prank(addr, CURATOR());
    manager.rebalance();
    stop_prank(addr);

    stop_mock_call(VESU_ADAPTER(), 'get_total_balance');
    stop_mock_call(EKUBO_ADAPTER(), 'get_total_balance');
    stop_mock_call(NOSTRA_ADAPTER(), 'get_total_balance');

    // Rebalance succeeded - just verifying no panic
}

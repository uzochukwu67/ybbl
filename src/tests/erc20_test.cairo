use starknet::ContractAddress;
use starknet::contract_address_const;

use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};

use game::erc20::IERC20Dispatcher;
use game::erc20::IERC20DispatcherTrait;

fn deploy_erc20(name: felt252, symbol: felt252, decimals: u8) -> ContractAddress {
    let contract = declare("ERC20").unwrap().contract_class();
    // minter_ = 0 means unrestricted mint (for unit tests only)
    let mut calldata = array![name, symbol, decimals.into(), 0];
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    contract_address
}

fn alice() -> ContractAddress {
    contract_address_const::<'alice'>()
}

fn bob() -> ContractAddress {
    contract_address_const::<'bob'>()
}

#[test]
fn test_initial_metadata() {
    let addr = deploy_erc20('MyToken', 'MTK', 18);
    let token = IERC20Dispatcher { contract_address: addr };

    assert(token.get_name() == 'MyToken', 'wrong name');
    assert(token.get_symbol() == 'MTK', 'wrong symbol');
    assert(token.get_decimals() == 18, 'wrong decimals');
    assert(token.get_total_supply() == 0, 'supply should be 0');
}

#[test]
fn test_mint_increases_balance_and_supply() {
    let addr = deploy_erc20('MyToken', 'MTK', 18);
    let token = IERC20Dispatcher { contract_address: addr };

    token.mint(alice(), 1000);

    assert(token.balance_of(alice()) == 1000, 'wrong balance');
    assert(token.get_total_supply() == 1000, 'wrong supply');
}

#[test]
fn test_transfer() {
    let addr = deploy_erc20('MyToken', 'MTK', 18);
    let token = IERC20Dispatcher { contract_address: addr };

    token.mint(alice(), 500);

    start_cheat_caller_address(addr, alice());
    token.transfer(bob(), 200);
    stop_cheat_caller_address(addr);

    assert(token.balance_of(alice()) == 300, 'alice balance wrong');
    assert(token.balance_of(bob()) == 200, 'bob balance wrong');
}

#[test]
fn test_approve_and_transfer_from() {
    let addr = deploy_erc20('MyToken', 'MTK', 18);
    let token = IERC20Dispatcher { contract_address: addr };

    token.mint(alice(), 500);

    // alice approves bob to spend 300
    start_cheat_caller_address(addr, alice());
    token.approve(bob(), 300);
    stop_cheat_caller_address(addr);

    assert(token.allowance(alice(), bob()) == 300, 'wrong allowance');

    // bob transfers from alice to bob
    start_cheat_caller_address(addr, bob());
    token.transfer_from(alice(), bob(), 300);
    stop_cheat_caller_address(addr);

    assert(token.balance_of(alice()) == 200, 'alice balance wrong');
    assert(token.balance_of(bob()) == 300, 'bob balance wrong');
    assert(token.allowance(alice(), bob()) == 0, 'allowance not spent');
}

#[test]
fn test_increase_and_decrease_allowance() {
    let addr = deploy_erc20('MyToken', 'MTK', 18);
    let token = IERC20Dispatcher { contract_address: addr };

    start_cheat_caller_address(addr, alice());
    token.approve(bob(), 100);
    token.increase_allowance(bob(), 50);
    stop_cheat_caller_address(addr);

    assert(token.allowance(alice(), bob()) == 150, 'increase failed');

    start_cheat_caller_address(addr, alice());
    token.decrease_allowance(bob(), 30);
    stop_cheat_caller_address(addr);

    assert(token.allowance(alice(), bob()) == 120, 'decrease failed');
}

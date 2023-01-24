#[contract]
mod ArgentAccount {
    
    struct Storage { 
        signer: felt,
        guardian: felt,
        guardian_backup: felt,
        supported_interfaces: Map::<felt, bool>,
    }

    #[external]
    fn initialize(signer: felt, guardian: felt, guardian_backup: felt) {
        // check that we are not already initialized
        assert(signer::read() == 0, 'argent: already initialized');
        // check that the target signer is not zero
        assert(signer != 0, 'argent: signer cannot be null');
        // initialize the account
        signer::write(signer);
        guardian::write(guardian);
        guardian_backup::write(guardian_backup);
    }

    #[view]
    fn get_signer() -> felt {
        signer::read()
    }

    #[view]
    fn get_guardian() -> felt {
        guardian::read()
    }

    #[view]
    fn get_guardian_backup() -> felt {
        guardian_backup::read()
    }

    // ERC165

    #[view]
    fn supportsInterface(interface_id: felt) -> bool {
        // using combination of hardcoding and dynamic lookup for tradeoff between performance and flexibility
        if interface_id == 0x01ffc9a7 {
            true // ERC165
        } else if interface_id == 0xa66bd575 { // TODO: validate value
            true // IAccount
        } else {
            supported_interfaces::read(interface_id)
        }
    }

    #[external]
    fn register_interface(interface_id: felt) {
        // assert_only_self()
        supported_interfaces::write(interface_id, true);
    }
}

#[test]
#[available_gas(20000)]
fn initialize() {
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_signer() == 1, 'value should be 1');
    assert(ArgentAccount::get_guardian() == 2, 'value should be 2');
    assert(ArgentAccount::get_guardian_backup() == 3, 'value should be 3');
}

#[test]
#[available_gas(20000)]
#[should_panic(expected = 'argent: signer cannot be null')]
fn initialize_with_null_signer() {
    ArgentAccount::initialize(0, 2, 3);
}

#[test]
#[available_gas(20000)]
#[should_panic(expected = 'argent: already initialized')]
fn already_initialized() {
    ArgentAccount::initialize(1, 2, 3);
    assert(ArgentAccount::get_signer() == 1, 'value should be 1');
    ArgentAccount::initialize(10, 20, 0);
}

#[test]
#[available_gas(20000)]
fn erc165_basic_interfaces() {
    assert(ArgentAccount::supportsInterface(0) == false, 'value should be false');
    assert(ArgentAccount::supportsInterface(0xffffffff) == false, 'value should be false');
    assert(ArgentAccount::supportsInterface(0x01ffc9a7) == true, 'value should be true');
    assert(ArgentAccount::supportsInterface(0xa66bd575) == true, 'value should be true');
}

#[test]
#[available_gas(20000)]
fn erc165_interface_registering() {
    assert(ArgentAccount::supportsInterface(0x12345678) == false, 'value should be false');
    ArgentAccount::register_interface(0x12345678);
    assert(ArgentAccount::supportsInterface(0x12345678) == true, 'value should be true');

    // TODO: add test making sure register_interface can only be called by self
}

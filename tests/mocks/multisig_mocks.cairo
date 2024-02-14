#[starknet::contract]
mod MultisigMock {
    use argent::multisig::multisig::multisig_component;
    use argent::signer_storage::signer_list::signer_list_component;

    component!(path: multisig_component, storage: multisig, event: MultisigEvents);
    #[abi(embed_v0)]
    impl Multisig = multisig_component::MultisigImpl<ContractState>;
    #[abi(embed_v0)]
    impl MultisigInternal = multisig_component::MultisigInternalImpl<ContractState>;

    component!(path: signer_list_component, storage: signer_list, event: SignerListEvents);
    impl SignerListInternal = signer_list_component::SignerListInternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        signer_list: signer_list_component::Storage,
        #[substorage(v0)]
        multisig: multisig_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SignerListEvents: signer_list_component::Event,
        MultisigEvents: multisig_component::Event,
    }
}

#[starknet::contract]
mod SRC5Mock {
    use argent::introspection::src5::src5_component;

    component!(path: src5_component, storage: src5, event: SRC5Events);
    #[abi(embed_v0)]
    impl SRC5 = src5_component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Legacy = src5_component::SRC5LegacyImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: src5_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SRC5Events: src5_component::Event,
    }
}

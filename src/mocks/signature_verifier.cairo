#[starknet::contract]
mod SignatureVerifier {
    use argent::signer::{signer_signature::{Signer, SignerSignature, SignerSignatureTrait,}};

    use argent::utils::serialization::full_deserialize;
    use starknet::VALIDATED;

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[starknet::interface]
    trait ISignatureVerifier<TContractState> {
        fn assert_valid_signature(self: @TContractState, hash: felt252, signature: Array<felt252>);
    }

    #[abi(embed_v0)]
    impl External of ISignatureVerifier<ContractState> {
        fn assert_valid_signature(self: @ContractState, hash: felt252, signature: Array<felt252>) {
            let signer_signature = full_deserialize::<SignerSignature>(signature.span()).unwrap();
            // This is for testing purposes only, in a real contract you should check that the signer is a valid signer.
            assert(signer_signature.is_valid_signature(hash), 'invalid-signature');
        }
    }
}


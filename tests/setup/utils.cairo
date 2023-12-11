use argent::common::signer_signature::{SignerType, StarknetSignature};

fn to_starknet_signer_signatures(arr: Array<felt252>) -> Array<felt252> {
    if (arr.len() == 3) {
        let mut signature = array![1];
        let sig = SignerType::Starknet(StarknetSignature { r: *arr.at(1), s: *arr.at(2) });
        arr.at(0).serialize(ref signature);
        sig.serialize(ref signature);
        signature
    } else if (arr.len() == 6) {
        let sig1 = SignerType::Starknet(StarknetSignature { r: *arr.at(1), s: *arr.at(2) });
        let sig2 = SignerType::Starknet(StarknetSignature { r: *arr.at(4), s: *arr.at(5) });
        let mut signature = array![2];
        arr.at(0).serialize(ref signature);
        sig1.serialize(ref signature);
        arr.at(3).serialize(ref signature);
        sig2.serialize(ref signature);
        signature
    } else {
        assert(0 == 1, 'wrong length');
        array![]
    }
}

fn to_starknet_signer_type(r: felt252, s: felt252) -> Span<felt252> {
    let mut signature = array![];
    let sig = SignerType::Starknet(StarknetSignature { r: r, s: s });
    sig.serialize(ref signature);
    signature.span()
}

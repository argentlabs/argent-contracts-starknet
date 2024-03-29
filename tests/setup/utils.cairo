use argent::signer::signer_signature::{Signer, SignerSignature, StarknetSignature, StarknetSigner, SignerTrait};
use integer::{u32_safe_divmod, u32_to_felt252};
use snforge_std::{start_prank, start_spoof, CheatTarget, TxInfoMockTrait};
use starknet::ContractAddress;

fn to_starknet_signer_signatures(arr: Array<felt252>) -> Array<felt252> {
    let size = arr.len() / 3;
    let mut signatures = array![size.into()];
    let mut i: usize = 0;
    loop {
        if i == size {
            break;
        }
        let signer_signature = SignerSignature::Starknet(
            (
                (*arr.at(i * 3)).try_into().expect('argent/zero-pubkey'),
                StarknetSignature { r: *arr.at(i * 3 + 1), s: *arr.at(i * 3 + 2) }
            )
        );
        signer_signature.serialize(ref signatures);
        i += 1;
    };
    signatures
}

fn set_tx_version_foundry(version: felt252, address: ContractAddress) {
    let mut tx_info = TxInfoMockTrait::default();
    tx_info.version = Option::Some(version);
    start_spoof(CheatTarget::One(address), tx_info);
}

impl felt252TryIntoStarknetSigner of TryInto<felt252, StarknetSigner> {
    #[inline(always)]
    fn try_into(self: felt252) -> Option<StarknetSigner> {
        Option::Some(StarknetSigner { pubkey: self.try_into().expect('Cant create starknet signer') })
    }
}


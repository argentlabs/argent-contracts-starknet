use argent::signer::eip191::is_valid_eip191_signature;
use argent::signer::webauthn::{
    WebauthnAssertion, get_webauthn_hash, verify_client_data_json, verify_authenticator_data
};
use ecdsa::check_ecdsa_signature;
use hash::{HashStateExTrait, HashStateTrait};
use poseidon::{hades_permutation, PoseidonTrait};
use starknet::SyscallResultTrait;
use starknet::secp256_trait::{Secp256PointTrait, Signature as Secp256r1Signature, recover_public_key};
use starknet::secp256k1::Secp256k1Point;
use starknet::secp256r1::Secp256r1Point;
use starknet::{EthAddress, eth_signature::{Signature as Secp256k1Signature, is_eth_signature_valid}};

const STARKNET_SIGNER_TYPE: felt252 = 'Starknet Signer';
const SECP256K1_SIGNER_TYPE: felt252 = 'Secp256k1 Signer';
const SECP256R1_SIGNER_TYPE: felt252 = 'Secp256r1 Signer';
const EIP191_SIGNER_TYPE: felt252 = 'Eip191 Signer';
const WEBAUTHN_SIGNER_TYPE: felt252 = 'Webauthn Signer';

#[derive(Drop, Copy, PartialEq, Serde, Default)]
enum SignerType {
    #[default]
    Starknet,
    Secp256k1,
    Secp256r1,
    Eip191,
    Webauthn,
}

#[derive(Drop, Copy, Serde)]
enum Signer {
    Starknet: StarknetSigner,
    Secp256k1: Secp256k1Signer,
    Secp256r1: Secp256r1Signer,
    Eip191: Eip191Signer,
    Webauthn: WebauthnSigner,
}

#[derive(Drop, Copy, Serde, PartialEq, Default)]
struct SignerStorageValue {
    stored_data: felt252,
    signer_type: SignerType,
}

trait SignerTrait<T> {
    fn into_guid(self: T) -> felt252;
    fn storage_value(self: @T) -> SignerStorageValue;
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct StarknetSigner {
    pubkey: NonZero<felt252>
}

#[derive(Drop, Copy, PartialEq)]
struct Secp256k1Signer {
    pubkey_hash: EthAddress
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct Secp256r1Signer {
    pubkey: NonZero<u256>
}

#[derive(Drop, Copy, PartialEq)]
struct Eip191Signer {
    eth_address: EthAddress
}
#[derive(Drop, Copy, Serde, PartialEq)]
struct WebauthnSigner {
    origin: NonZero<felt252>,
    rp_id_hash: NonZero<u256>,
    pubkey: NonZero<u256>
}

// Ensures that the pubkey_hash is not zero as we can't do NonZero<EthAddress>.
impl Secp256k1SignerSerde of Serde<Secp256k1Signer> {
    #[inline(always)]
    fn serialize(self: @Secp256k1Signer, ref output: Array<felt252>) {
        self.pubkey_hash.serialize(ref output);
    }

    #[inline(always)]
    fn deserialize(ref serialized: Span<felt252>) -> Option<Secp256k1Signer> {
        let pubkey_hash = Serde::<EthAddress>::deserialize(ref serialized)?;
        assert(pubkey_hash.address != 0, 'argent/zero-pubkey-hash');
        Option::Some(Secp256k1Signer { pubkey_hash })
    }
}

impl Eip191SignerSerde of Serde<Eip191Signer> {
    #[inline(always)]
    fn serialize(self: @Eip191Signer, ref output: Array<felt252>) {
        self.eth_address.serialize(ref output);
    }

    #[inline(always)]
    fn deserialize(ref serialized: Span<felt252>) -> Option<Eip191Signer> {
        let eth_address = Serde::<EthAddress>::deserialize(ref serialized)?;
        assert(eth_address.address != 0, 'argent/zero-eth-EthAddress');
        Option::Some(Eip191Signer { eth_address })
    }
}

#[inline(always)]
fn starknet_signer_from_pubkey(pubkey: felt252) -> Signer {
    Signer::Starknet(StarknetSigner { pubkey: pubkey.try_into().expect('argent/zero-pubkey') })
}

#[inline(always)]
fn new_web_authn_signer(origin: felt252, rp_id_hash: u256, pubkey: u256) -> WebauthnSigner {
    WebauthnSigner {
        origin: origin.try_into().expect('argent/zero-origin'),
        rp_id_hash: rp_id_hash.try_into().expect('argent/zero-rp-id-hash'),
        pubkey: pubkey.try_into().expect('argent/zero-pubkey')
    }
}

impl SignerTraitImpl of SignerTrait<Signer> {
    #[inline(always)]
    fn into_guid(self: Signer) -> felt252 {
        // TODO avoiding excesive hashing rounds
        match self {
            Signer::Starknet(signer) => signer.pubkey.into(),
            Signer::Secp256k1(signer) => {
                let (hash, _, _) = hades_permutation(SECP256K1_SIGNER_TYPE, signer.pubkey_hash.address, 2);
                hash
            },
            Signer::Secp256r1(signer) => {
                let pubkey: u256 = signer.pubkey.into();
                PoseidonTrait::new().update_with(SECP256R1_SIGNER_TYPE).update_with(pubkey).finalize()
            },
            Signer::Eip191(signer) => {
                let (hash, _, _) = hades_permutation(EIP191_SIGNER_TYPE, signer.eth_address.address, 2);
                hash
            },
            Signer::Webauthn(signer) => {
                let origin: felt252 = signer.origin.into();
                let rp_id_hash: u256 = signer.rp_id_hash.into();
                let pubkey: u256 = signer.pubkey.into();
                PoseidonTrait::new()
                    .update_with(WEBAUTHN_SIGNER_TYPE)
                    .update_with(origin)
                    .update_with(rp_id_hash)
                    .update_with(pubkey)
                    .finalize()
            },
        }
    }

    #[inline(always)]
    fn storage_value(self: @Signer) -> SignerStorageValue {
        match self {
            Signer::Starknet(signer) => SignerStorageValue {
                signer_type: SignerType::Starknet, stored_data: (*signer.pubkey).into()
            },
            Signer::Secp256k1(signer) => SignerStorageValue {
                signer_type: SignerType::Secp256k1, stored_data: *signer.pubkey_hash.address
            },
            Signer::Secp256r1(_) => SignerStorageValue {
                signer_type: SignerType::Secp256r1, stored_data: (*self).into_guid()
            },
            Signer::Eip191(signer) => SignerStorageValue {
                signer_type: SignerType::Eip191, stored_data: *signer.eth_address.address
            },
            Signer::Webauthn(_) => SignerStorageValue {
                signer_type: SignerType::Webauthn, stored_data: (*self).into_guid()
            },
        }
    }
}

impl SignerStorageValueImpl of SignerTrait<SignerStorageValue> {
    #[inline(always)]
    fn into_guid(self: SignerStorageValue) -> felt252 {
        match self.signer_type {
            SignerType::Starknet => {
                let (hash, _, _) = hades_permutation(STARKNET_SIGNER_TYPE, self.stored_data, 2);
                hash
            },
            _ => self.stored_data,
        }
    }

    #[inline(always)]
    fn storage_value(self: @SignerStorageValue) -> SignerStorageValue {
        *self
    }
}

/// Enum of the different signature type supported.
/// For each type the variant contains a signer and an associated signature.
#[derive(Drop, Copy, Serde)]
enum SignerSignature {
    Starknet: (StarknetSigner, StarknetSignature),
    Secp256k1: (Secp256k1Signer, Secp256k1Signature),
    Secp256r1: (Secp256r1Signer, Secp256r1Signature),
    Eip191: (Eip191Signer, Secp256r1Signature),
    Webauthn: (WebauthnSigner, WebauthnAssertion),
}

trait SignerSignatureTrait {
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool;
    fn signer(self: SignerSignature) -> Signer;
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct StarknetSignature {
    r: felt252,
    s: felt252,
}

impl SignerSignatureImpl of SignerSignatureTrait {
    #[inline(always)]
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool {
        match self {
            SignerSignature::Starknet((signer, signature)) => is_valid_starknet_signature(hash, signer, signature),
            SignerSignature::Secp256k1((
                signer, signature
            )) => is_valid_secp256k1_signature(hash.into(), signer, signature),
            SignerSignature::Secp256r1((
                signer, signature
            )) => is_valid_secp256r1_signature(hash.into(), signer, signature),
            SignerSignature::Eip191((signer, signature)) => is_valid_eip191_signature(hash, signer, signature),
            SignerSignature::Webauthn((signer, signature)) => is_valid_webauthn_signature(hash, signer, signature),
        }
    }
    #[inline(always)]
    fn signer(self: SignerSignature) -> Signer {
        match self {
            SignerSignature::Starknet((signer, _)) => Signer::Starknet(signer),
            SignerSignature::Secp256k1((signer, _)) => Signer::Secp256k1(signer),
            SignerSignature::Secp256r1((signer, _)) => Signer::Secp256r1(signer),
            SignerSignature::Eip191((signer, _)) => Signer::Eip191(signer),
            SignerSignature::Webauthn((signer, _)) => Signer::Webauthn(signer)
        }
    }
}

impl SignerTypeIntoFelt252 of Into<SignerType, felt252> {
    #[inline(always)]
    fn into(self: SignerType) -> felt252 implicits() nopanic {
        match self {
            SignerType::Starknet => 0,
            SignerType::Secp256k1 => 1,
            SignerType::Secp256r1 => 2,
            SignerType::Eip191 => 3,
            SignerType::Webauthn => 4,
        }
    }
}

impl U256TryIntoSignerType of TryInto<u256, SignerType> {
    #[inline(always)]
    fn try_into(self: u256) -> Option<SignerType> {
        if self == 0 {
            Option::Some(SignerType::Starknet)
        } else if self == 1 {
            Option::Some(SignerType::Secp256k1)
        } else if self == 2 {
            Option::Some(SignerType::Secp256r1)
        } else if self == 3 {
            Option::Some(SignerType::Eip191)
        } else if self == 4 {
            Option::Some(SignerType::Webauthn)
        } else {
            Option::None
        }
    }
}

#[inline(always)]
fn is_valid_starknet_signature(hash: felt252, signer: StarknetSigner, signature: StarknetSignature) -> bool {
    check_ecdsa_signature(hash, signer.pubkey.into(), signature.r, signature.s)
}

#[inline(always)]
fn is_valid_secp256k1_signature(hash: u256, signer: Secp256k1Signer, signature: Secp256k1Signature) -> bool {
    is_eth_signature_valid(hash, signature, signer.pubkey_hash.into()).is_ok()
}

#[inline(always)]
fn is_valid_secp256r1_signature(hash: u256, signer: Secp256r1Signer, signature: Secp256r1Signature) -> bool {
    let recovered = recover_public_key::<Secp256r1Point>(hash, signature).expect('argent/invalid-sig-format');
    let (recovered_signer, _) = recovered.get_coordinates().expect('argent/invalid-sig-format');
    recovered_signer == signer.pubkey.into()
}

#[inline(always)]
fn is_valid_webauthn_signature(hash: felt252, signer: WebauthnSigner, assertion: WebauthnAssertion) -> bool {
    verify_client_data_json(@assertion, hash, signer.origin.into());
    verify_authenticator_data(assertion.authenticator_data, signer.rp_id_hash.into());

    let signed_hash = get_webauthn_hash(@assertion);
    is_valid_secp256r1_signature(signed_hash, Secp256r1Signer { pubkey: signer.pubkey }, assertion.signature)
}

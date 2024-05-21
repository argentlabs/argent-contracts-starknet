use argent::signer::eip191::is_valid_eip191_signature;
use argent::signer::webauthn::{WebauthnSignature, get_webauthn_hash, verify_authenticator_flags};
use argent::utils::hashing::poseidon_2;
use core::traits::TryInto;
use ecdsa::check_ecdsa_signature;
use hash::{HashStateExTrait, HashStateTrait};
use poseidon::{hades_permutation, PoseidonTrait};
use starknet::SyscallResultTrait;
use starknet::secp256_trait::{
    Secp256PointTrait, Secp256Trait, Signature as Secp256Signature, recover_public_key, is_valid_signature
};
use starknet::secp256k1::Secp256k1Point;
use starknet::secp256r1::{Secp256r1Point, Secp256r1Impl};
use starknet::{EthAddress, eth_signature::is_eth_signature_valid};

/// All signer type magic values. Used to derive their guid
const STARKNET_SIGNER_TYPE: felt252 = 'Starknet Signer';
const SECP256K1_SIGNER_TYPE: felt252 = 'Secp256k1 Signer';
const SECP256R1_SIGNER_TYPE: felt252 = 'Secp256r1 Signer';
const EIP191_SIGNER_TYPE: felt252 = 'Eip191 Signer';
const WEBAUTHN_SIGNER_TYPE: felt252 = 'Webauthn Signer';

/// @notice Secp256 Signature, the `y_parity` is omitted as it is assumed to be false
/// If your signature has a different `y_parity` you can convert it to this format by changing `s` to `Curve.N - s`
#[derive(Copy, Drop, Debug, PartialEq, Serde)]
struct Secp256SignatureEven {
    r: u256,
    s: u256,
}

impl Secp256SignatureEvenIntoSecp256Signature of Into<Secp256SignatureEven, Secp256Signature> {
    fn into(self: Secp256SignatureEven) -> Secp256Signature {
        Secp256Signature { r: self.r, s: self.s, y_parity: false }
    }
}

/// @notice The type of the signer that this version of the accounts supports
#[derive(Drop, Copy, PartialEq, Serde, Default)]
enum SignerType {
    #[default]
    Starknet,
    Secp256k1,
    Secp256r1,
    Eip191,
    Webauthn,
}

/// @notice The different signature type supported
/// Each variant must contain a signer and its associated signature
#[derive(Drop, Copy, Serde)]
enum SignerSignature {
    Starknet: (StarknetSigner, StarknetSignature),
    Secp256k1: (Secp256k1Signer, Secp256SignatureEven),
    Secp256r1: (Secp256r1Signer, Secp256SignatureEven),
    Eip191: (Eip191Signer, Secp256SignatureEven),
    Webauthn: (WebauthnSigner, WebauthnSignature),
}

/// @notice The starknet signature using the stark-curve
#[derive(Drop, Copy, Serde, PartialEq)]
struct StarknetSignature {
    r: felt252,
    s: felt252,
}

/// @notice Represents all supported Signers with their different signing schemes
#[derive(Drop, Copy, Serde)]
enum Signer {
    Starknet: StarknetSigner,
    Secp256k1: Secp256k1Signer,
    Secp256r1: Secp256r1Signer,
    Eip191: Eip191Signer,
    Webauthn: WebauthnSigner,
}

#[derive(Drop, Copy, Serde, PartialEq)]
struct SignerStorageValue {
    stored_value: felt252,
    signer_type: SignerType,
}

/// @notice The Starknet signer using the Starknet Curve
/// @param pubkey the public key as felt252 for a starknet signature. Cannot be zero
#[derive(Drop, Copy, Serde, PartialEq)]
struct StarknetSigner {
    pubkey: NonZero<felt252>
}

/// @notice The Secp256k1 signer using the Secp256k1 elliptic curve
/// @param pubkey_hash the right-most 160 bits of a Keccak hash of an ECDSA public key
#[derive(Drop, Copy, PartialEq)]
struct Secp256k1Signer {
    pubkey_hash: EthAddress
}

/// @notice The Secp256r1 signer using the Secp256r1 elliptic curve
/// @param pubkey the public key as a u256. Cannot be zero
#[derive(Drop, Copy, Serde, PartialEq)]
struct Secp256r1Signer {
    pubkey: NonZero<u256>
}

/// @notice The Eip191Signer signer conforming to the EIP-191 standard
/// @param eth_address the ethereum address that signed the data 
#[derive(Drop, Copy, PartialEq)]
struct Eip191Signer {
    eth_address: EthAddress
}

/// @notice The webauthn signer
/// @param origin The origin of the request. Cannot be zero
/// @param rp_id_hash The SHA-256 hash of the Relying Party Identifier. Cannot be zero
/// @param pubkey the public key as a u256. Cannot be zero
#[derive(Drop, Copy, Serde, PartialEq)]
struct WebauthnSigner {
    origin: Span<u8>,
    rp_id_hash: NonZero<u256>,
    pubkey: NonZero<u256>
}

// Ensures that the pubkey_hash is not zero as we can't do NonZero<EthAddress>
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

#[generate_trait]
impl SignerTraitImpl of SignerTrait {
    fn into_guid(self: Signer) -> felt252 {
        match self {
            Signer::Starknet(signer) => poseidon_2(STARKNET_SIGNER_TYPE, signer.pubkey.into()),
            Signer::Secp256k1(signer) => poseidon_2(SECP256K1_SIGNER_TYPE, signer.pubkey_hash.address.into()),
            Signer::Secp256r1(signer) => {
                let pubkey: u256 = signer.pubkey.into();
                PoseidonTrait::new().update_with(SECP256R1_SIGNER_TYPE).update_with(pubkey).finalize()
            },
            Signer::Eip191(signer) => poseidon_2(EIP191_SIGNER_TYPE, signer.eth_address.address.into()),
            Signer::Webauthn(signer) => {
                let mut origin = signer.origin;
                let rp_id_hash: u256 = signer.rp_id_hash.into();
                let pubkey: u256 = signer.pubkey.into();
                let mut hash_state = PoseidonTrait::new()
                    .update_with(WEBAUTHN_SIGNER_TYPE)
                    .update_with(signer.origin.len());

                while let Option::Some(byte) = origin.pop_front() {
                    hash_state = hash_state.update_with(*byte);
                };
                hash_state.update_with(rp_id_hash).update_with(pubkey).finalize()
            },
        }
    }

    fn storage_value(self: Signer) -> SignerStorageValue {
        match self {
            Signer::Starknet(signer) => SignerStorageValue {
                signer_type: SignerType::Starknet, stored_value: signer.pubkey.into()
            },
            Signer::Secp256k1(signer) => SignerStorageValue {
                signer_type: SignerType::Secp256k1, stored_value: signer.pubkey_hash.address.try_into().unwrap()
            },
            Signer::Secp256r1 => SignerStorageValue {
                signer_type: SignerType::Secp256r1, stored_value: self.into_guid().try_into().unwrap()
            },
            Signer::Eip191(signer) => SignerStorageValue {
                signer_type: SignerType::Eip191, stored_value: signer.eth_address.address.try_into().unwrap()
            },
            Signer::Webauthn => SignerStorageValue {
                signer_type: SignerType::Webauthn, stored_value: self.into_guid().try_into().unwrap()
            },
        }
    }

    #[inline(always)]
    fn signer_type(self: Signer) -> SignerType {
        match self {
            Signer::Starknet => SignerType::Starknet,
            Signer::Secp256k1 => SignerType::Secp256k1,
            Signer::Secp256r1 => SignerType::Secp256r1,
            Signer::Eip191 => SignerType::Eip191,
            Signer::Webauthn => SignerType::Webauthn,
        }
    }
}

#[generate_trait]
impl SignerStorageValueImpl of SignerStorageTrait {
    fn into_guid(self: SignerStorageValue) -> felt252 {
        match self.signer_type {
            SignerType::Starknet => poseidon_2(STARKNET_SIGNER_TYPE, self.stored_value),
            SignerType::Eip191 => poseidon_2(EIP191_SIGNER_TYPE, self.stored_value),
            SignerType::Secp256k1 => poseidon_2(SECP256K1_SIGNER_TYPE, self.stored_value),
            SignerType::Secp256r1 => self.stored_value,
            SignerType::Webauthn => self.stored_value,
        }
    }

    fn is_stored_as_guid(self: SignerStorageValue) -> bool {
        match self.signer_type {
            SignerType::Starknet => false,
            SignerType::Eip191 => false,
            SignerType::Secp256k1 => false,
            SignerType::Secp256r1 => true,
            SignerType::Webauthn => true,
        }
    }

    #[inline(always)]
    fn starknet_pubkey_or_none(self: SignerStorageValue) -> Option<felt252> {
        match self.signer_type {
            SignerType::Starknet => Option::Some(self.stored_value),
            _ => Option::None,
        }
    }
}

trait SignerSignatureTrait {
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool;
    fn signer(self: SignerSignature) -> Signer;
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
    fn into(self: SignerType) -> felt252 {
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
fn is_valid_secp256k1_signature(hash: u256, signer: Secp256k1Signer, signature: Secp256SignatureEven) -> bool {
    is_eth_signature_valid(hash, signature.into(), signer.pubkey_hash.into()).is_ok()
}

#[inline(always)]
fn is_valid_secp256r1_signature(hash: u256, signer: Secp256r1Signer, signature: Secp256SignatureEven) -> bool {
    // let pubkey_point_1 = Secp256r1Impl::secp256_ec_get_point_from_x_syscall(signer.pubkey.into(), false)
    //             .unwrap_syscall()
    //             .unwrap();
    // let pubkey_point_2 = Secp256r1Impl::secp256_ec_get_point_from_x_syscall(signer.pubkey.into(), true)
    //         .unwrap_syscall()
    //         .unwrap();
    // is_valid_signature::<Secp256r1Point>(hash, signature.r, signature.s, pubkey_point_1) ||  is_valid_signature::<Secp256r1Point>(hash, signature.r, signature.s, pubkey_point_2) 
    let recovered = recover_public_key::<Secp256r1Point>(hash, signature.into()).expect('argent/invalid-sig-format');
    let (recovered_signer, _) = recovered.get_coordinates().expect('argent/invalid-sig-format');
    if (recovered_signer == signer.pubkey.into()) {
        return true;
    }
    (Secp256Trait::<Secp256r1Point>::get_curve_size() - recovered_signer) == signer.pubkey.into()
}

#[inline(always)]
fn is_valid_webauthn_signature(hash: felt252, signer: WebauthnSigner, signature: WebauthnSignature) -> bool {
    verify_authenticator_flags(signature.flags);

    let signed_hash = get_webauthn_hash(hash, signer, signature);
    is_valid_secp256r1_signature(signed_hash, Secp256r1Signer { pubkey: signer.pubkey }, signature.ec_signature)
}

trait SignerSpanTrait {
    #[must_use]
    #[inline(always)]
    fn to_guid_list(self: Span<Signer>) -> Array<felt252>;
}

impl SignerSpanTraitImpl of SignerSpanTrait {
    #[must_use]
    fn to_guid_list(mut self: Span<Signer>) -> Array<felt252> {
        let mut guids = array![];
        while let Option::Some(signer) = self.pop_front() {
            guids.append((*signer).into_guid());
        };
        guids
    }
}

fn assert_sorted_guids(mut guids: Span<felt252>, error_message: felt252) {
    let mut last_guid: u256 = 0;
    while let Option::Some(guid) = guids
        .pop_front() {
            let guid_u256: u256 = (*guid).into();
            assert(guid_u256 > last_guid, error_message);
            last_guid = guid_u256;
        };
}

use argent::signer::eip191::is_valid_eip191_signature;
use argent::signer::webauthn::{WebauthnSignature, get_webauthn_hash, verify_authenticator_flags};
use argent::utils::hashing::poseidon_2;
use core::ecdsa::check_ecdsa_signature;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use starknet::secp256_trait::{
    Secp256PointTrait, Signature as Secp256Signature, is_signature_entry_valid, recover_public_key,
};
use starknet::secp256r1::Secp256r1Point;
use starknet::{EthAddress, eth_signature::is_eth_signature_valid};

/// Magic values used to derive unique GUIDs for each signer type
const STARKNET_SIGNER_TYPE: felt252 = 'Starknet Signer';
const SECP256K1_SIGNER_TYPE: felt252 = 'Secp256k1 Signer';
const SECP256R1_SIGNER_TYPE: felt252 = 'Secp256r1 Signer';
const EIP191_SIGNER_TYPE: felt252 = 'Eip191 Signer';
const WEBAUTHN_SIGNER_TYPE: felt252 = 'Webauthn Signer';

pub const SECP_256_R1_HALF: u256 = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551 / 2;
pub const SECP_256_K1_HALF: u256 = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141 / 2;

/// @notice Supported signer types for account authentication
/// @dev Each type has its own signature validation scheme
#[derive(Drop, Copy, PartialEq, Serde, Default, starknet::Store, Debug)]
pub enum SignerType {
    #[default]
    Starknet,
    Secp256k1,
    Secp256r1,
    Eip191,
    Webauthn,
}

/// @notice Container for a signature and its associated signer
/// @dev Each variant pairs a signer with its corresponding signature type
#[derive(Drop, Copy, Serde)]
pub enum SignerSignature {
    Starknet: (StarknetSigner, StarknetSignature),
    Secp256k1: (Secp256k1Signer, Secp256Signature),
    Secp256r1: (Secp256r1Signer, Secp256Signature),
    Eip191: (Eip191Signer, Secp256Signature),
    Webauthn: (WebauthnSigner, WebauthnSignature),
}

/// @notice The starknet signature using the stark-curve
#[derive(Drop, Copy, Serde)]
pub struct StarknetSignature {
    pub r: felt252,
    pub s: felt252,
}

/// @notice Supported signer types with their data
#[derive(Drop, Copy, Serde, PartialEq)]
pub enum Signer {
    Starknet: StarknetSigner,
    Secp256k1: Secp256k1Signer,
    Secp256r1: Secp256r1Signer,
    Eip191: Eip191Signer,
    Webauthn: WebauthnSigner,
}

/// @notice Storage format for signer data
/// @param stored_value Raw signer data (pubkey, address, or GUID depending on type). Note that only one felt252 is
/// available for storage even if some Signers don't fit in it.
/// @param signer_type Type of the signer determining how stored_value must be interpreted
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store, Default)]
pub struct SignerStorageValue {
    pub stored_value: felt252,
    pub signer_type: SignerType,
}

/// @notice The Starknet signer using the Starknet Curve
/// @param pubkey the public key as felt252 for a starknet signature. Cannot be zero
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct StarknetSigner {
    pub pubkey: NonZero<felt252>,
}

/// @notice The Secp256k1 signer using the Secp256k1 elliptic curve
/// @param pubkey_hash the right-most 160 bits of a Keccak hash of an ECDSA public key
#[derive(Drop, Copy, PartialEq)]
pub struct Secp256k1Signer {
    pub pubkey_hash: EthAddress,
}

/// @notice The Secp256r1 signer using the Secp256r1 elliptic curve
/// @param pubkey the public key as a u256. Cannot be zero
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct Secp256r1Signer {
    pub pubkey: NonZero<u256>,
}

/// @notice The Eip191Signer signer conforming to the EIP-191 standard
/// @param eth_address the ethereum address that signed the data
#[derive(Drop, Copy, PartialEq)]
pub struct Eip191Signer {
    pub eth_address: EthAddress,
}

/// @notice The webauthn signer
/// @param origin The origin of the request.
/// @param rp_id_hash The SHA-256 hash of the Relying Party Identifier. Cannot be zero
/// @param pubkey the public key as a u256. Cannot be zero
#[derive(Drop, Copy, Serde, PartialEq)]
pub struct WebauthnSigner {
    pub origin: Span<u8>,
    pub rp_id_hash: NonZero<u256>,
    pub pubkey: NonZero<u256>,
}

/// @notice Information about a signer stored in the account
/// @param signerType The type of the signer
/// @param guid The guid of the signer
/// @param stored_value Depending on the type it can be a pubkey, a guid or another value. The stored value is unique
/// for each signer type
#[derive(Drop, Copy, PartialEq, Serde, Debug)]
pub struct SignerInfo {
    signerType: SignerType,
    guid: felt252,
    stored_value: felt252,
}

// Ensures that the pubkey_hash is not zero as we can't do NonZero<EthAddress>
impl Secp256k1SignerSerde of Serde<Secp256k1Signer> {
    fn serialize(self: @Secp256k1Signer, ref output: Array<felt252>) {
        self.pubkey_hash.serialize(ref output);
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<Secp256k1Signer> {
        let pubkey_hash = Serde::<EthAddress>::deserialize(ref serialized)?;
        assert(pubkey_hash.into() != 0, 'argent/zero-pubkey-hash');
        Option::Some(Secp256k1Signer { pubkey_hash })
    }
}

impl Eip191SignerSerde of Serde<Eip191Signer> {
    fn serialize(self: @Eip191Signer, ref output: Array<felt252>) {
        self.eth_address.serialize(ref output);
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<Eip191Signer> {
        let eth_address = Serde::<EthAddress>::deserialize(ref serialized)?;
        assert(eth_address.into() != 0, 'argent/zero-eth-EthAddress');
        Option::Some(Eip191Signer { eth_address })
    }
}

pub fn starknet_signer_from_pubkey(pubkey: felt252) -> Signer {
    Signer::Starknet(StarknetSigner { pubkey: pubkey.try_into().expect('argent/zero-pubkey') })
}

#[generate_trait]
pub impl SignerTraitImpl of SignerTrait {
    fn into_guid(self: Signer) -> felt252 {
        match self {
            Signer::Starknet(signer) => poseidon_2(STARKNET_SIGNER_TYPE, signer.pubkey.into()),
            Signer::Secp256k1(signer) => poseidon_2(SECP256K1_SIGNER_TYPE, signer.pubkey_hash.into()),
            Signer::Secp256r1(signer) => {
                let pubkey: u256 = signer.pubkey.into();
                PoseidonTrait::new().update_with(SECP256R1_SIGNER_TYPE).update_with(pubkey).finalize()
            },
            Signer::Eip191(signer) => poseidon_2(EIP191_SIGNER_TYPE, signer.eth_address.into()),
            Signer::Webauthn(signer) => {
                let mut origin = signer.origin;
                let rp_id_hash: u256 = signer.rp_id_hash.into();
                let pubkey: u256 = signer.pubkey.into();
                let mut hash_state = PoseidonTrait::new()
                    .update_with(WEBAUTHN_SIGNER_TYPE)
                    .update_with(signer.origin.len());
                for byte in origin {
                    hash_state = hash_state.update_with(*byte);
                };
                hash_state.update_with(rp_id_hash).update_with(pubkey).finalize()
            },
        }
    }

    #[inline(always)]
    fn storage_value(self: Signer) -> SignerStorageValue {
        match self {
            Signer::Starknet(signer) => SignerStorageValue {
                signer_type: SignerType::Starknet, stored_value: signer.pubkey.into(),
            },
            Signer::Secp256k1(signer) => SignerStorageValue {
                signer_type: SignerType::Secp256k1, stored_value: signer.pubkey_hash.try_into().unwrap(),
            },
            Signer::Secp256r1 => SignerStorageValue {
                signer_type: SignerType::Secp256r1, stored_value: self.into_guid().try_into().unwrap(),
            },
            Signer::Eip191(signer) => SignerStorageValue {
                signer_type: SignerType::Eip191, stored_value: signer.eth_address.try_into().unwrap(),
            },
            Signer::Webauthn => SignerStorageValue {
                signer_type: SignerType::Webauthn, stored_value: self.into_guid().try_into().unwrap(),
            },
        }
    }

    fn signer_type(self: Signer) -> SignerType {
        match self {
            Signer::Starknet => SignerType::Starknet,
            Signer::Secp256k1 => SignerType::Secp256k1,
            Signer::Secp256r1 => SignerType::Secp256r1,
            Signer::Eip191 => SignerType::Eip191,
            Signer::Webauthn => SignerType::Webauthn,
        }
    }

    fn starknet_pubkey_or_none(self: Signer) -> Option<felt252> {
        match self {
            Signer::Starknet(signer) => Option::Some(signer.pubkey.into()),
            _ => Option::None,
        }
    }
}

#[generate_trait]
pub impl SignerStorageValueImpl of SignerStorageTrait {
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

    fn starknet_pubkey_or_none(self: SignerStorageValue) -> Option<felt252> {
        match self.signer_type {
            SignerType::Starknet => Option::Some(self.stored_value),
            _ => Option::None,
        }
    }

    #[must_use]
    fn to_guid_list(mut self: Span<SignerStorageValue>) -> Array<felt252> {
        let mut guids = array![];
        for signer_storage_value in self {
            guids.append((*signer_storage_value).into_guid());
        };
        guids
    }

    #[must_use]
    fn to_signer_info(mut self: Span<SignerStorageValue>) -> Array<SignerInfo> {
        let mut signer_info = array![];
        for signer_storage_value in self {
            signer_info.append((*signer_storage_value).into());
        };
        signer_info
    }
}

pub trait SignerSignatureTrait {
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool;
    fn signer(self: SignerSignature) -> Signer;
}

impl SignerSignatureImpl of SignerSignatureTrait {
    #[inline(always)]
    fn is_valid_signature(self: SignerSignature, hash: felt252) -> bool {
        match self {
            SignerSignature::Starknet((signer, signature)) => is_valid_starknet_signature(hash, signer, signature),
            SignerSignature::Secp256k1((
                signer, signature,
            )) => is_valid_secp256k1_signature(hash.into(), signer.pubkey_hash.into(), signature),
            SignerSignature::Secp256r1((
                signer, signature,
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
            SignerSignature::Webauthn((signer, _)) => Signer::Webauthn(signer),
        }
    }
}

impl SignerTypeIntoFelt252 of Into<SignerType, felt252> {
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
#[must_use]
fn is_valid_starknet_signature(hash: felt252, signer: StarknetSigner, signature: StarknetSignature) -> bool {
    check_ecdsa_signature(hash, signer.pubkey.into(), signature.r, signature.s)
}

#[must_use]
pub fn is_valid_secp256k1_signature(hash: u256, pubkey_hash: EthAddress, signature: Secp256Signature) -> bool {
    assert(signature.s <= SECP_256_K1_HALF, 'argent/malleable-signature');
    is_eth_signature_valid(hash, signature, pubkey_hash).is_ok()
}

#[must_use]
fn is_valid_secp256r1_signature(hash: u256, signer: Secp256r1Signer, signature: Secp256Signature) -> bool {
    // `recover_public_key` accepts invalid values for r and s, so we need to check them first
    assert(is_signature_entry_valid::<Secp256r1Point>(signature.r), 'argent/invalid-r-value');
    assert(is_signature_entry_valid::<Secp256r1Point>(signature.s), 'argent/invalid-s-value');
    assert(signature.s <= SECP_256_R1_HALF, 'argent/malleable-signature');
    let recovered = recover_public_key::<Secp256r1Point>(hash, signature).expect('argent/invalid-sig-format');
    let (recovered_signer, _) = recovered.get_coordinates().expect('argent/invalid-sig-format');
    recovered_signer == signer.pubkey.into()
}

#[must_use]
pub fn is_valid_webauthn_signature(hash: felt252, signer: WebauthnSigner, signature: WebauthnSignature) -> bool {
    verify_authenticator_flags(signature.flags);

    let signed_hash = get_webauthn_hash(hash, signer, signature);
    is_valid_secp256r1_signature(signed_hash, Secp256r1Signer { pubkey: signer.pubkey }, signature.ec_signature)
}

pub trait SignerSpanTrait {
    #[must_use]
    fn to_guid_list(self: Span<Signer>) -> Array<felt252>;
}

impl SignerSpanTraitImpl of SignerSpanTrait {
    #[must_use]
    fn to_guid_list(mut self: Span<Signer>) -> Array<felt252> {
        let mut guids = array![];
        for signer in self {
            guids.append((*signer).into_guid());
        };
        guids
    }
}

impl SignerSignatureIntoSignerInfo of Into<SignerStorageValue, SignerInfo> {
    fn into(self: SignerStorageValue) -> SignerInfo {
        SignerInfo { signerType: self.signer_type, guid: self.into_guid(), stored_value: self.stored_value }
    }
}

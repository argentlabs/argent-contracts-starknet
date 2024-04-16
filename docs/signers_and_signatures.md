# Multiple Signer Types

Starting from argent [account](./argent-account.md) v0.4.0 and [multisig](./multisig.md) v0.2.0, the accounts will allow the use of other signatures types, besides the Starknet native one. We support the following:

- **Starknet**: native starknet key signature, it will be the most efficient in terms of gas usage
- **Secp256k1**: Uses the curve used by Ethereum and other cryptocurrencies
- **Secp256r1**: Curve with broad support, especially on secure hardware
- **Eip191**: Leverages Eip191 signatures to sign on Starknet
- **Webauthn**: Allow to use passkeys as they are widely supported by browsers, and Operating systems

Every time one a new signer is added to the account there will be a `SignerLinked` even emitted, with all the data about the Signer and a GUID, that GUID will uniquely identify that signer in the account. The GUID is a hash of the Signer that will uniquely identify it. The contract won’t always store all the signer data and only the GUID will provided by the contract (there are some exceptions for backwards compatibility)

At any time it will be possible to get the Signer data linked to a GUID, but querying the account SignerLinked events
[Example](../scripts/query-guid-info.ts)

```
/// For every signer in the account there will be SignerLinked event with its guid
struct SignerLinked {
  #[key]
  signer_guid: felt252,
  signer: Signer,
}
```

[More info about signers](../src/signer/signer_signature.cairo)
[More info about Cairo serialization](https://docs.starknet.io/documentation/architecture_and_concepts/Smart_Contracts/serialization_of_Cairo_types/#data_types_of_252_bits_or_less)

## Calculate GUIDs from Signer data

- Starknet:

  `poseidon('Starknet Signer', signer.pubkey)`

- Secp256k1:

  `poseidon('Secp256k1 Signer', signer.pubkey_hash)`

- Secp256r1:

  `poseidon('Secp256r1 Signer', signer.pubkey.low, signer.pubkey.high)`

- Eip191:

  `poseidon('Eip191 Signer', signer.eth_address)`

- Webauthn:

  `poseidon('Webauthn Signer', signer.origin.len(), ...signer.origin, signer.rp_id_hash.low, signer.rp_id_hash.high, signer.pubkey.low, signer.pubkey.high)`

# Signatures

**NOTE** Besides the format specified here, the argent account also supports concise signatures. See [Signatures](./argent_account.md#Signatures)

Signatures are provided as an `Array<SignerSignature>`

```
enum SignerSignature {
  Starknet: (StarknetSigner, StarknetSignature),
  Secp256k1: (Secp256k1Signer, Secp256k1Signature),
  Secp256r1: (Secp256r1Signer, Secp256r1Signature),
  Eip191: (Eip191Signer, Secp256r1Signature),
  Webauthn: (WebauthnSigner, WebauthnAssertion),
}
```

[More details about each type](../src/signer/signer_signature.cairo)

Here is an example of a signature with two starknet signers

```
0x000002 // number of signatures in the array

0x000000 // 1st signature type (Starknet)
0xAAAAAA // signer_1 pubkey
0xAAA001 // signer_1 signature r
0xAAA002 // signer_1 signature s

0x000000 // 2nd signature type (Starknet)
0xBBBBBB // signer_2 pubkey
0xBBB001 // signer_2 signature r
0xBBB002 // signer_2 signature s
```

[More info about Cairo serialization](https://docs.starknet.io/documentation/architecture_and_concepts/Smart_Contracts/serialization_of_Cairo_types/#data_types_of_252_bits_or_less)

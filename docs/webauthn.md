# WebAuthn Signer

WebAuthn is a standard implemented by most modern browsers and operating systems. It allows user authentication by leveraging the available device's built-in security features like fingerprint sensors, facial recognition, or hardware security keys. It can often provide a better user experience and higher security.

WebAuthn signatures are more expensive to validate than regular signatures.

## The Signer

A WebAuthn Signer is defined by the following data:

```rust
struct WebauthnSigner {
    origin: Span<u8>,
    rp_id_hash: u256,
    pubkey: u256
}
```

- `origin`: Typically the website domain or app origin. [More info](https://www.w3.org/TR/webauthn/). Represented as an array of bytes.
- `rp_id_hash`: SHA-256 hash of the RP ID. The Relying Party ID is based on a host's domain name. It does not itself include a scheme or port, as an origin does (RP ID). [More info](https://www.w3.org/TR/webauthn/#relying-party-identifier)
- `pubkey`: The **Secp256r1** public key used for signatures.

## The Signature

The client will request the authenticator to create a signature, the client will provide the data to sign (usually a transaction hash) as the webauthn **challenge**.

The actual signature includes the following data

```rust
struct WebauthnSignature {
    pub client_data_json_outro: Span<u8>,
    pub flags: u8,
    pub sign_count: u32,
    pub ec_signature: Signature,
}
```

- `client_data_json_outro`:
  The authenticator builds a **Client Data JSON** with values as defined in the [spec](https://www.w3.org/TR/webauthn/#dictdef-collectedclientdata). Note that unlike other JSON the serialization of these values is deterministic and defined by the [serialization spec](https://www.w3.org/TR/webauthn/#clientdatajson-verification), which among other things determines the order of the members

  Here is example of this JSON:

  ```json
  { "type": "webauthn.get", "challenge": "3q2-7_8", "origin": "http://argent.xyz", "crossOrigin": false }
  ```

  The wallet building the account signature, must take the json payload and split it after the "origin" value (after the last `"` character enclosing the value).

  Then check that the part before matches the expected JSON, and the rest will be submitted in the signature as the `client_data_json_outro`.

  If the remaining data is just the `}` character, the `client_data_json_outro` should be empty

- `flags`:

  This field includes the "flags" (1 byte) from the _[Authenticator Data](https://www.w3.org/TR/webauthn/#sctn-authenticator-data)_ returned by the authenticator
  The contract will require that the [User Present](https://www.w3.org/TR/webauthn/#concept-user-present) and the [User Verified](https://www.w3.org/TR/webauthn/#concept-user-verified) bits are set

- `sign_count`:

  This field includes the "sigCount" (4 byte) from the _[Authenticator Data](https://www.w3.org/TR/webauthn/#sctn-authenticator-data)_ returned by the authenticator

- `ec_signature`:

  A normalized secp256 r1 elliptic curve signature as

  ```rust
  struct {
    r: u256,
    s: u256,
    y_parity: bool
  }
  ```

## History

There are two changes that make the signatures starting in the account v0.5.0 and the multisig v0.3.0 incompatible.

Although, signers added before those versions are still usable, they just need to generate new signatures according to the new format

- **Challenge** to sign:

  The challenge to sign used to be a felt252 (converted to a u256) concatenated with the byte defining the implementation to use for SHA-256, 0x0 meaning Cairo0, and 0x1 using Cairo 1

  In the latest version the challenge to encode is just the felt252 converted to a u256 without any extra data.

- **`WebAuthnSignature`** struct

  Used to have this format

  ```rust
  struct WebauthnSignature {
      cross_origin: bool,
      client_data_json_outro: Span<u8>,
      flags: u8,
      sign_count: u32,
      ec_signature: Signature,
      sha256_implementation: Sha256Implementation,
  }
  ```

  Notice that the `cross_origin` field is removed, this information is now included in the `client_data_json_outro` which now expects all the characters after the "origin" value in the client data JSON

  `sha256_implementation` was also removed as the option to use Cairo 0 for validation was removed.

## Examples

There are some examples in typescript about how to use this feature [here](../lib/signers/webauthn.ts)

There is a proof of concept dapp [here](../examples/webauthn/)

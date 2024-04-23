use argent::signer::signer_signature::{WebauthnSigner};
use argent::signer::webauthn::{WebauthnAssertion, AuthenticatorData, Sha256Implementation};
use argent::utils::array_ext::ArrayExtTrait;
use argent::utils::bytes::{ByteArrayExt, SpanU8TryIntoFelt252, u256_to_u8s};
use starknet::secp256_trait::Signature;

fn new_webauthn_signer(origin: ByteArray, rp_id_hash: u256, pubkey: u256) -> WebauthnSigner {
    let origin = origin.into_bytes().span();
    let rp_id_hash = rp_id_hash.try_into().expect('argent/zero-rp-id-hash');
    let pubkey = pubkey.try_into().expect('argent/zero-pubkey');
    WebauthnSigner { origin, rp_id_hash, pubkey }
}

fn localhost_rp() -> (ByteArray, u256) {
    let origin = "http://localhost:5173";
    let rp_id_hash = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763;
    (origin, rp_id_hash)
}

fn setup_1() -> (felt252, WebauthnSigner, WebauthnAssertion) {
    let (origin, rp_id_hash) = localhost_rp();

    let transaction_hash = 0x06fd6673287ba2e4d2975ad878dc26c0a989c549259d87a044a8d37bb9168bb4;
    let pubkey = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    let signer = new_webauthn_signer(:origin, :rp_id_hash, :pubkey);
    let assertion = WebauthnAssertion {
        authenticator_data: AuthenticatorData { rp_id_hash, flags: 0b101, sign_count: 0 },
        cross_origin: false,
        client_data_json_outro: array![].span(),
        sha256_implementation: Sha256Implementation::Cairo1,
        signature: Signature {
            r: 17964448168501796902021058754052023747843800978633577064976152434953556917106,
            s: 24325385074589667029100892281776352749061721889898781064305922798414532583201,
            y_parity: true,
        },
    };
    (transaction_hash, signer, assertion)
}

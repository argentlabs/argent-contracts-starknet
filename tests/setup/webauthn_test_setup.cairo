use argent::common::bytes::ByteArrayExt;
use argent::common::signer_signature::WebauthnSigner;
use argent::common::webauthn::{WebauthnAssertion};
use starknet::secp256_trait::Signature;

fn get_authenticator_data() -> Span<u8> {
    // rp id hash = 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763
    // flags (binary) = 101
    // sign count = 0
    array![
        73,
        150,
        13,
        229,
        136,
        14,
        140,
        104,
        116,
        52,
        23,
        15,
        100,
        118,
        96,
        91,
        143,
        228,
        174,
        185,
        162,
        134,
        50,
        199,
        153,
        92,
        243,
        186,
        131,
        29,
        151,
        99,
        5,
        0,
        0,
        0,
        0
    ]
        .span()
}

fn setup_1() -> (felt252, WebauthnSigner, WebauthnAssertion) {
    let signer = WebauthnSigner {
        pubkey: 0x90fa3f868e09db8d7103e1302d8a7aea214a31064b50bbd2545107799d513b25,
        origin: 'http://localhost:5173',
        rp_id_hash: 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763
    };
    let assertion = WebauthnAssertion {
        authenticator_data: get_authenticator_data(),
        // challenge = 0xdeadbeef (4 bytes)
        client_data_json: "{\"type\":\"webauthn.get\",\"challenge\":\"3q2-7w\",\"origin\":\"http://localhost:5173\",\"crossOrigin\":false}"
            .into_bytes()
            .span(),
        signature: Signature {
            r: 0xecef916550e308e2bcb9296730a3fd1e70f4f33599b4fce11727a445b1a63002,
            s: 0xe67a75ea5838c111f7f2e368d87bdc05526611459992d1951c5405b385dbc00d,
            y_parity: false,
        },
        // message hash = 0xfe25e8cd90bedbd3e0a00b1c7d3219e38c1e23823f0d62ca75acaff627bef411
        type_offset: 9,
        challenge_offset: 36,
        challenge_length: 6,
        origin_offset: 54,
        origin_length: 21,
    };
    let challenge = 0xdeadbeef;
    (challenge, signer, assertion)
}

fn setup_2() -> (felt252, WebauthnSigner, WebauthnAssertion) {
    let signer = WebauthnSigner {
        pubkey: 0x948947bb01aa6bc60a10b0f84f17ce580bf824b904c85381df122fbf64674dbb,
        origin: 'http://localhost:5173',
        rp_id_hash: 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763
    };
    let assertion = WebauthnAssertion {
        authenticator_data: get_authenticator_data(),
        // challenge = 0xdeadbeefff (5 bytes)
        client_data_json: "{\"type\":\"webauthn.get\",\"challenge\":\"3q2-7_8\",\"origin\":\"http://localhost:5173\",\"crossOrigin\":false}"
            .into_bytes()
            .span(),
        signature: Signature {
            r: 0xb96c53a76f75cbec090e619ad2dc5e03aed517eb993c0104870550ac04350e39,
            s: 0x1f9c7f626e649d19e707a85ad33f14fcd1105f78cc9216e32b2ea1b88dd75f7b,
            y_parity: false,
        },
        // message hash = 0x88cf4d2b87184ee6e595373809b8dc83022187b6792cd6d2dff1d3ecc7c14dcc
        type_offset: 9,
        challenge_offset: 36,
        challenge_length: 7,
        origin_offset: 55,
        origin_length: 21,
    };
    let challenge = 0xdeadbeefff;
    (challenge, signer, assertion)
}

fn setup_3() -> (felt252, WebauthnSigner, WebauthnAssertion) {
    let signer = WebauthnSigner {
        pubkey: 0xe7e2601548d428b0746936f84034a9869221bb994f8e6dc71953088aa9229bd7,
        origin: 'http://localhost:5173',
        rp_id_hash: 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763
    };
    let assertion = WebauthnAssertion {
        authenticator_data: get_authenticator_data(),
        client_data_json: "{\"type\":\"webauthn.get\",\"challenge\":\"3q2-7_-q\",\"origin\":\"http://localhost:5173\",\"crossOrigin\":false,\"other_keys_can_be_added_here\":\"do not compare clientDataJSON against a template. See https://goo.gl/yabPex\"}"
            .into_bytes()
            .span(),
        // challenge = 0xdeadbeefffaa (6 bytes)
        signature: Signature {
            r: 0xd6d9158a417e8ca79ca910843acda073775f3f4c39ce81c2ce14533d5890a57a,
            s: 0xaacbb23b8f5e828f14988e2747755e95afcc4b221cefb18314292ccf3edaadf7,
            y_parity: false,
        },
        // message hash = 0x8b17cd9d759c752ec650f5db242c5a74f6af5a3a95f9d23efc991411a4c661c6
        type_offset: 9,
        challenge_offset: 36,
        challenge_length: 8,
        origin_offset: 56,
        origin_length: 21,
    };
    let challenge = 0xdeadbeefffaa;
    (challenge, signer, assertion)
}

fn setup_4() -> (felt252, WebauthnSigner, WebauthnAssertion) {
    let signer = WebauthnSigner {
        pubkey: 0x03bac39ba002c54f77a81b211af863646927e7758032ff255a3aa48aa332602b,
        origin: 'http://localhost:5173',
        rp_id_hash: 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763
    };
    let assertion = WebauthnAssertion {
        authenticator_data: get_authenticator_data(),
        client_data_json: "{\"type\":\"webauthn.get\",\"challenge\":\"3q2-777vuw\",\"origin\":\"http://localhost:5173\",\"crossOrigin\":false}"
            .into_bytes()
            .span(),
        // challenge = 0xdeadbeefbeefbb (7 bytes)
        signature: Signature {
            r: 0xf3c9b06dd6d7e21c5c571a060b54928c0f5834e87ec0802cdcddd7f771975eba,
            s: 0x8ec722c0443b439f15a3efd14c8d97d52c255324e80e6a313f8e050f462263a7,
            y_parity: true,
        },
        // message hash = 0x00bef3a153c28c1d3356317de7cda51efbc4ae47c71204d525a24af454eeb417
        type_offset: 9,
        challenge_offset: 36,
        challenge_length: 10,
        origin_offset: 58,
        origin_length: 21,
    };
    let challenge = 0xdeadbeefbeefbb;
    (challenge, signer, assertion)
}

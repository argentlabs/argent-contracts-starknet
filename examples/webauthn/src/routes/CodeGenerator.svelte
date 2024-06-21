<script lang="ts">
  import type { WebauthnAttestation } from "$lib/webauthnAttestation";
  import type { IAssertion } from "$lib/webauthnOwner";
  import { buf2hex, buf2base64url, base64url2buf } from "$lib/bytes";

  export let account: WebauthnAttestation;
  export let assertions: IAssertion[];

  const { x, y } = account;
  const { r, s, yParity, messageHash, authenticatorData, clientDataJSON } = assertions[0];
  const clientDataText = new TextDecoder().decode(clientDataJSON.buffer);
  const clientData = JSON.parse(clientDataText);
  const clientDataOffset = (substring: string) => clientDataText.indexOf(substring) + substring.length;
  const challenge = base64url2buf(clientData.challenge);

  const pythonCode = `
# Python

x = '${buf2hex(x, false)}'
y = '${buf2hex(y, false)}'
r = '${buf2hex(r, false)}'
s = '${buf2hex(s, false)}'
message_hash = '${buf2hex(messageHash, false)}'
`;

  const jsCode = `
# JS

const publicKey = '${buf2hex(account.x)}';
const { account } = await deployWebauthnAccount(accountClassHash, publicKey);

const assertion = {
  authenticator_data: '${buf2base64url(authenticatorData)}',
  // rp id hash = ${buf2hex(authenticatorData.slice(0, 32))}
  // flags (binary) = ${authenticatorData[32].toString(2)}
  // sign count = ${BigInt(buf2hex(authenticatorData.slice(33, 37)))}
  client_data_json: '${buf2base64url(clientDataJSON)}',
  // ${clientDataText}
  // challenge = ${buf2hex(challenge)} (${challenge.byteLength} bytes)
  signature_r: '${buf2hex(r)}',
  signature_s: '${buf2hex(s)}',
  signature_y_parity: ${yParity},
  type_offset: ${clientDataOffset('"type":"')},
  challenge_offset: ${clientDataOffset('"challenge":"')},
  challenge_length: ${clientData.challenge.length},
  origin_offset: ${clientDataOffset('"origin":"')},
  origin_length: ${clientData.origin.length},
}
`;

  const cairoVerificationTest = `
// Cairo verification test

#[test]
#[available_gas(10_000_000_000)]
fn webauthn_verify_assertion() {
    let assertion = Assertion {
        authenticator_data: get_authenticator_data(),
        // rp id hash = ${buf2hex(authenticatorData.slice(0, 32))}
        // flags (binary) = ${authenticatorData[32].toString(2)}
        // sign count = ${BigInt(buf2hex(authenticatorData.slice(33, 37)))}
        client_data_json: get_client_data_json(),
        // ${clientDataText}
        // challenge = ${buf2hex(challenge)} (${challenge.byteLength} bytes)
        signature_r: ${buf2hex(r)},
        signature_s: ${buf2hex(s)},
        signature_y_parity: ${yParity},
        // message hash = ${buf2hex(messageHash)}
        type_offset: ${clientDataOffset('"type":"')},
        challenge_offset: ${clientDataOffset('"challenge":"')},
        challenge_length: ${clientData.challenge.length},
        origin_offset: ${clientDataOffset('"origin":"')},
        origin_length: ${clientData.origin.length},
    };

    verify_assertion(
        :assertion,
        owner: ${buf2hex(x)}_u256.low.into(),
        expected_challenge: ${buf2hex(challenge)},
        expected_origin: '${clientData.origin}',
        expected_rp_id_hash: 0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763,
    );
}

fn get_authenticator_data() -> Array<u8> {
    array![${Array.from(authenticatorData)
      .map((x) => `${x}`)
      .join(", ")}]
}

fn get_client_data_json() -> Array<u8> {
    array![${clientDataText
      .split("")
      .map((x) => `'${x}'`)
      .join(", ")}]
}
`;

  let cairoSignatureTests = "";
  if (assertions.length > 1) {
    cairoSignatureTests = assertions
      .map(
        ({ r, s, yParity, messageHash }, i) => `
#[test]
#[available_gas(100_000_000)]
fn test_recover_public_key_r1_${i}() {
    let x: u256 = ${buf2hex(x)};
    let y: u256 = ${buf2hex(y)};
    let r: u256 = ${buf2hex(r)};
    let s: u256 = ${buf2hex(s)};
    let y_parity = ${yParity};
    let message_hash: u256 = ${buf2hex(messageHash)};
    let is_valid = check_secp256r1_signature(message_hash, x.low.into(), r, s, y_parity);
    assert(is_valid, 'Signature is not valid');
}`,
      )
      .join("\n");
  }

  const code = [pythonCode, jsCode, cairoVerificationTest, cairoSignatureTests].join("\n");
</script>

<div class="code">
  <pre>{code}</pre>
</div>

<style>
  .code {
    display: inline-block;
    text-align: left;
    padding: 0 1rem;
  }
</style>

import {
  Account,
  ArraySignatureType,
  CairoCustomEnum,
  CairoOption,
  CairoOptionVariant,
  CallData,
  hash,
  uint256,
} from "starknet";
import { RawSigner, fundAccount, provider } from "..";

const buf2hex = (buffer: ArrayBuffer, prefix = true) =>
  `${prefix ? "0x" : ""}${[...new Uint8Array(buffer)].map((x) => x.toString(16).padStart(2, "0")).join("")}`;

const rpIdHash: string = buf2hex(
  new Uint8Array([
    73, 150, 13, 229, 136, 14, 140, 104, 116, 52, 23, 15, 100, 118, 96, 91, 143, 228, 174, 185, 162, 134, 50, 199, 153,
    92, 243, 186, 131, 29, 151, 99,
  ]),
);

interface WebauthnAssertion {
  authenticatorData: Uint8Array;
  clientDataJson: Uint8Array;
  r: Uint8Array;
  s: Uint8Array;
  yParity: boolean;
}

let firstPass = true;
const origin = "http://localhost:5173";
const pubkey = buf2hex(
  new Uint8Array([
    121, 231, 224, 51, 127, 167, 96, 95, 57, 249, 250, 53, 136, 126, 36, 208, 37, 216, 34, 127, 163, 34, 170, 150, 151,
    6, 246, 46, 5, 253, 205, 68,
  ]),
);

export async function deployFixedWebauthnAccount(classHash: string): Promise<Account> {
  const constructorCalldata = CallData.compile({
    owner: webauthnSigner(origin, rpIdHash, pubkey),
    guardian: new CairoOption(CairoOptionVariant.None),
  });
  const addressSalt = 12n;
  const accountAddress = hash.calculateContractAddressFromHash(addressSalt, classHash, constructorCalldata, 0);

  await fundAccount(accountAddress, 1e16, "ETH");

  const account = new Account(provider, accountAddress, webauthnOwner, "1");
  const response = await account.deploySelf({ classHash, constructorCalldata, addressSalt }, { maxFee: 1e15 });
  await provider.waitForTransaction(response.transaction_hash);

  return account;
}

class WebauthnOwner extends RawSigner {
  public async signRaw(): Promise<ArraySignatureType> {
    const { authenticatorData, clientDataJson, r, s, yParity } = await signTransaction();
    const clientDataText = new TextDecoder().decode(clientDataJson.buffer);
    const clientData = JSON.parse(clientDataText);
    const clientDataOffset = (substring: string) => clientDataText.indexOf(substring) + substring.length;

    const cairoAssertion = {
      origin,
      rp_id_hash: uint256.bnToUint256(rpIdHash),
      pubkey: uint256.bnToUint256(pubkey),
      authenticator_data: CallData.compile(Array.from(authenticatorData)),
      client_data_json: CallData.compile(Array.from(clientDataJson)),
      signature: {
        r: uint256.bnToUint256(buf2hex(r)),
        s: uint256.bnToUint256(buf2hex(s)),
        y_parity: yParity,
      },
      type_offset: clientDataOffset('"type":"'),
      challenge_offset: clientDataOffset('"challenge":"'),
      challenge_length: clientData.challenge.length,
      origin_offset: clientDataOffset('"origin":"'),
      origin_length: clientData.origin.length,
    };

    return CallData.compile([
      [
        new CairoCustomEnum({
          Starknet: undefined,
          Secp256k1: undefined,
          Secp256r1: undefined,
          Webauthn: cairoAssertion,
        }),
      ],
    ]);
  }
}

const webauthnOwner = new WebauthnOwner();

function webauthnSigner(origin: string, rp_id_hash: string, pubkey: string) {
  return new CairoCustomEnum({
    Starknet: undefined,
    Secp256k1: undefined,
    Secp256r1: undefined,
    Webauthn: {
      origin,
      rp_id_hash: uint256.bnToUint256(rp_id_hash),
      pubkey: uint256.bnToUint256(pubkey),
    },
  });
}

async function signTransaction(): Promise<WebauthnAssertion> {
  if (firstPass) {
    firstPass = false;

    return {
      authenticatorData: new Uint8Array([
        73, 150, 13, 229, 136, 14, 140, 104, 116, 52, 23, 15, 100, 118, 96, 91, 143, 228, 174, 185, 162, 134, 50, 199,
        153, 92, 243, 186, 131, 29, 151, 99, 5, 0, 0, 0, 0,
      ]),
      clientDataJson: new Uint8Array([
        123, 34, 116, 121, 112, 101, 34, 58, 34, 119, 101, 98, 97, 117, 116, 104, 110, 46, 103, 101, 116, 34, 44, 34,
        99, 104, 97, 108, 108, 101, 110, 103, 101, 34, 58, 34, 66, 80, 65, 73, 52, 51, 65, 52, 116, 51, 85, 86, 121, 88,
        76, 108, 106, 117, 95, 111, 121, 52, 78, 81, 77, 88, 51, 122, 48, 52, 120, 75, 111, 69, 85, 122, 71, 70, 45,
        114, 57, 112, 111, 34, 44, 34, 111, 114, 105, 103, 105, 110, 34, 58, 34, 104, 116, 116, 112, 58, 47, 47, 108,
        111, 99, 97, 108, 104, 111, 115, 116, 58, 53, 49, 55, 51, 34, 44, 34, 99, 114, 111, 115, 115, 79, 114, 105, 103,
        105, 110, 34, 58, 102, 97, 108, 115, 101, 125,
      ]),
      r: new Uint8Array([
        82, 203, 168, 180, 232, 205, 247, 215, 126, 231, 223, 31, 52, 174, 42, 225, 114, 101, 138, 67, 18, 146, 215,
        198, 206, 222, 15, 25, 63, 232, 152, 214,
      ]),
      s: new Uint8Array([
        18, 213, 61, 109, 112, 236, 28, 178, 151, 232, 114, 21, 142, 5, 126, 51, 112, 216, 193, 20, 187, 29, 197, 72,
        158, 79, 64, 235, 122, 109, 152, 229,
      ]),
      yParity: true,
    };
  } else {
    return {
      authenticatorData: new Uint8Array([
        73, 150, 13, 229, 136, 14, 140, 104, 116, 52, 23, 15, 100, 118, 96, 91, 143, 228, 174, 185, 162, 134, 50, 199,
        153, 92, 243, 186, 131, 29, 151, 99, 5, 0, 0, 0, 0,
      ]),
      clientDataJson: new Uint8Array([
        123, 34, 116, 121, 112, 101, 34, 58, 34, 119, 101, 98, 97, 117, 116, 104, 110, 46, 103, 101, 116, 34, 44, 34,
        99, 104, 97, 108, 108, 101, 110, 103, 101, 34, 58, 34, 65, 86, 85, 48, 72, 119, 67, 70, 71, 86, 70, 49, 120,
        108, 109, 90, 115, 73, 104, 90, 109, 78, 104, 72, 56, 104, 69, 110, 66, 50, 77, 104, 50, 77, 88, 73, 84, 121,
        68, 89, 68, 95, 73, 34, 44, 34, 111, 114, 105, 103, 105, 110, 34, 58, 34, 104, 116, 116, 112, 58, 47, 47, 108,
        111, 99, 97, 108, 104, 111, 115, 116, 58, 53, 49, 55, 51, 34, 44, 34, 99, 114, 111, 115, 115, 79, 114, 105, 103,
        105, 110, 34, 58, 102, 97, 108, 115, 101, 125,
      ]),
      r: new Uint8Array([
        133, 59, 200, 93, 139, 18, 54, 216, 236, 147, 133, 213, 201, 65, 181, 124, 155, 158, 131, 184, 20, 220, 115, 58,
        162, 235, 232, 92, 11, 21, 250, 113,
      ]),
      s: new Uint8Array([
        237, 136, 79, 80, 48, 31, 134, 89, 110, 36, 236, 44, 251, 253, 156, 75, 42, 188, 126, 241, 22, 179, 254, 238,
        131, 184, 71, 97, 30, 206, 9, 188,
      ]),
      yParity: true,
    };
  }
}

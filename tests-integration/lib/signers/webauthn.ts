import {
  Abi,
  Account,
  ArraySignatureType,
  CairoCustomEnum,
  CairoOption,
  CairoOptionVariant,
  Call,
  CallData,
  Signature,
  SignerInterface,
  V2DeclareSignerDetails,
  V2DeployAccountSignerDetails,
  V2InvocationsSignerDetails,
  hash,
  transaction,
  typedData,
  uint256,
} from "starknet";
import { fundAccount, provider } from "..";

const buf2hex = (buffer: ArrayBuffer, prefix = true) =>
  `${prefix ? "0x" : ""}${[...new Uint8Array(buffer)].map((x) => x.toString(16).padStart(2, "0")).join("")}`;

const rpIdHash: string = buf2hex(new Uint8Array([
  73, 150, 13, 229, 136, 14, 140, 104, 116, 52, 23, 15, 100, 118, 96, 91, 143, 228, 174, 185, 162, 134, 50, 199, 153,
  92, 243, 186, 131, 29, 151, 99,
]));

interface WebauthnAttestation {
  email: string;
  rpId: string;
  credentialId: Uint8Array;
  x: Uint8Array;
  y: Uint8Array;
}

interface WebauthnAssertion {
  authenticatorData: Uint8Array;
  clientDataJSON: Uint8Array;
  r: Uint8Array;
  s: Uint8Array;
  yParity: boolean;
}

let firstPass = true;

const origin = "http://localhost:5173";

const attestation = {
  email: "axel@argent.xyz",
  rpId: "localhost",
  credentialId: new Uint8Array([
    192, 249, 188, 136, 177, 247, 200, 17, 50, 91, 146, 20, 183, 251, 82, 196, 18, 98, 13, 24, 51, 16, 14, 114, 178,
    211, 111, 67, 103, 51, 8, 248,
  ]),
  x: new Uint8Array([
    46, 159, 209, 182, 176, 149, 169, 127, 113, 209, 4, 16, 168, 36, 95, 120, 80, 91, 75, 116, 255, 147, 226, 134, 140,
    165, 174, 224, 46, 166, 106, 155,
  ]),
  y: new Uint8Array([
    119, 151, 21, 18, 129, 196, 15, 139, 136, 127, 133, 106, 135, 185, 122, 183, 196, 5, 55, 132, 101, 85, 114, 130,
    152, 255, 19, 103, 155, 236, 95, 103,
  ]),
};

export async function deployFixedWebauthnAccount(classHash: string): Promise<Account> {
  const constructorCalldata = CallData.compile({
    owner: webauthnSigner(origin, rpIdHash, buf2hex(attestation.x)),
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

abstract class RawSigner implements SignerInterface {
  abstract signRaw(messageHash: string): Promise<Signature>;

  public async getPubKey(): Promise<string> {
    throw Error("This signer allows multiple public keys");
  }

  public async signMessage(typedDataArgument: typedData.TypedData, accountAddress: string): Promise<Signature> {
    const messageHash = typedData.getMessageHash(typedDataArgument, accountAddress);
    return this.signRaw(messageHash);
  }

  public async signTransaction(
    transactions: Call[],
    transactionsDetail: V2InvocationsSignerDetails,
    abis?: Abi[],
  ): Promise<Signature> {
    if (abis && abis.length !== transactions.length) {
      throw new Error("ABI must be provided for each transaction or no transaction");
    }
    // now use abi to display decoded data somewhere, but as this signer is headless, we can't do that
    const compiledCalldata = transaction.getExecuteCalldata(transactions, transactionsDetail.cairoVersion);
    const messageHash = hash.calculateInvokeTransactionHash({
      senderAddress: transactionsDetail.walletAddress,
      compiledCalldata,
      ...transactionsDetail,
    });

    return this.signRaw(messageHash);
  }

  public async signDeployAccountTransaction({
    classHash,
    contractAddress,
    constructorCalldata,
    addressSalt,
    maxFee,
    version,
    chainId,
    nonce,
  }: V2DeployAccountSignerDetails) {
    const messageHash = hash.calculateDeployAccountTransactionHash({
      contractAddress,
      classHash,
      constructorCalldata: CallData.compile(constructorCalldata),
      salt: BigInt(addressSalt),
      version: version,
      maxFee,
      chainId,
      nonce,
    });

    return this.signRaw(messageHash);
  }

  public async signDeclareTransaction(transaction: V2DeclareSignerDetails) {
    const messageHash = hash.calculateDeclareTransactionHash(transaction);
    return this.signRaw(messageHash);
  }
}

class WebauthnOwner extends RawSigner {
  constructor(public attestation: WebauthnAttestation) {
    super();
  }

  public async signRaw(): Promise<ArraySignatureType> {
    const { authenticatorData, clientDataJSON, r, s, yParity } = await signTransaction();
    const clientDataText = new TextDecoder().decode(clientDataJSON.buffer);
    const clientData = JSON.parse(clientDataText);
    const clientDataOffset = (substring: string) => clientDataText.indexOf(substring) + substring.length;

    const cairoAssertion = {
      origin,
      rp_id_hash: uint256.bnToUint256(rpIdHash),
      pubkey: uint256.bnToUint256(buf2hex(this.attestation.x)),
      authenticator_data: CallData.compile(Array.from(authenticatorData)),
      client_data_json: CallData.compile(Array.from(clientDataJSON)),
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

const webauthnOwner = new WebauthnOwner(attestation);

function webauthnSigner(origin: string, rp_id_hash: string, pubkey: string) {
  return new CairoCustomEnum({
    Starknet: undefined,
    Secp256k1: undefined,
    Secp256r1: undefined,
    Webauthn: {
      origin,
      rp_id_hash: uint256.bnToUint256(BigInt(rp_id_hash)),
      pubkey: uint256.bnToUint256(BigInt(pubkey)),
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
      clientDataJSON: new Uint8Array([
        123, 34, 116, 121, 112, 101, 34, 58, 34, 119, 101, 98, 97, 117, 116, 104, 110, 46, 103, 101, 116, 34, 44, 34,
        99, 104, 97, 108, 108, 101, 110, 103, 101, 34, 58, 34, 65, 85, 45, 119, 106, 81, 87, 45, 86, 50, 73, 80, 57, 57,
        80, 83, 84, 98, 80, 100, 97, 97, 115, 51, 90, 85, 67, 82, 67, 90, 54, 102, 87, 111, 111, 104, 83, 117, 70, 82,
        73, 95, 119, 34, 44, 34, 111, 114, 105, 103, 105, 110, 34, 58, 34, 104, 116, 116, 112, 58, 47, 47, 108, 111, 99,
        97, 108, 104, 111, 115, 116, 58, 53, 49, 55, 51, 34, 44, 34, 99, 114, 111, 115, 115, 79, 114, 105, 103, 105,
        110, 34, 58, 102, 97, 108, 115, 101, 125,
      ]),
      r: new Uint8Array([
        119, 200, 46, 229, 212, 223, 166, 76, 226, 3, 65, 190, 5, 125, 207, 63, 23, 235, 200, 90, 26, 180, 107, 142, 22,
        65, 65, 86, 235, 194, 161, 129,
      ]),
      s: new Uint8Array([
        142, 60, 121, 121, 241, 110, 131, 220, 120, 26, 41, 107, 204, 137, 41, 242, 184, 8, 230, 151, 119, 219, 64, 189,
        29, 142, 77, 176, 28, 21, 40, 80,
      ]),
      yParity: true,
    };
  } else {
    return {
      authenticatorData: new Uint8Array([
        73, 150, 13, 229, 136, 14, 140, 104, 116, 52, 23, 15, 100, 118, 96, 91, 143, 228, 174, 185, 162, 134, 50, 199,
        153, 92, 243, 186, 131, 29, 151, 99, 5, 0, 0, 0, 0,
      ]),
      clientDataJSON: new Uint8Array([
        123, 34, 116, 121, 112, 101, 34, 58, 34, 119, 101, 98, 97, 117, 116, 104, 110, 46, 103, 101, 116, 34, 44, 34,
        99, 104, 97, 108, 108, 101, 110, 103, 101, 34, 58, 34, 66, 111, 95, 79, 111, 114, 71, 45, 103, 112, 111, 84, 73,
        90, 112, 85, 81, 109, 51, 51, 51, 114, 56, 118, 116, 116, 88, 68, 107, 88, 71, 106, 69, 77, 66, 108, 74, 103,
        76, 48, 122, 86, 103, 34, 44, 34, 111, 114, 105, 103, 105, 110, 34, 58, 34, 104, 116, 116, 112, 58, 47, 47, 108,
        111, 99, 97, 108, 104, 111, 115, 116, 58, 53, 49, 55, 51, 34, 44, 34, 99, 114, 111, 115, 115, 79, 114, 105, 103,
        105, 110, 34, 58, 102, 97, 108, 115, 101, 44, 34, 111, 116, 104, 101, 114, 95, 107, 101, 121, 115, 95, 99, 97,
        110, 95, 98, 101, 95, 97, 100, 100, 101, 100, 95, 104, 101, 114, 101, 34, 58, 34, 100, 111, 32, 110, 111, 116,
        32, 99, 111, 109, 112, 97, 114, 101, 32, 99, 108, 105, 101, 110, 116, 68, 97, 116, 97, 74, 83, 79, 78, 32, 97,
        103, 97, 105, 110, 115, 116, 32, 97, 32, 116, 101, 109, 112, 108, 97, 116, 101, 46, 32, 83, 101, 101, 32, 104,
        116, 116, 112, 115, 58, 47, 47, 103, 111, 111, 46, 103, 108, 47, 121, 97, 98, 80, 101, 120, 34, 125,
      ]),
      r: new Uint8Array([
        152, 215, 56, 138, 13, 123, 157, 99, 243, 247, 160, 210, 254, 110, 118, 121, 158, 145, 206, 92, 46, 251, 98,
        142, 194, 126, 135, 202, 78, 113, 195, 187,
      ]),
      s: new Uint8Array([
        132, 178, 88, 102, 167, 211, 151, 215, 89, 150, 50, 20, 63, 206, 5, 135, 192, 17, 106, 133, 79, 38, 157, 45,
        111, 255, 116, 232, 178, 0, 40, 72,
      ]),
      yParity: true,
    };
  }
}

import { ArraySignatureType, ec, encode } from "starknet";
import { RawSigner } from "./signers";

export class LegacyArgentSigner extends RawSigner {
  constructor(
    public owner: LegacyStarknetKeyPair = new LegacyStarknetKeyPair(),
    public guardian?: LegacyStarknetKeyPair,
  ) {
    super();
  }

  async signRaw(messageHash: string): Promise<ArraySignatureType> {
    const signature = await this.owner.signRaw(messageHash);
    if (this.guardian) {
      const [guardianR, guardianS] = await this.guardian.signRaw(messageHash);
      signature[2] = guardianR;
      signature[3] = guardianS;
    }
    return signature;
  }
}

export class LegacyMultisigSigner extends RawSigner {
  constructor(public keys: RawSigner[]) {
    super();
  }

  async signRaw(messageHash: string): Promise<string[]> {
    const keys = [];
    for (const key of this.keys) {
      keys.push(await key.signRaw(messageHash));
    }
    return keys.flat();
  }
}

export abstract class LegacyKeyPair extends RawSigner {
  abstract get privateKey(): string;
  abstract get publicKey(): bigint;
}

export class LegacyStarknetKeyPair extends LegacyKeyPair {
  pk: string;

  constructor(pk?: string | bigint) {
    super();
    this.pk = pk ? `${pk}` : `0x${encode.buf2hex(ec.starkCurve.utils.randomPrivateKey())}`;
  }

  public get privateKey(): string {
    return this.pk;
  }

  public get publicKey() {
    return BigInt(ec.starkCurve.getStarkKey(this.pk));
  }

  public async signRaw(messageHash: string): Promise<string[]> {
    const { r, s } = ec.starkCurve.sign(messageHash, this.pk);
    return [r.toString(), s.toString()];
  }
}

export class LegacyMultisigKeyPair extends LegacyKeyPair {
  pk: string;

  constructor(pk?: string | bigint) {
    super();
    this.pk = pk ? `${pk}` : `0x${encode.buf2hex(ec.starkCurve.utils.randomPrivateKey())}`;
  }

  public get publicKey() {
    return BigInt(ec.starkCurve.getStarkKey(this.pk));
  }

  public get privateKey(): string {
    return this.pk;
  }

  public async signRaw(messageHash: string): Promise<string[]> {
    const { r, s } = ec.starkCurve.sign(messageHash, this.pk);
    return [this.publicKey.toString(), r.toString(), s.toString()];
  }
}

export const randomLegacyMultisigKeyPairs = (length: number) =>
  Array.from({ length }, () => new LegacyMultisigKeyPair());

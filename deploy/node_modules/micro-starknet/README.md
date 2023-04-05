# micro-starknet

Minimal implementation of [Starknet cryptography](https://docs.starkware.co/starkex/stark-curve.html) including Pedersen, Poseidon and Stark Curve.

## Usage

```sh
npm install micro-starknet
```

```ts
import * as starknet from 'micro-starknet';
```

### Curve

#### Signing and verification

```ts
const privateKey = '2dccce1da22003777062ee0870e9881b460a8b7eca276870f57c601f182136c';
const publicKey = starknet.getPublicKey(privateKey);
const messageHash = 'c465dd6b1bbffdb05442eb17f5ca38ad1aa78a6f56bf4415bdee219114a47';
const sig = starknet.sign(messageHash, privateKey);
const { r, s } = starknet.Signature.fromHex(sig);
deepStrictEqual(r.toString(16), '5f496f6f210b5810b2711c74c15c05244dad43d18ecbbdbe6ed55584bc3b0a2');
deepStrictEqual(s.toString(16), '4e8657b153787f741a67c0666bad6426c3741b478c8eaa3155196fc571416f3');
deepStrictEqual(starknet.verify(sig, messageHash, publicKey), true);
```

#### Private key to StarkKey

```ts
deepStrictEqual(
  starknet.getStarkKey('0x178047D3869489C055D7EA54C014FFB834A069C9595186ABE04EA4D1223A03F'),
  '0x1895a6a77ae14e7987b9cb51329a5adfb17bd8e7c638f92d6892d76e51cebcf'
);
```

### Pedersen hash

```ts
deepStrictEqual(
  starknet.pedersen(
    '0x3d937c035c878245caf64531a5756109c53068da139362728feb561405371cb',
    '0x208a0a10250e382e1e4bbe2880906c2791bf6275695e02fbbc6aeff9cd8b31a'
  ),
  '30e480bed5fe53fa909cc0f8c4d99b8f9f2c016be4c41e13a4848797979c662'
);
```

### Create private key from ethereum signature

```ts
const ethSignature =
  '0x21fbf0696d5e0aa2ef41a2b4ffb623bcaf070461d61cf7251c74161f82fec3a43' +
  '70854bc0a34b3ab487c1bc021cd318c734c51ae29374f2beb0e6f2dd49b4bf41c';
deepStrictEqual(
  starknet.ethSigToPrivate(ethSignature),
  '766f11e90cd7c7b43085b56da35c781f8c067ac0d578eabdceebc4886435bda'
);
```

### Private key from mnemonic

```ts
import * as bip32 from '@scure/bip32';
import * as bip39 from '@scure/bip39';

should('Seed derivation (example)', () => {
  const layer = 'starknet';
  const application = 'starkdeployement';
  const mnemonic =
    'range mountain blast problem vibrant void vivid doctor cluster enough melody ' +
    'salt layer language laptop boat major space monkey unit glimpse pause change vibrant';
  const ethAddress = '0xa4864d977b944315389d1765ffa7e66F74ee8cd7';
  const hdKey = bip32.HDKey.fromMasterSeed(bip39.mnemonicToSeedSync(mnemonic)).derive(
    starknet.getAccountPath(layer, application, ethAddress, 0)
  );
  deepStrictEqual(
    starknet.grindKey(hdKey.privateKey),
    '6cf0a8bf113352eb863157a45c5e5567abb34f8d32cddafd2c22aa803f4892c'
  );
});
```

### Utils

#### Hash chain

```ts
deepStrictEqual(
  starknet.hashChain([1, 2, 3]),
  '5d9d62d4040b977c3f8d2389d494e4e89a96a8b45c44b1368f1cc6ec5418915'
);
```

#### Key grinding

```ts
deepStrictEqual(
  starknet.grindKey('86F3E7293141F20A8BAFF320E8EE4ACCB9D4A4BF2B4D295E8CEE784DB46E0519'),
  '5c8c8683596c732541a59e03007b2d30dbbbb873556fe65b5fb63c16688f941'
);
```

#### Starknet keccak

```ts
deepStrictEqual(
  starknet.keccak(utf8.decode('hello')),
  0x8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8n
);
```

## Benchmark

Benchmarks measured with Apple M2 on MacOS 13 with node.js 18.10.

The package is much faster than `@starkware-industries/starkware-crypto-utils`.

```
stark
init x 33 ops/sec @ 30ms/op
pedersen
├─old x 86 ops/sec @ 11ms/op
└─noble x 620 ops/sec @ 1ms/op
poseidon x 7,162 ops/sec @ 139μs/op
verify
├─old x 303 ops/sec @ 3ms/op
└─noble x 485 ops/sec @ 2ms/op
```

## License

MIT (c) Paul Miller [(https://paulmillr.com)](https://paulmillr.com), see LICENSE file.

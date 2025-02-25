# Argent Accounts on Starknet

## Specification

See [Argent Account](./docs/argent_account.md) and [Argent Multisig](./docs/multisig.md) for more details.

## Release Notes

See here for the [Argent Account](./docs/CHANGELOG_argent_account.md)

See here for the [Argent Multisig](./docs/CHANGELOG_multisig.md)

## Deployments

See deployed class hashes can be found here for the [Argent Account](./deployments/account.txt), and here for the [Argent Multisig](./deployments/multisig.txt)

Other deployment artifacts are located in [/deployments/](./deployments/)

## Documentation

We use [mdBook](https://rust-lang.github.io/mdBook/index.html) to generate a browsable and searchable documentation website.

Requirements :

- [rust](https://www.rust-lang.org/tools/install)
- [mdBook](https://rust-lang.github.io/mdBook/guide/installation.html#installation)

To generate the documentation :

```sh
mdbook build
```

You can browse the documentation locally with :

```sh
mdbook serve --open
```

## Development

See [Development](./docs/development.md)

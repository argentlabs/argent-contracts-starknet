# Argent Account on Starknet

Preliminary work for an Argent Account on Starknet.

## Environment (python)

### Install Cairo

See https://www.cairo-lang.org/docs/quickstart.html

### Install Nile
```
pip install cairo-nile
```

See https://github.com/martriay/nile for more details.


### Install pytest
```
pip install pytest pytest-asyncio
```

## Compile the contracts
```
nile compile
```

### Test the contracts
```
pytest ./test/argent_account.py
```

## Environment (node)

### Install

```
yarn install
```

## Compile the contracts
```
yarn run compile 
```

### Test the contracts
```
yarn run test
```
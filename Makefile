# Won't write the called command in the console
.SILENT:
# Because we have a folder called test we need PHONY to avoid collision
.PHONY: test 

INSTALLATION_FOLDER=./cairo
INSTALLATION_FOLDER_CARGO=$(INSTALLATION_FOLDER)/Cargo.toml
SOURCE_FOLDER=./contracts
CAIRO_VERSION=v1.0.0

all: install build compile-account fixtures

install: install-cairo install-integration build vscode

install-cairo:
	if [ -d $(INSTALLATION_FOLDER) ]; then \
		$(MAKE) update-cairo; \
	else \
		$(MAKE) clone-cairo; \
	fi

install-integration:
	yarn

clone-cairo:
	mkdir -p $(INSTALLATION_FOLDER)
	git clone --branch $(CAIRO_VERSION) https://github.com/starkware-libs/cairo.git

update-cairo:
	git -C $(INSTALLATION_FOLDER) checkout $(CAIRO_VERSION)

build:
	cargo build --manifest-path $(INSTALLATION_FOLDER_CARGO) --workspace --release

compile-account: 
	./cairo/target/release/starknet-compile $(SOURCE_FOLDER)/account account.json --allowed-libfuncs-list-name experimental_v0.1.0

fixtures: 
	./cairo/target/release/starknet-compile $(SOURCE_FOLDER)/account ./tests/fixtures/ArgentAccount.json --allowed-libfuncs-list-name experimental_v0.1.0
	./cairo/target/release/starknet-sierra-compile ./tests/fixtures/ArgentAccount.json ./tests/fixtures/ArgentAccount.casm --allowed-libfuncs-list-name experimental_v0.1.0
	./cairo/target/release/starknet-compile $(SOURCE_FOLDER)/multicall/src/test_dapp.cairo ./tests/fixtures/TestDapp.json --allowed-libfuncs-list-name experimental_v0.1.0
	./cairo/target/release/starknet-sierra-compile ./tests/fixtures/TestDapp.json ./tests/fixtures/TestDapp.casm --allowed-libfuncs-list-name experimental_v0.1.0
	./cairo/target/release/starknet-compile $(SOURCE_FOLDER)/multisig ./tests/fixtures/ArgentMultisigAccount.json --allowed-libfuncs-list-name experimental_v0.1.0 --contract-path multisig::argent_multisig_account::ArgentMultisigAccount
	./cairo/target/release/starknet-sierra-compile ./tests/fixtures/ArgentMultisigAccount.json ./tests/fixtures/ArgentMultisigAccount.casm --allowed-libfuncs-list-name experimental_v0.1.0

test: 
	./cairo/target/release/cairo-test --starknet $(SOURCE_FOLDER)

test-account: 
	./cairo/target/release/cairo-test --starknet $(SOURCE_FOLDER)/account

test-lib: 
	./cairo/target/release/cairo-test --starknet $(SOURCE_FOLDER)/lib

test-multicall: 
	./cairo/target/release/cairo-test --starknet $(SOURCE_FOLDER)/multicall

test-multisig: 
	./cairo/target/release/cairo-test --starknet $(SOURCE_FOLDER)/multisig

test-integration: fixtures
	yarn test:ci

format:
	./cairo/target/release/cairo-format --recursive $(SOURCE_FOLDER) --print-parsing-errors

check-format:
	./cairo/target/release/cairo-format --check --recursive $(SOURCE_FOLDER)

devnet:
	INSTALLATION_FOLDER_CARGO=$(INSTALLATION_FOLDER_CARGO) ./scripts/start-devnet.sh

kill-devnet:
	lsof -t -i tcp:5050 | xargs kill

vscode:
	cd cairo/vscode-cairo && cargo build --bin cairo-language-server --release && cd ../..

clean:
	rm -rf cairo dist node_modules venv
	git reset --hard HEAD
	rm dump

# Won't write the called command in the console
.SILENT:
# Because we have a folder called test we need PHONY to avoid collision
.PHONY: test 

INSTALLATION_FOLDER=./cairo
INSTALLATION_FOLDER_CARGO=$(INSTALLATION_FOLDER)/Cargo.toml
ACCOUNT_FOLDER= $(SOURCE_FOLDER)/account
LIB_FOLDER= $(SOURCE_FOLDER)/lib
MULTISIG_FOLDER= $(SOURCE_FOLDER)/multisig
MULTICALL_FOLDER= $(SOURCE_FOLDER)/multicall
SOURCE_FOLDER=./contracts
CAIRO_VERSION=v2.0.0-rc2
FIXTURES_FOLDER = ./tests/fixtures

all: install build fixtures

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
	./cairo/target/release/starknet-compile $(SOURCE_FOLDER)/account account.json --allowed-libfuncs-list-name all

fixtures: 
	./cairo/target/release/starknet-compile $(ACCOUNT_FOLDER) $(FIXTURES_FOLDER)/ArgentAccount.json --allowed-libfuncs-list-name all --contract-path account::argent_account::ArgentAccount
	./cairo/target/release/starknet-sierra-compile $(FIXTURES_FOLDER)/ArgentAccount.json $(FIXTURES_FOLDER)/ArgentAccount.casm --allowed-libfuncs-list-name all
	./cairo/target/release/starknet-compile $(LIB_FOLDER) $(FIXTURES_FOLDER)/TestDapp.json --allowed-libfuncs-list-name all
	./cairo/target/release/starknet-sierra-compile $(FIXTURES_FOLDER)/TestDapp.json $(FIXTURES_FOLDER)/TestDapp.casm --allowed-libfuncs-list-name all
	./cairo/target/release/starknet-compile $(MULTISIG_FOLDER) $(FIXTURES_FOLDER)/ArgentMultisig.json --allowed-libfuncs-list-name all --contract-path multisig::argent_multisig::ArgentMultisig
	./cairo/target/release/starknet-sierra-compile $(FIXTURES_FOLDER)/ArgentMultisig.json $(FIXTURES_FOLDER)/ArgentMultisig.casm --allowed-libfuncs-list-name all

test: 
	./cairo/target/release/cairo-test --starknet $(SOURCE_FOLDER)

test-account: 
	./cairo/target/release/cairo-test --starknet $(ACCOUNT_FOLDER)

test-lib: 
	./cairo/target/release/cairo-test --starknet $(LIB_FOLDER)

test-multicall: 
	./cairo/target/release/cairo-test --starknet $(MULTICALL_FOLDER)

test-multisig: 
	./cairo/target/release/cairo-test --starknet $(MULTISIG_FOLDER)

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

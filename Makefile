# Won't write the called command in the console
.SILENT:
# Because we have a folder called test we need PHONY to avoid collision
.PHONY: test 

INSTALLATION_FOLDER=./cairo
INSTALLATION_FOLDER_CARGO=$(INSTALLATION_FOLDER)/Cargo.toml
SOURCE_FOLDER=./contracts
CAIRO_VERSION=v1.0.0-alpha.7

install: install-cairo build vscode

install-cairo:
	if [ -d $(INSTALLATION_FOLDER) ]; then \
		$(MAKE) update-cairo; \
	else \
		$(MAKE) clone-cairo; \
	fi

clone-cairo:
	mkdir -p $(INSTALLATION_FOLDER)
	git clone --branch $(CAIRO_VERSION) https://github.com/starkware-libs/cairo.git

update-cairo:
	git -C $(INSTALLATION_FOLDER) checkout $(CAIRO_VERSION)

build:
	cargo build --manifest-path $(INSTALLATION_FOLDER_CARGO) --workspace --release

compile-account: 
	./cairo/target/release/starknet-compile $(SOURCE_FOLDER)/account account.json --allowed-libfuncs-list-name experimental_v0.1.0

compile-account-test: 
	./cairo/target/release/starknet-compile $(SOURCE_FOLDER)/account ./tests/contracts/ArgentAccount.json --allowed-libfuncs-list-name experimental_v0.1.0
	./cairo/target/release/starknet-sierra-compile ./tests/contracts/ArgentAccount.json ./tests/contracts/ArgentAccount.casm --allowed-libfuncs-list-name experimental_v0.1.0

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

format:
	./cairo/target/release/cairo-format --recursive $(SOURCE_FOLDER) --print-parsing-errors

check-format:
	./cairo/target/release/cairo-format --check --recursive $(SOURCE_FOLDER)

devnet:
	INSTALLATION_FOLDER_CARGO=$(INSTALLATION_FOLDER_CARGO) ./scripts/start-devnet.sh

kill-devnet:
	lsof -t -i tcp:5050 | xargs kill

test-jsons:
	./cairo/target/release/starknet-compile ./contracts/account ./tests/contracts/ArgentAccount.json --allowed-libfuncs-list-name experimental_v0.1.0 --replace-ids
	./cairo/target/release/starknet-sierra-compile ./tests/contracts/ArgentAccount.json ./tests/contracts/ArgentAccount.casm --allowed-libfuncs-list-name experimental_v0.1.0 

vscode:
	cd cairo/vscode-cairo && cargo build --bin cairo-language-server --release && cd ../..

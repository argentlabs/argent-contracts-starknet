# Won't write the called command in the console
.SILENT:
# Because we have a folder called test we need PHONY to avoid collision
.PHONY: test 

INSTALLATION_FOLDER=./cairo
INSTALLATION_FOLDER_CARGO=$(INSTALLATION_FOLDER)/Cargo.toml
SOURCE_FOLDER=./contracts
CAIRO_VERSION=v1.0.0-alpha.7

install: 
	$(MAKE) install-cairo
	$(MAKE) build
	$(MAKE) vscode

make install-cairo:
	if [ -d $(INSTALLATION_FOLDER) ]; then \
		$(MAKE) update-cairo; \
	else \
		$(MAKE) clone-cairo; \
	fi

clone-cairo:
	mkdir -p $(INSTALLATION_FOLDER)
	git clone git@github.com:starkware-libs/cairo.git --branch $(CAIRO_VERSION)

update-cairo:
	git -C $(INSTALLATION_FOLDER) checkout $(CAIRO_VERSION)

build:
	cargo build --manifest-path $(INSTALLATION_FOLDER_CARGO) --workspace --release

compile-account: 
	./cairo/target/release/starknet-compile $(SOURCE_FOLDER)/account account.json --allowed-libfuncs-list-name experimental_v0.1.0

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
	if ! command -v starknet-devnet >/dev/null; then \
		echo "starknet-devnet is not installed. Please install it and try again." >&2; \
		echo "Maybe start your venv" >&2; \
		exit 1; \
	fi
	if nc -z 127.0.0.1 5050; then \
		echo "Port is not free"; \
		exit 1; \
	else \
		echo "About to spawn a devnet"; \
		export STARKNET_DEVNET_CAIRO_VM=python; \
		starknet-devnet --cairo-compiler-manifest $(INSTALLATION_FOLDER_CARGO) --seed 42 --lite-mode; \
	fi

vscode:
	cd cairo/vscode-cairo && cargo build --bin cairo-language-server --release && cd ../..
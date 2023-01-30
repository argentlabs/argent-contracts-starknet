# @ are used to prevent the makefile to print the command used in the console
# Because we have a fodler called test we need PHONY
.PHONY: test 

install: 
	@if [ -d "cairo/starkware-libs-cairo" ]; then $(MAKE) update-cairo; else $(MAKE) clone-cairo; fi; $(MAKE) build

clone-cairo:
	@mkdir -p cairo/starkware-libs-cairo
	@git clone --depth 1 https://github.com/starkware-libs/cairo.git ./cairo/starkware-libs-cairo


update-cairo:
	@git -C ./cairo/starkware-libs-cairo pull

build:
	@cargo build

test: 
	@cargo run --bin cairo-test -- --starknet --path contracts/

format:
	@cargo run --bin cairo-format -- --check --recursive contracts/
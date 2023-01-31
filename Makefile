# Won't write the called command in the console
.SILENT:
# Because we have a folder called test we need PHONY to avoid collision
.PHONY: test 

INSTALLATION-FOLDER=./cairo

install: 
	if [ -d $(INSTALLATION-FOLDER) ]; then \
		$(MAKE) update-cairo; \
	else \
		$(MAKE) clone-cairo; \
	fi
	$(MAKE) build

clone-cairo:
	mkdir -p $(INSTALLATION-FOLDER)
	git clone --depth 1 https://github.com/starkware-libs/cairo.git $(INSTALLATION-FOLDER)


update-cairo:
	git -C $(INSTALLATION-FOLDER) pull

build:
	cargo build

test: 
	cargo run --bin cairo-test -- --starknet --path contracts/


format:
	cargo run --bin cairo-format -- --recursive contracts/

check-format:
	cargo run --bin cairo-format -- --check --recursive contracts/

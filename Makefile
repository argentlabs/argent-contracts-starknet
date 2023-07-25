# Won't write the called command in the console
.SILENT:

DEVNET_CAIRO_INSTALLATION_FOLDER=./cairo
DEVNET_CAIRO_VERSION=v2.0.0

install-devnet-cairo:
	mkdir -p $(DEVNET_CAIRO_INSTALLATION_FOLDER)
	git clone --branch $(DEVNET_CAIRO_VERSION) https://github.com/starkware-libs/cairo.git
	
kill-devnet:
	lsof -t -i tcp:5050 | xargs kill

clean:
	rm -rf cairo dist node_modules venv
	git reset --hard HEAD
	rm dump

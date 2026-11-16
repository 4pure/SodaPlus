.PHONY: build-mac build-mac-arm build-mac-intel build-bridge fetch-libresoda run

fetch-libresoda:
	bash scripts/fetch-libresoda.sh

build-bridge:
	bash scripts/build-bridge.sh

build-mac:
	bash scripts/package-mac.sh universal --app-only

build-mac-arm:
	bash scripts/package-mac.sh arm --app-only

build-mac-intel:
	bash scripts/package-mac.sh intel --app-only

run: build-bridge
	swift run

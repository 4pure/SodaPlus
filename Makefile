.PHONY: \
	build-mac build-mac-arm build-mac-intel \
	build-mac-app build-mac-arm-app build-mac-intel-app \
	build-bridge fetch-libresoda run

fetch-libresoda:
	bash scripts/fetch-libresoda.sh

build-bridge:
	bash scripts/build-bridge.sh

# 完整打包：只出 DMG 到 installers/（不带 .app）
build-mac:
	bash scripts/package.sh universal

build-mac-arm:
	bash scripts/package.sh arm

build-mac-intel:
	bash scripts/package.sh intel

# --app-only：只发布最新 .app 到 installers/
build-mac-app:
	bash scripts/package.sh universal --app-only

build-mac-arm-app:
	bash scripts/package.sh arm --app-only

build-mac-intel-app:
	bash scripts/package.sh intel --app-only

run: build-bridge
	swift run

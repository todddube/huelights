.PHONY: build app install run test xcodeproj icons clean

build:            ## Debug build with SwiftPM
	swift build

app:              ## Release build + build/HueBar.app (ad-hoc signed)
	scripts/build-app.sh

install: app      ## Copy the app to /Applications
	scripts/build-app.sh --install

run: app          ## Build the app bundle and (re)launch it
	pkill -x HueBar || true
	open build/HueBar.app

test:             ## HueKit and HueBar unit tests (add HUEBAR_LIVE=1 to also hit the bridge on your LAN)
	swift test --package-path HueKit
	swift test

xcodeproj:        ## Regenerate HueBar.xcodeproj from project.yml
	xcodegen generate

icons:            ## Re-render the app icon, .icns and logo from scripts/make-icons.swift
	swift scripts/make-icons.swift .

clean:
	rm -rf .build build HueKit/.build

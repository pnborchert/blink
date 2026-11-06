# Blink — build helpers. Everything here is a thin wrapper around SwiftPM.

# SwiftPM's build products include bundles (.app, .xctest) that codesign rejects
# when iCloud Drive syncs the folder ("Desktop & Documents" sync adds Finder
# metadata). Build outside iCloud in that case; override with BUILD_DIR=...
ifneq (,$(filter $(HOME)/Documents/% $(HOME)/Desktop/% $(HOME)/Library/Mobile\ Documents/%,$(CURDIR)))
BUILD_DIR ?= $(HOME)/Library/Caches/blink-build
else
BUILD_DIR ?= .build
endif

# With only the Command Line Tools installed (no Xcode), SwiftPM does not find
# the Swift Testing macro plugin on its own.
TESTING_PLUGINS := $(shell xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing
ifneq (,$(wildcard $(TESTING_PLUGINS)))
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS)
endif

APP := dist/Blink.app
export BUILD_DIR

.PHONY: build test app icon run install uninstall clean

build:
	swift build --scratch-path "$(BUILD_DIR)"

test:
	swift test --scratch-path "$(BUILD_DIR)" $(TEST_FLAGS)

app:
	scripts/bundle.sh

# Regenerates the app icon from scripts/make-icon.swift (output is committed).
icon:
	@mkdir -p "$(BUILD_DIR)/icon" docs
	swift scripts/make-icon.swift "$(BUILD_DIR)/icon"
	iconutil -c icns "$(BUILD_DIR)/icon/AppIcon.iconset" -o Resources/AppIcon.icns
	sips -Z 512 "$(BUILD_DIR)/icon/logo.png" --out docs/logo.png >/dev/null

run: app
	-pkill -x Blink
	open "$(APP)"

install: app
	-pkill -x Blink
	rm -rf /Applications/Blink.app
	cp -R "$(APP)" /Applications/
	open /Applications/Blink.app

uninstall:
	-pkill -x Blink
	rm -rf /Applications/Blink.app

clean:
	rm -rf "$(BUILD_DIR)" .build dist

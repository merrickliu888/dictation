APP_NAME ?= Dictation
BUNDLE_ID ?= dev.dictation.app
CODESIGN_IDENTITY ?= -
ARCH ?= $(shell uname -m)
BUILD_DIR = build
MIN_MACOS = 15.0
ICON_SOURCE = Assets/dictation-logo.png
ICONSET_DIR = $(BUILD_DIR)/Dictation.iconset
ICON_FILE = $(BUILD_DIR)/Dictation.icns

SOURCES = $(shell find Sources -name '*.swift' -type f | LC_ALL=C sort)
# The tests compile only the AppKit-free core with plain swiftc.
TEST_SOURCES = $(shell find Tests -name '*.swift' -type f | LC_ALL=C sort) \
	Sources/Core/TOML.swift \
	Sources/Core/Shortcuts.swift \
	Sources/Core/DictationInteractionModel.swift

APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

SDK = $(shell xcrun --show-sdk-path)
# Arch-specific: .build/release is a symlink to whichever arch built last.
SPM_BIN = .build/$(ARCH)-apple-macosx/release

VERSION = $(shell plutil -extract CFBundleShortVersionString raw Info.plist)
ARCH_LABEL = $(if $(filter arm64,$(ARCH)),Apple-Silicon,Intel)
DMG = $(BUILD_DIR)/$(APP_NAME)-$(VERSION)-$(ARCH_LABEL).dmg
DMG_STAGING = $(BUILD_DIR)/dmg-$(ARCH)

.PHONY: all app run test clean release release-all

all: app

# Built with SwiftPM; the bundle is assembled by hand.
app: $(SOURCES) Package.swift Info.plist Dictation.entitlements $(ICON_FILE)
	swift build -c release --arch $(ARCH)
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
	@cp "$(SPM_BIN)/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	@cp "$(ICON_FILE)" "$(RESOURCES)/"
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleDisplayName -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" --entitlements Dictation.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"
	@# Ad-hoc signing keys the Accessibility grant to the binary's hash, so each
	@# rebuild invalidates it while the stale row lingers in System Settings.
	@# Clear it so the new build re-prompts instead of silently staying untrusted.
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
		tccutil reset Accessibility "$(BUNDLE_ID)" >/dev/null 2>&1 \
			&& echo "Reset Accessibility permission for $(BUNDLE_ID) (ad-hoc build); re-grant on next launch" \
			|| echo "Could not reset Accessibility permission for $(BUNDLE_ID); remove and re-add it in System Settings"; \
	fi

$(ICON_FILE): $(ICON_SOURCE)
	@rm -rf "$(ICONSET_DIR)"
	@mkdir -p "$(ICONSET_DIR)"
	@sips -z 16 16 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_16x16.png" >/dev/null
	@sips -z 32 32 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_16x16@2x.png" >/dev/null
	@sips -z 32 32 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_32x32.png" >/dev/null
	@sips -z 64 64 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_32x32@2x.png" >/dev/null
	@sips -z 128 128 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_128x128.png" >/dev/null
	@sips -z 256 256 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_128x128@2x.png" >/dev/null
	@sips -z 256 256 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_256x256.png" >/dev/null
	@sips -z 512 512 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_256x256@2x.png" >/dev/null
	@sips -z 512 512 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_512x512.png" >/dev/null
	@cp "$(ICON_SOURCE)" "$(ICONSET_DIR)/icon_512x512@2x.png"
	@iconutil -c icns "$(ICONSET_DIR)" -o "$(ICON_FILE)"
	@rm -rf "$(ICONSET_DIR)"

run: app
	open "$(APP_BUNDLE)"

# A drag-to-Applications DMG for one architecture (ARCH=arm64 or x86_64).
release: app
	@rm -rf "$(DMG_STAGING)" "$(DMG)"
	@mkdir -p "$(DMG_STAGING)"
	@cp -R "$(APP_BUNDLE)" "$(DMG_STAGING)/"
	@ln -s /Applications "$(DMG_STAGING)/Applications"
	@hdiutil create -quiet -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DMG)"
	@rm -rf "$(DMG_STAGING)"
	@echo "Packaged $(DMG)"

# Both DMGs, one after the other; the bundle dir is shared, so not parallel.
release-all:
	$(MAKE) release ARCH=arm64
	$(MAKE) release ARCH=x86_64

test:
	@mkdir -p $(BUILD_DIR)
	swiftc -parse-as-library \
		-o $(BUILD_DIR)/dictation-tests \
		-sdk "$(SDK)" \
		-target $(ARCH)-apple-macosx$(MIN_MACOS) \
		$(TEST_SOURCES)
	$(BUILD_DIR)/dictation-tests

clean:
	rm -rf $(BUILD_DIR) .build

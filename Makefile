# Variables
APP_NAME := MenuBarFS
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS)/MacOS

SOURCES := $(shell find Sources -name '*.swift')
SWIFTC := xcrun swiftc
SWIFT_FLAGS := -O -whole-module-optimization
FRAMEWORKS := -framework Cocoa \
              -framework SwiftUI \
              -framework DiskArbitration \
              -framework NetFS \
			  -framework Security \
			  -framework UserNotifications \
			  -framework SystemConfiguration \
			  -framework Network \
			  -framework ServiceManagement

BINARY := $(MACOS_DIR)/$(APP_NAME)
PLIST := $(CONTENTS)/Info.plist
VERSION      := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo '0.0.0')
DMG          := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
DMG_VOL_NAME := $(APP_NAME) $(VERSION)

# Default goal
all: $(BINARY) $(PLIST)

# Rules
$(BINARY): $(SOURCES)
	@mkdir -p "$(@D)"
	$(SWIFTC) $(SWIFT_FLAGS) $(SOURCES) $(FRAMEWORKS) -o "$@"

$(PLIST): Resources/Info.plist
	@mkdir -p "$(@D)"
	@cp "$<" "$@"
	@codesign --sign - --force --deep "$(APP_BUNDLE)"

dmg: all
	@rm -f "$(DMG)"
	create-dmg \
		--volname "$(DMG_VOL_NAME)" \
		--window-size 460 280 \
		--icon-size 96 \
		--icon "$(APP_NAME).app" 120 140 \
		--app-drop-link 360 140 \
		--no-internet-enable \
		"$(DMG)" \
		"$(APP_BUNDLE)"
	@echo "DMG ready: $(DMG)"

# Phony targets
.PHONY: all clean run debug install dmg

clean:
	rm -rf "$(BUILD_DIR)"

run: all
	@open "$(APP_BUNDLE)"

debug: SWIFT_FLAGS := -g -Onone
debug: all

install: all
	cp -R "$(APP_BUNDLE)" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

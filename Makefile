# Variables
APP_NAME := MenuBarFS
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS)/MacOS

SOURCES := $(shell find Sources -name '*.swift')
SWIFTC := xcrun swiftc
ARCH ?= arm64
MIN_MACOS := $(shell /usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' Resources/Info.plist)
TARGET := -target $(ARCH)-apple-macos$(MIN_MACOS)
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

BINARY  := $(MACOS_DIR)/$(APP_NAME)
PLIST   := $(CONTENTS)/Info.plist
ICON    := $(CONTENTS)/Resources/AppIcon.icns
STATUS_ICON := $(CONTENTS)/Resources/MenuBarIcon.pdf
VERSION      := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo '0.0.0')
DMG          := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
DMG_VOL_NAME := $(APP_NAME) $(VERSION)

VENV     := .venv
DMGBUILD := $(VENV)/bin/dmgbuild

# Default goal
all: $(BINARY) $(PLIST)

# Rules
# Info.plist is a prerequisite because the deployment target is read from it
$(BINARY): $(SOURCES) Resources/Info.plist
	@mkdir -p "$(@D)"
	$(SWIFTC) $(TARGET) $(SWIFT_FLAGS) $(SOURCES) $(FRAMEWORKS) -o "$@"

# Depends on all bundle content so signing always runs after any content change
$(PLIST): Resources/Info.plist $(BINARY) $(ICON) $(STATUS_ICON)
	@mkdir -p "$(@D)"
	@cp Resources/Info.plist "$@"
	@codesign --sign - --force --deep "$(APP_BUNDLE)"

$(ICON): Resources/AppIcon.icns
	@mkdir -p "$(@D)"
	@cp "$<" "$@"

$(STATUS_ICON): Resources/MenuBarIcon.pdf
	@mkdir -p "$(@D)"
	@cp "$<" "$@"

$(DMGBUILD): requirements.txt
	python3 -m venv "$(VENV)"
	"$(VENV)/bin/pip" install --quiet -r requirements.txt
	@touch "$@"

dmg: all $(DMGBUILD)
	@rm -f "$(DMG)"
	"$(DMGBUILD)" -s dmg-settings.py -D app="$(APP_BUNDLE)" "$(DMG_VOL_NAME)" "$(DMG)"
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

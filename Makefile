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
			  -framework Network

BINARY := $(MACOS_DIR)/$(APP_NAME)
PLIST := $(CONTENTS)/Info.plist
VERSION      := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo '0.0.0')
DMG          := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
DMG_RW       := $(BUILD_DIR)/$(APP_NAME)-rw.dmg
DMG_STAGING  := $(BUILD_DIR)/.dmg-staging
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
	@set -e; \
	rm -rf "$(DMG_STAGING)" "$(DMG)" "$(DMG_RW)"; \
	mkdir -p "$(DMG_STAGING)"; \
	cp -R "$(APP_BUNDLE)" "$(DMG_STAGING)/"; \
	ln -s /Applications "$(DMG_STAGING)/Applications"; \
	hdiutil create -volname "$(DMG_VOL_NAME)" \
		-srcfolder "$(DMG_STAGING)" \
		-ov -format UDRW \
		-o "$(DMG_RW)"; \
	rm -rf "$(DMG_STAGING)"; \
	hdiutil attach -readwrite -noverify -noautoopen "$(DMG_RW)"; \
	sleep 2; \
	osascript \
		-e 'tell application "Finder"' \
		-e '  tell disk "$(DMG_VOL_NAME)"' \
		-e '    open' \
		-e '    set current view of container window to icon view' \
		-e '    set toolbar visible of container window to false' \
		-e '    set statusbar visible of container window to false' \
		-e '    set the bounds of container window to {200, 120, 660, 400}' \
		-e '    set viewOptions to the icon view options of container window' \
		-e '    set arrangement of viewOptions to not arranged' \
		-e '    set icon size of viewOptions to 96' \
		-e '    set position of item "$(APP_NAME).app" of container window to {120, 140}' \
		-e '    set position of item "Applications" of container window to {360, 140}' \
		-e '    update without registering applications' \
		-e '    delay 2' \
		-e '    close' \
		-e '  end tell' \
		-e 'end tell'; \
	hdiutil detach "/Volumes/$(DMG_VOL_NAME)"; \
	hdiutil convert "$(DMG_RW)" \
		-format UDZO -imagekey zlib-level=9 \
		-o "$(DMG)"; \
	rm -f "$(DMG_RW)"; \
	echo "DMG ready: $(DMG)"

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

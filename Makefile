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
			  -framework UserNotifications

BINARY := $(MACOS_DIR)/$(APP_NAME)
PLIST := $(CONTENTS)/Info.plist

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

# Phony targets
.PHONY: all clean run debug install

clean:
	rm -rf "$(BUILD_DIR)"

run: all
	@open "$(APP_BUNDLE)"

debug: SWIFT_FLAGS := -g -Onone
debug: all

install: all
	cp -R "$(APP_BUNDLE)" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

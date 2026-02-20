APP_NAME = iMessagePrinter
BUILD_DIR = .build/release
BUNDLE = $(APP_NAME).app
SIGN_IDENTITY = -

.PHONY: build bundle run clean dev

build:
	swift build --configuration release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(BUNDLE)/Contents/
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/
	codesign --force --sign $(SIGN_IDENTITY) \
		--entitlements Resources/$(APP_NAME).entitlements \
		$(BUNDLE)

run: bundle
	open $(BUNDLE)

dev:
	swift build --configuration debug && .build/debug/$(APP_NAME)

clean:
	swift package clean
	rm -rf $(BUNDLE)

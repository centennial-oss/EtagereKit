.PHONY: build lint test build-macos build-ios build-tvos clean

# SwiftLint: https://github.com/realm/SwiftLint - `brew install swiftlint`
SWIFTLINT ?= $(shell command -v swiftlint 2>/dev/null)
SCHEME := EtagereKit
# xcodebuild's output stays inside .build (ignored by git).
XCODE_DERIVED_DATA := .build/xcode

# Everything CI checks: lint, the unit tests on macOS, and builds for iOS and tvOS.
build: lint test build-ios build-tvos

lint:
	@if [ -z "$(SWIFTLINT)" ]; then \
		echo "SwiftLint not found. Install with: brew install swiftlint" >&2; \
		exit 1; \
	fi
	@"$(SWIFTLINT)" lint --strict

# Unit tests on macOS. They never touch the network or real devices.
test:
	swift test

build-macos:
	swift build

build-ios:
	xcodebuild -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(XCODE_DERIVED_DATA) build -quiet

build-tvos:
	xcodebuild -scheme $(SCHEME) -destination 'generic/platform=tvOS Simulator' \
		-derivedDataPath $(XCODE_DERIVED_DATA) build -quiet

clean:
	rm -rf .build

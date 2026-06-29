#!/usr/bin/env bash
# Build VoiceInk from source on Xcode 16.x (Swift 6.0 SDK) without paying / without Xcode 26.
#
# Why this script exists (3 obstacles, all worked around with NO large downloads):
#   1. Dependency LLMkit declares swift-tools-version 6.2 -> SwiftPM 6.0 refuses to parse it.
#      Fix: resolve packages with a standalone swift.org 6.2 toolchain, then lower the
#           checked-out LLMkit manifest to 6.0 and build with the stock Xcode toolchain.
#   2. App source uses macOS-26-only Speech APIs (SpeechTranscriber/AssetInventory), gated
#      behind the ENABLE_NATIVE_SPEECH_ANALYZER flag. Fix: that flag is stripped from
#      project.pbxproj (committed in the working tree) so the native backend compiles out.
#      You use Parakeet, so this backend is irrelevant.
#   3. App uses macOS-26 SwiftUI overloads .help(LocalizedStringResource) /
#      .accessibilityLabel(LocalizedStringResource). Fix: call sites wrapped in Text(...)
#      in AddIconButton.swift and AppControls.swift (committed in the working tree).
#
# Requires: a swift.org Swift 6.2.x toolchain installed in ~/Library/Developer/Toolchains
#   (download once: https://www.swift.org/install/macos/  -> ~1.7GB, already done).
set -euo pipefail
cd "$(dirname "$0")"

DERIVED="$PWD/.local-build"
LLMKIT_MANIFEST="$DERIVED/SourcePackages/checkouts/LLMkit/Package.swift"

# Find an installed swift.org 6.2 toolchain bundle id.
TC_DIR=$(ls -d "$HOME/Library/Developer/Toolchains/"swift-6.2*xctoolchain 2>/dev/null | head -1 || true)
[ -n "$TC_DIR" ] || { echo "ERROR: no swift-6.2 toolchain in ~/Library/Developer/Toolchains"; exit 1; }
TC_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$TC_DIR/Info.plist")
echo ">> using toolchain $TC_ID for package resolution"

# Ensure whisper.xcframework exists (cached in ~/VoiceInk-Dependencies).
make setup

# Step 1: resolve packages with the 6.2 toolchain so the LLMkit 6.2 manifest parses.
TOOLCHAINS="$TC_ID" xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk \
  -derivedDataPath "$DERIVED" -resolvePackageDependencies

# Step 2: lower the checked-out LLMkit manifest to 6.0 so the stock toolchain accepts it.
if [ -f "$LLMKIT_MANIFEST" ]; then
  sed -i '' 's#// swift-tools-version: *6\.2#// swift-tools-version: 6.0#' "$LLMKIT_MANIFEST"
  echo ">> patched LLMkit manifest -> $(head -1 "$LLMKIT_MANIFEST")"
fi

# Step 3: build with the stock Xcode toolchain, resolution disabled so the patch sticks.
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -derivedDataPath "$DERIVED" -xcconfig LocalBuild.xcconfig \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
  CODE_SIGN_ENTITLEMENTS="$PWD/VoiceInk/VoiceInk.local.entitlements" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
  build

APP="$DERIVED/Build/Products/Debug/VoiceInk.app"
rm -rf "$HOME/Downloads/VoiceInk.app"
ditto "$APP" "$HOME/Downloads/VoiceInk.app"
xattr -cr "$HOME/Downloads/VoiceInk.app"
echo ">> built: ~/Downloads/VoiceInk.app  (install: ditto over /Applications/VoiceInk.app)"

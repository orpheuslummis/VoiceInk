#!/usr/bin/env bash
# Build VoiceInk from source on Xcode 16.x (Swift 6.0 SDK) without paying / without Xcode 26.
# See PERSONAL_BUILD.md for the full recipe, rationale, and recovery notes.
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
#   (download once: https://www.swift.org/install/macos/  -> ~1.7GB).
#
# Usage:
#   ./build-local-xcode16.sh          normal build (incremental, no large downloads)
#   ./build-local-xcode16.sh --fresh  wipe .local-build/SourcePackages and re-resolve
#                                     everything from scratch. Re-downloads ALL Swift
#                                     package dependencies (several hundred MB) -- only
#                                     use this on unmetered network, and only when a
#                                     normal build fails with a missing-XCFramework error
#                                     that this script's own checks didn't catch.
set -euo pipefail
cd "$(dirname "$0")"

FRESH=0
[ "${1:-}" = "--fresh" ] && FRESH=1

DERIVED="$PWD/.local-build"
LLMKIT_MANIFEST="$DERIVED/SourcePackages/checkouts/LLMkit/Package.swift"
SPARKLE_XCFRAMEWORK="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework"

if [ "$FRESH" = "1" ]; then
  echo ">> --fresh: wiping $DERIVED/SourcePackages (will re-download all SPM dependencies)"
  rm -rf "$DERIVED/SourcePackages"
fi

# Find an installed swift.org 6.2 toolchain bundle id.
TC_DIR=$(ls -d "$HOME/Library/Developer/Toolchains/"swift-6.2*xctoolchain 2>/dev/null | head -1 || true)
[ -n "$TC_DIR" ] || { echo "ERROR: no swift-6.2 toolchain in ~/Library/Developer/Toolchains"; exit 1; }
TC_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$TC_DIR/Info.plist")
echo ">> using toolchain $TC_ID for package resolution"

# Ensure whisper.xcframework exists (cached in ~/VoiceInk-Dependencies).
make setup

# Step 1: resolve packages with the 6.2 toolchain so the LLMkit 6.2 manifest parses.
# This step is ONLY needed to fetch a *new* LLMkit revision; once the checkout exists
# and is patched (step 2), later resolves work fine with the stock toolchain. If this
# step errors (a known flaky interaction between the toolchain override and xcodebuild's
# driver), don't treat it as fatal -- proceed and let the artifact check below decide
# whether recovery is actually needed.
TOOLCHAINS="$TC_ID" xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk \
  -derivedDataPath "$DERIVED" -resolvePackageDependencies || \
  echo ">> toolchain-override resolve reported an error; continuing (often harmless, see PERSONAL_BUILD.md)"

# Step 2: lower the checked-out LLMkit manifest to 6.0 so the stock toolchain accepts it.
if [ -f "$LLMKIT_MANIFEST" ]; then
  sed -i '' 's#// swift-tools-version: *6\.2#// swift-tools-version: 6.0#' "$LLMKIT_MANIFEST"
  echo ">> patched LLMkit manifest -> $(head -1 "$LLMKIT_MANIFEST")"
else
  echo "ERROR: LLMkit checkout not found at $LLMKIT_MANIFEST -- step 1 must have failed to fetch it."
  echo "       Try: ./build-local-xcode16.sh --fresh (on unmetered network)."
  exit 1
fi

# Step 2b: make sure binary artifacts (e.g. Sparkle.xcframework) actually got extracted.
# A "resolve succeeded" message does not guarantee this -- it has silently skipped
# extraction before. One plain stock-toolchain resolve (no special flags) is enough to
# fix it when the checkout/manifest are already correct; it does not need the network
# unless something is genuinely missing from the local cache.
if [ ! -d "$SPARKLE_XCFRAMEWORK" ]; then
  echo ">> Sparkle.xcframework missing after resolve, retrying with a plain resolve..."
  xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -derivedDataPath "$DERIVED" \
    -resolvePackageDependencies || true
fi
if [ ! -d "$SPARKLE_XCFRAMEWORK" ]; then
  echo "ERROR: Sparkle.xcframework still missing at:"
  echo "         $SPARKLE_XCFRAMEWORK"
  echo "       This is a known SwiftPM/Xcode-16 artifact-extraction glitch, not a code problem."
  echo "       Recovery requires re-fetching dependencies (network, several hundred MB):"
  echo "         ./build-local-xcode16.sh --fresh"
  echo "       Only run that on unmetered network."
  exit 1
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

# Re-sign with the stable local identity so TCC grants (Accessibility/Mic)
# persist across rebuilds. Run ./setup-local-signing.sh once per machine to create it.
SIGN_KEYCHAIN="$HOME/Library/Keychains/voiceink-local-signing.keychain-db"
if security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null | grep -q "VoiceInk Local Signing"; then
  security unlock-keychain -p voiceink-local "$SIGN_KEYCHAIN" 2>/dev/null || true
  codesign --force --deep --sign "VoiceInk Local Signing" --keychain "$SIGN_KEYCHAIN" \
    --entitlements "$PWD/VoiceInk/VoiceInk.local.entitlements" "$HOME/Downloads/VoiceInk.app"
  echo ">> signed with stable identity (TCC grants persist across rebuilds)"
else
  echo ">> WARNING: stable signing identity not found; app is ad-hoc signed."
  echo ">>          run ./setup-local-signing.sh to avoid re-granting permissions each build."
fi
echo ">> built: ~/Downloads/VoiceInk.app  (install: ditto over /Applications/VoiceInk.app, it keeps the signature)"

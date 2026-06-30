# Personal build (no payment, built from source)

`Beingpax/VoiceInk` doesn't accept pull requests (see `CONTRIBUTING.md`), so the
patches below live only on this fork (`orpheuslummis/VoiceInk`), on the `mybuild`
branch. This file is the recipe for building and maintaining that branch on any
machine — read this before asking "why doesn't it just build."

## Branches

- `main` — clean mirror of `Beingpax/VoiceInk:main`. Never commit to it directly.
- `mybuild` — `main` + the patches below. This is what you build from.
- `pr/middle-click-push-to-talk`, `pr/lock-to-hands-free` — static, kept for reference
  only. Not maintained, don't build from them.

## What's patched on `mybuild`, and why

1. **Local build on Xcode 16** (no Xcode 26 / macOS-26 SDK):
   - `ENABLE_NATIVE_SPEECH_ANALYZER` stripped from `project.pbxproj` — that flag gates
     the macOS-26-only `SpeechAnalyzer`/`SpeechTranscriber` backend, which needs a
     newer SDK than Xcode 16 ships. Irrelevant anyway since we use Parakeet.
   - `AddIconButton.swift` / `AppControls.swift` — `.help`/`.accessibilityLabel` calls
     wrapped in `Text(...)`; the `LocalizedStringResource` overloads of those
     modifiers are macOS-26-SDK-only.
   - `LLMkit` dependency declares `swift-tools-version: 6.2`, newer than Xcode 16's
     bundled Swift (6.0). Handled by `build-local-xcode16.sh`, not a source patch:
     it resolves packages once with a standalone Swift 6.2 toolchain (so the 6.2
     manifest can be parsed and the right revision fetched), then patches the
     *checked-out* manifest down to `6.0` and builds with the stock toolchain.
2. **Middle-click activation modes** (Toggle / Push-to-Talk / Hybrid) — middle-click
   recording (#268) only ever supported Toggle. Routes the middle-button monitor
   through the existing `RecordingShortcutModeHandler` and adds a Mode picker.
3. **Lock-to-hands-free** — while holding a Push-to-Talk/Hybrid trigger (keyboard,
   e.g. Fn, or mouse), tap Space to promote the recording to hands-free so releasing
   the trigger doesn't stop it. See `VoiceInkTests/RecordingShortcutModeHandlerTests.swift`
   for the state-machine tests.
4. **Stable local code signing** (`setup-local-signing.sh`) — ad-hoc signing changes
   the app's identity on every build, which resets macOS's Accessibility/Microphone
   grants each time. Signing with a fixed self-signed certificate keeps the grant
   across rebuilds.

## First-time setup on a new machine

```bash
git clone https://github.com/orpheuslummis/VoiceInk.git
cd VoiceInk
git checkout mybuild

# One-time: Swift 6.2 toolchain (needed only to resolve LLMkit's manifest)
# https://www.swift.org/install/macos/ -> swift-6.2.x-RELEASE-osx.pkg (~1.7GB)
installer -pkg swift-6.2.x-RELEASE-osx.pkg -target CurrentUserHomeDirectory

# One-time: stable signing identity (no prompts; uses a dedicated keychain)
./setup-local-signing.sh

# Build (downloads whisper.cpp + SwiftPM deps the first time, then incremental)
./build-local-xcode16.sh

# Install
osascript -e 'quit app "VoiceInk"' 2>/dev/null; sleep 1
ditto ~/Downloads/VoiceInk.app /Applications/VoiceInk.app
open /Applications/VoiceInk.app
```

Then grant **Accessibility** and **Microphone** once in System Settings. Because of
the stable signing identity, you should not need to grant them again after future
rebuilds *on this machine* — each machine has its own local signing identity, so this
one-time grant is per-machine, not per-build.

## Keeping `mybuild` current with upstream

```bash
./sync-with-upstream.sh
```

This fast-forwards `main` to `origin/main`, pushes it to your fork, and rebases
`mybuild` on top. If it reports a conflict, resolve it manually
(`git status` will show the conflicted files) and run `git rebase --continue`.

After a clean rebase: rebuild (`./build-local-xcode16.sh`), reinstall, then
`git push fork mybuild --force-with-lease` (force is required because rebase
rewrites commit hashes).

## Known gotcha: "no XCFramework found" for Sparkle

Occasionally — usually right after `sync-with-upstream.sh` pulls in a dependency
bump — `xcodebuild` fails with:

```
error: There is no XCFramework found at '.../artifacts/sparkle/Sparkle/Sparkle.xcframework'
```

This is a SwiftPM/Xcode-16 artifact-extraction glitch (a resolve can report success
without actually extracting the binary artifact), not a code problem.
`build-local-xcode16.sh` checks for this and retries once automatically. If it still
fails, it tells you to run:

```bash
./build-local-xcode16.sh --fresh
```

**This re-downloads all SwiftPM dependencies (several hundred MB) — only run it on
unmetered network.**

## The durable alternative: Xcode 26

All of the Xcode-16-specific patches above exist only because Xcode 16 ships Swift
6.0 and the macOS 15.x SDK. Installing Xcode 26 (native Swift 6.2, macOS 26 SDK,
~10GB) removes the LLMkit-manifest patch, the toolchain-override dance, the Sparkle
gotcha, and the two `Text(...)` SDK-availability patches entirely — `git pull &&
xcodebuild build` would just work. Worth it if the Xcode-16 patches become more
maintenance than the download is worth.

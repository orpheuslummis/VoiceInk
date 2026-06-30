#!/usr/bin/env bash
# Pull the latest Beingpax/VoiceInk and rebase your personal patches on top.
# See PERSONAL_BUILD.md for the full maintenance workflow.
set -euo pipefail
cd "$(dirname "$0")"

echo ">> fetching origin (Beingpax/VoiceInk)..."
git fetch origin

echo ">> fast-forwarding main to origin/main..."
git checkout -q main
git merge --ff-only origin/main
git push fork main

echo ">> rebasing mybuild onto main..."
git checkout -q mybuild
if git rebase main; then
  echo ""
  echo ">> rebase clean. Next steps:"
  echo "     ./build-local-xcode16.sh"
  echo "     ditto ~/Downloads/VoiceInk.app /Applications/VoiceInk.app   (after quitting VoiceInk)"
  echo "     git push fork mybuild --force-with-lease   (rebase rewrites history)"
else
  echo ""
  echo "!! rebase hit conflicts. Resolve them, then:"
  echo "     git add <files> && git rebase --continue"
  echo "   or abort with:"
  echo "     git rebase --abort"
fi

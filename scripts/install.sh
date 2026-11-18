#!/usr/bin/env bash
# Builds ClipVault and installs it into /Applications, replacing any running copy.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

if pgrep -x ClipVault >/dev/null; then
  osascript -e 'quit app "ClipVault"' >/dev/null 2>&1 || true
  for _ in {1..20}; do pgrep -x ClipVault >/dev/null || break; sleep 0.2; done
  pkill -x ClipVault 2>/dev/null || true
fi

rm -rf /Applications/ClipVault.app
ditto build/ClipVault.app /Applications/ClipVault.app
open /Applications/ClipVault.app

echo "ClipVault installed in /Applications and running — look for the clipboard icon in the menu bar."

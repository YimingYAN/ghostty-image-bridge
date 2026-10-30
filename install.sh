#!/bin/bash
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
root="$HOME/Projects/ghostty-image-bridge"
app="$HOME/Applications/Ghostty Image Bridge.app"
label=org.ghosttyimagebridge.app
agent="$HOME/Library/LaunchAgents/$label.plist"
[[ "$(cd "$(dirname "$0")" && pwd)" == "$root" ]] || { echo "Copy this folder to $root first." >&2; exit 1; }
[[ -d /Applications/Ghostty.app ]] || { echo 'Install Ghostty first.' >&2; exit 1; }
command -v uv >/dev/null || { echo 'Install uv first: brew install uv' >&2; exit 1; }
xcrun --find swiftc >/dev/null
mkdir -p "$HOME/.config/ghostty-image-bridge"
if [[ ! -f "$HOME/.config/ghostty-image-bridge/hosts.json" ]]; then
  cp "$root/hosts.example.json" "$HOME/.config/ghostty-image-bridge/hosts.json"
  echo 'Edit ~/.config/ghostty-image-bridge/hosts.json with your SSH destinations.'
fi
uv venv --python 3.13 "$root/.venv"
mkdir -p "$app/Contents/MacOS" "$HOME/Library/LaunchAgents"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Leave the original source intact; compile against this installation's venv.
sed 's|NSHomeDirectory() + "/.local/bin/python3.13"|root + "/.venv/bin/python"|' "$root/Bridge.swift" > "$work/Bridge.swift"
swiftc "$work/Bridge.swift" -o "$work/GhosttyImageBridge"
# Stop only this helper, after a successful build.
pkill -x GhosttyImageBridge 2>/dev/null || true
cp "$work/GhosttyImageBridge" "$app/Contents/MacOS/GhosttyImageBridge"
cp "$root/Info.plist" "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
"$root/.venv/bin/python" - "$agent" "$app" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'Label': 'org.ghosttyimagebridge.app',
                  'ProgramArguments': ['/usr/bin/open', sys.argv[2]],
                  'RunAtLoad': True}, f)
PY
plutil -lint "$agent"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
if launchctl bootstrap "gui/$(id -u)" "$agent"; then
  open "$app"
else
  echo 'Installed. Log into the Mac desktop and open Ghostty Image Bridge.'
fi
printf '\nEnable Accessibility for Ghostty Image Bridge, then allow Ghostty Automation on first image paste.\n'

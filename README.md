# Ghostty Image Bridge

Paste clipboard images into remote coding agents over SSH with **⌘V** in Ghostty on macOS.

This standalone menu bar add-on uploads a PNG to the active SSH host and inserts its remote file path. Use it with agents that can read image paths, such as Claude Code, Codex, or Pi. Ordinary text paste stays native. The bridge preserves the clipboard and never presses Enter.

This is an independent community project, not an official Ghostty plugin. The end-to-end workflow has been user-tested; compatibility with every agent and terminal arrangement is not guaranteed.

## Requirements

- macOS with a logged-in graphical desktop.
- Ghostty 1.4.0 or later with AppleScript support enabled (the default).
- Apple Command Line Tools (`xcode-select --install`).
- [uv](https://docs.astral.sh/uv/) and SSH/SCP.
- Noninteractive SSH authentication to your remote host.

## Install

```sh
brew install uv
brew install --cask ghostty
mkdir -p ~/Projects
git clone https://github.com/YimingYAN/ghostty-image-bridge.git ~/Projects/ghostty-image-bridge
cd ~/Projects/ghostty-image-bridge
./install.sh
```

Keep the repository at this path: the app loads its worker from it. The installer creates a private Python 3.13 environment, compiles and ad-hoc signs the app, and enables login startup. No remote service is installed.

Edit `~/.config/ghostty-image-bridge/hosts.json` to allow your exact SSH destinations:

```json
{
  "hosts": ["you@devbox.example.com", "ubuntu@another-host.example.com"]
}
```

Allow **Ghostty Image Bridge** in **System Settings → Privacy & Security → Accessibility**. If it is missing, add `~/Applications/Ghostty Image Bridge.app`. On first image paste, allow it to control Ghostty under **Automation**. These permissions must be granted separately on each Mac. Rebuilding the app may require granting them again.

## Use

1. In Ghostty, connect with `ssh you@devbox.example.com`.
2. Open your remote coding agent.
3. Copy an image or take a clipboard screenshot with **Control Shift Command 4**.
4. Press **⌘V** at the agent prompt. Keep that pane selected until the path appears.
5. Submit your prompt yourself.

Uploads remain in `~/.cache/clipboard-images/` on the remote host. Remove them when no longer needed.

## How it works

The native Swift app intercepts image-only paste events while Ghostty is frontmost. Ghostty's AppleScript API identifies the focused pane and foreground process. A Python worker checks the SSH destination against your allowlist, uploads over SSH/SCP, rechecks the pane and process, then inserts the path through Ghostty's paste-style input API.

Temporary local PNGs use mode 0600 and are removed after the worker finishes. The bridge does not modify the clipboard, log keystrokes, submit prompts, or expose a network listener. The permission to intercept keyboard input is used only for the Ghostty image paste shortcut. Remote applications receive a file path, not direct access to your clipboard.

## Current limitations

- Only plain `ssh user@host` is recognized. Shell aliases expanding to that exact form work.
- Extra SSH flags, SSH config shorthand destinations, nested SSH, and local tmux around SSH are unsupported.
- Remote tmux remains behind the same SSH process, but agent-specific behavior should be checked.
- Image pasting in local shells is intercepted and rejected; quit the bridge for Ghostty's native local image paste.
- Changing the focused pane during upload cancels insertion; an already-uploaded file may remain remotely.
- Network operations time out; interactive password or host-key prompts are unsupported. Establish trusted SSH access first.
- Copied bitmap images and screenshots are the primary input. Finder file selections are not guaranteed.
- No automatic cleanup of remote uploads is implemented.

## Troubleshooting

- **Nothing happens:** check the menu bar app and Accessibility permission. Select “Enable / Check Permissions”, or quit and reopen it.
- **Automation error:** allow Ghostty control in Privacy & Security → Automation.
- **Destination rejected:** check the exact `user@host` in `hosts.json` and use a plain SSH command.
- **Upload fails:** run `ssh -o BatchMode=yes you@host true`, then check SCP, connectivity, and host keys.
- **Session changed:** keep the original pane selected and retry.
- **Remote installation:** the app can be built over SSH, but permissions and paste verification require a desktop login.

## Move to a new Mac

Clone this repository to the same path, copy your private `hosts.json` separately, establish SSH access, and run `./install.sh`. Grant the permissions again. Do not copy Python environments or compiled app binaries between Macs.

## Disable or uninstall

Quit the app from its menu bar. Disable login startup with:

```sh
launchctl bootout "gui/$(id -u)/org.ghosttyimagebridge.app"
```

Then remove `~/Library/LaunchAgents/org.ghosttyimagebridge.app.plist` and `~/Applications/Ghostty Image Bridge.app` using Finder. Keep the source and private config if you plan to reinstall.

## Development

- `Bridge.swift`: native keyboard interception and clipboard extraction.
- `transfer.py`: destination validation, file transfer, and targeted paste.
- `install.sh`: build and install.
- `Info.plist`: app identity and Automation permission description.

Run `python3 -m unittest discover -s tests` and `shellcheck install.sh` before changing transfer or installation behavior. See [Ghostty's AppleScript documentation](https://ghostty.org/docs/features/applescript) and the installed `Ghostty.sdef` for its automation API.

## License

MIT. Contributions are welcome; please include reproduction steps and avoid uploading private images, hostnames, or credentials in bug reports.

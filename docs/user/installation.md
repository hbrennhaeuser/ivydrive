# Installation

## Requirements

- Apple Silicon Mac
- macOS 14 or later

## Install

1. Download the `.dmg` from the project's GitHub releases.
2. Open it and drag **MenuBarFS** to **Applications**.
3. Start MenuBarFS. It has no Dock icon; look for its icon in the menu bar.

To start MenuBarFS automatically, enable **Open at login** in **Settings > General**.

### First launch

Builds are not notarized by Apple, so macOS blocks the first launch of a downloaded copy. To allow it, do one of the following:

- Open **System Settings > Privacy & Security** and click **Open Anyway** next to the MenuBarFS message.
- Or remove the quarantine flag in Terminal: `xattr -dr com.apple.quarantine /Applications/MenuBarFS.app`

This is only needed once per downloaded version.

## Update

Quit MenuBarFS, then install the new version over the old one as described above. Saved network shares and settings are kept.

## Uninstall

1. Turn off **Open at login** in **Settings > General**.
2. Quit MenuBarFS from its menu.
3. Delete `/Applications/MenuBarFS.app`.
4. Optional: remove saved network shares and settings: `defaults delete com.hbrennhaeuser.menubarfs`

Alternatively, use **Reset…** in **Settings > General** before deleting the app. It removes all settings and saved network shares, turns off the login item and quits MenuBarFS.

Passwords saved in the Keychain belong to macOS and are not removed by either way. Delete them in Keychain Access if you no longer need them.

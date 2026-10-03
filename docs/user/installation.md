# Installation

## Requirements

- Apple Silicon Mac
- macOS 14 or later

## Install

1. Download the `.dmg` from the project's GitHub releases.
2. Open it and drag **IvyDrive** to **Applications**.
3. Start Ivy Drive. It has no Dock icon; look for its icon in the menu bar.

To start Ivy Drive automatically, enable **Open at login** in **Settings > General**.

### First launch

Builds are not notarized by Apple, so macOS blocks the first launch of a downloaded copy. To allow it, do one of the following:

- Open **System Settings > Privacy & Security** and click **Open Anyway** next to the Ivy Drive message.
- Or remove the quarantine flag in Terminal: `xattr -dr com.apple.quarantine /Applications/IvyDrive.app`

This is only needed once per downloaded version.

## Update

Quit Ivy Drive, then install the new version over the old one as described above. Saved network shares and settings are kept.

Coming from MenuBarFS, the app's former name: Ivy Drive imports its saved network shares and settings on the first launch. Afterwards, turn off **Open at login** in MenuBarFS and delete it, otherwise both apps start at login.

## Uninstall

1. Turn off **Open at login** in **Settings > General**.
2. Quit Ivy Drive from its menu.
3. Delete `/Applications/IvyDrive.app`.
4. Optional: remove saved network shares and settings: `defaults delete com.hbrennhaeuser.ivydrive`

Alternatively, use **Reset…** in **Settings > General** before deleting the app. It removes all settings and saved network shares, turns off the login item and quits Ivy Drive.

Passwords saved in the Keychain belong to macOS and are not removed by either way. Delete them in Keychain Access if you no longer need them.

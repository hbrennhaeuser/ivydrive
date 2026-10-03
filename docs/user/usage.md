# Usage

Adding network shares, connecting and the available options are described right where you use them, in the menu and in **Settings**. This page covers what happens in the background.

## Status colors

Each network share in the menu has a status dot:

| Color | Meaning |
|-------|---------|
| Green | Connected |
| Blue | Not connected, all enabled availability checks passed |
| Red | Not connected, at least one enabled availability check failed |
| Grey | Not connected, no checks enabled or no result yet |

Availability checks only run while the menu is open. To see the result of each check, enable **Show details when hovering over an item** in **Settings > General** and hover over a network share.

## Connecting automatically

Network shares with **Connect Automatically** enabled are connected in the background, shortly after MenuBarFS starts or after the network changes. If availability checks are enabled for a network share, they must pass first.

- **Passwords must already be in the Keychain.** Automatic connects never ask for credentials. Connect the share once by hand and let macOS save the password; from then on it can connect automatically.
- **Failures are silent.** If an automatic connect fails, MenuBarFS shows no message and tries again at the next trigger. A successful connect shows a notification.
- **Ejecting pauses it.** After you eject a network share from the MenuBarFS menu, it is not connected automatically for 5 minutes. Ejecting in Finder does not pause it.

## Passwords

MenuBarFS never stores passwords. Connecting is handled by macOS, which asks for credentials when needed and can save them to the Keychain.

The list of network shares, including server addresses, is saved unencrypted in the app's settings. For this reason a server address that contains a password is rejected.

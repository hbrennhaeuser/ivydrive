# Ivy Drive

Keep track of your network shares on macOS and reconnect them with one click.

Ivy Drive remembers your network shares (SMB, NFS, FTP, AFP, or any server address macOS can connect to), shows at a glance which ones are connected and which servers are reachable, and brings them back automatically when you start your Mac or switch networks.

![Ivy Drive screenshot](docs/images/screenshot.png)

## Features

- One-click connect for every saved network share, or all shares of a host at once
- One-click open of connected network shares in Finder
- Automatic connect on startup and when the network changes, without Finder windows or password prompts
- Availability checks (DNS, network, port), so you see whether a share is reachable before connecting
- Capacity and usage for connected network shares and local volumes
- Notifications for automatic connects and ejects
- Always available from the menu bar, with launch at login

Requires an Apple Silicon Mac with macOS 14 or later.

## Documentation

- [Installation](docs/user/installation.md): install, update and uninstall
- [Usage](docs/user/usage.md): status colors, automatic connects and passwords
- [Building from source](docs/dev/building.md)

## License

GPL-3.0-only. See [LICENSE](LICENSE).

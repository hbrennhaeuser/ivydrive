# Building

## Requirements

- macOS 14+ on Apple Silicon
- Xcode or the Xcode Command Line Tools (`xcrun swiftc`)
- Python 3 (only for building the disk image)

There is no Xcode project; the Makefile calls `swiftc` directly.

## Make targets

| Target | Action |
|--------|--------|
| `make` | Build `build/IvyDrive.app` and ad-hoc sign it |
| `make run` | Build and open the app |
| `make debug` | Build without optimization, with debug info |
| `make install` | Build and copy the app to `/Applications` |
| `make dmg` | Build `build/IvyDrive-<version>.dmg` |
| `make clean` | Remove `build/` |

`make dmg` creates a `.venv` and installs the pinned [dmgbuild](https://github.com/dmgbuild/dmgbuild) dependencies from `requirements.txt` on first use. The version comes from `Resources/Info.plist`.

The target architecture defaults to `arm64` and can be overridden:

```sh
make ARCH=x86_64
```

Only Apple Silicon is a supported target platform; other values are not tested.

## CI and releases

The `build` GitHub Actions workflow is started manually (`workflow_dispatch`). It runs `make dmg` on a macOS runner and uploads the disk image as the `IvyDrive-dmg` artifact. Releases are created manually on GitHub using that artifact.

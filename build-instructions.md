# Build Instructions

## Prerequisites

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (stable channel)
2. Install `esptool`: `pip install esptool`

## Windows

```bash
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\smartspin2k_flasher.exe`

### Creating an installer

Install [Inno Setup](https://jrsoftware.org/isdownload.php), then run:

```powershell
$env:APP_VERSION = "1.0.0"
iscc /DAPP_VERSION="$env:APP_VERSION" windows\installer.iss
```

Output: `SmartSpin2kFlasher-windows-setup.exe`

## macOS

```bash
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/smartspin2k_flasher.app`

### Creating a DMG installer

Install `create-dmg` via Homebrew, then run:

```bash
brew install create-dmg
create-dmg \
  --volname "SmartSpin2k Flasher" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "smartspin2k_flasher.app" 150 185 \
  --app-drop-link 450 185 \
  --no-internet-enable \
  "SmartSpin2kFlasher.dmg" \
  "build/macos/Build/Products/Release/smartspin2k_flasher.app"
```

## Linux

Install build dependencies first:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

Then build:

```bash
flutter build linux --release
```

Output: `build/linux/x64/release/bundle/`

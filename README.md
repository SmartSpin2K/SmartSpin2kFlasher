# SmartSpin2kFlasher[![CI](https://github.com/SmartSpin2K/SmartSpin2kFlasher/actions/workflows/build.yml/badge.svg)](https://github.com/SmartSpin2K/SmartSpin2kFlasher/actions/workflows/build.yml)

SmartSpin2kFlasher is a utility app for the [SmartSpin2k](https://github.com/doudar/SmartSpin2K)
framework and is designed to make flashing ESPs with SmartSpin2K as simple as possible by:

 * Having pre-built binaries for most operating systems.
 * Hiding all non-essential options for flashing. All necessary options for flashing
   (bootloader, flash mode) are automatically extracted from the binary.

The GUI is built with [Flutter](https://flutter.dev/) for cross-platform desktop support
(Windows, macOS, Linux).

The flashing process is done using the [esptool](https://github.com/espressif/esptool)
command-line tool by Espressif.

## Installation

It doesn't have to be installed, just double-click it and it'll start.
Check the [releases section](https://github.com/SmartSpin2K/SmartSpin2kFlasher/releases)
for downloads for your platform.

### Prerequisites

You need `esptool` installed and available in your PATH:

```bash
pip install esptool
```

## Build it yourself

If you want to build this application yourself you need to:

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (stable channel)
2. Enable desktop support:
   ```bash
   flutter config --enable-windows-desktop  # Windows
   flutter config --enable-macos-desktop    # macOS
   flutter config --enable-linux-desktop    # Linux
   ```
3. Install `esptool`: `pip install esptool`
4. Clone this repository and run:
   ```bash
   flutter pub get
   flutter run
   ```
5. To build a release binary:
   ```bash
   flutter build windows   # Windows
   flutter build macos     # macOS
   flutter build linux     # Linux
   ```

### Linux Build Dependencies

On Linux, install the required build dependencies:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

## License

[MIT](http://opensource.org/licenses/MIT) © Anthony Doud, Joel Baranick
[MIT](http://opensource.org/licenses/MIT) © Marcel Stör, Otto Winter

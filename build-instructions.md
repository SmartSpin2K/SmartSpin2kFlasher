# macOS

`pyinstaller -F -w -n SmartSpin2kFlasher -i icon.icns smartspin2kflasher/__main__.py`

# Windows

1. Start up VM
2. Install Python (3) from App Store
3. Download SmartSpin2kFlasher from GitHub
4. `pip install -e.` and `pip install pyinstaller`
5. Check with `python -m smartspin2kflasher.__main__`
6. `python -m PyInstaller.__main__ -F -w -n SmartSpin2kFlasher -i icon.ico smartspin2kflasher\__main__.py`
7. Go to `dist` folder, check SmartSpin2kFlasher.exe works.

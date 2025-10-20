import re

__version__ = "1.3.1"

import requests
import os

ESP32_DEFAULT_OTA_DATA = 'https://raw.githubusercontent.com/doudar/OTAUpdates/main/firmware.bin'
ESP32_DEFAULT_BOOTLOADER_FORMAT = 'https://raw.githubusercontent.com/espressif/arduino-esp32/' \
                                  '1.0.4/tools/sdk/bin/bootloader_$FLASH_MODE$_$FLASH_FREQ$.bin'

# Partitions and filesystem are now fetched from the latest SmartSpin2k release
# These constants indicate that special handling is needed
ESP32_DEFAULT_PARTITIONS = 'SMARTSPIN2K_RELEASE:partitions.bin'
ESP32_FILESYSTEM_URL = 'SMARTSPIN2K_RELEASE:littlefs.bin'

# https://stackoverflow.com/a/3809435/8924614
HTTP_REGEX = re.compile(r'https?://(www\.)?[-a-zA-Z0-9@:%._+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_+.~#?&/=]*)')

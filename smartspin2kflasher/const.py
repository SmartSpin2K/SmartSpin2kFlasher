import re

__version__ = "1.3.1"

import requests
import os

ESP32_DEFAULT_OTA_DATA = 'https://raw.githubusercontent.com/doudar/OTAUpdates/main/firmware.bin'
ESP32_DEFAULT_BOOTLOADER_FORMAT = 'https://raw.githubusercontent.com/espressif/arduino-esp32/' \
                                  '1.0.4/tools/sdk/bin/bootloader_$FLASH_MODE$_$FLASH_FREQ$.bin'
ESP32_DEFAULT_PARTITIONS = 'https://raw.githubusercontent.com/doudar/OTAUpdates/main/partitions.bin'
ESP32_FILESYSTEM_URL = 'https://raw.githubusercontent.com/doudar/OTAUpdates/main/LittleFS.bin'
LOCAL_FILESYSTEM = "LittleFS.bin"  # The local file name

# https://stackoverflow.com/a/3809435/8924614
HTTP_REGEX = re.compile(r'https?://(www\.)?[-a-zA-Z0-9@:%._+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_+.~#?&/=]*)')


def download_file(url, local_filename):
    # Send HTTP request to the server and download the file
    response = requests.get(url)
    if response.status_code == 200:
        # Save the file locally
        with open(local_filename, 'wb') as file:
            file.write(response.content)
        print(f"Downloaded file and saved it locally as {local_filename}")
    else:
        raise Exception(f"Failed to download the file from {url}, status code: {response.status_code}")

# Check if the file is already downloaded
if not os.path.exists(LOCAL_FILESYSTEM):
    # If not, download the file
    download_file(ESP32_FILESYSTEM_URL, LOCAL_FILESYSTEM)

# Set ESP32_FILESYSTEM to the local file path
ESP32_FILESYSTEM = LOCAL_FILESYSTEM
from __future__ import print_function

import io
import os
import sys
import zipfile

import serial

DEVNULL = open(os.devnull, 'w')


def list_serial_ports():
    # from https://github.com/pyserial/pyserial/blob/master/serial/tools/list_ports.py
    from serial.tools.list_ports import comports
    result = []
    for port, desc, info in comports():
        if not port or "VID:PID" not in info:
            continue
        split_desc = desc.split(' - ')
        if len(split_desc) == 2 and split_desc[0] == split_desc[1]:
            desc = split_desc[0]
        result.append((port, desc))
    result.sort()
    return result


def prevent_print(func, *args, **kwargs):
    orig_sys_stdout = sys.stdout
    sys.stdout = DEVNULL
    try:
        return func(*args, **kwargs)
    except serial.SerialException as err:
        from smartspin2kflasher.common import Smartspin2kflasherError

        raise Smartspin2kflasherError("Serial port closed: {}".format(err))
    finally:
        sys.stdout = orig_sys_stdout
        pass


def get_latest_smartspin2k_release():
    """Fetch the latest SmartSpin2k release information from GitHub."""
    import requests
    from smartspin2kflasher.common import Smartspin2kflasherError
    
    try:
        # Follow the redirect to get the latest release tag
        url = 'https://github.com/doudar/SmartSpin2k/releases/latest'
        response = requests.get(url, allow_redirects=True, timeout=10)
        response.raise_for_status()
        
        # Extract the tag from the final URL (e.g., https://github.com/doudar/SmartSpin2k/releases/tag/25.10.19)
        final_url = response.url
        if '/releases/tag/' not in final_url:
            raise Smartspin2kflasherError("Could not determine latest release tag")
        
        tag = final_url.split('/releases/tag/')[-1]
        
        # Now we need to find the firmware zip asset
        # Instead of using the API, we'll construct the download URL from the tag
        # The pattern is: https://github.com/doudar/SmartSpin2k/releases/download/{tag}/SmartSpin2kFirmware-{tag}.bin.zip
        download_url = f'https://github.com/doudar/SmartSpin2k/releases/download/{tag}/SmartSpin2kFirmware-{tag}.bin.zip'
        
        # Verify the URL exists by making a HEAD request
        verify_response = requests.head(download_url, allow_redirects=True, timeout=10)
        if verify_response.status_code == 404:
            raise Smartspin2kflasherError(f"Firmware zip not found at expected location: {download_url}")
        
        return download_url
    except requests.exceptions.RequestException as err:
        raise Smartspin2kflasherError("Error fetching latest SmartSpin2k release: {}".format(err))


def extract_file_from_zip_url(zip_url, filename):
    """Download a zip file and extract a specific file from it, returning a BytesIO object."""
    import requests
    from smartspin2kflasher.common import Smartspin2kflasherError
    
    try:
        # Download the zip file
        response = requests.get(zip_url, timeout=30)
        response.raise_for_status()
        
        # Open the zip from memory
        zip_data = io.BytesIO(response.content)
        with zipfile.ZipFile(zip_data, 'r') as zip_ref:
            # Find the file (case-insensitive)
            for name in zip_ref.namelist():
                if name.lower() == filename.lower():
                    file_data = zip_ref.read(name)
                    return io.BytesIO(file_data)
        
        raise Smartspin2kflasherError("File '{}' not found in zip archive".format(filename))
    except requests.exceptions.RequestException as err:
        raise Smartspin2kflasherError("Error downloading zip file: {}".format(err))
    except zipfile.BadZipFile as err:
        raise Smartspin2kflasherError("Invalid zip file: {}".format(err))

import io
import struct

import esptool

from smartspin2kflasher.const import HTTP_REGEX
from smartspin2kflasher.const import ESP32_FILESYSTEM_URL
from smartspin2kflasher.helpers import prevent_print


class Smartspin2kflasherError(Exception):
    pass


class MockEsptoolArgs(object):
    def __init__(self, flash_size, addr_filename, flash_mode, flash_freq):
        self.compress = True
        self.no_compress = False
        self.flash_size = flash_size
        self.addr_filename = addr_filename
        self.flash_mode = flash_mode
        self.flash_freq = flash_freq
        self.no_stub = False
        self.verify = False
        self.erase_all = False
        self.encrypt = False
        self.encrypt_files = None


class ChipInfo(object):
    def __init__(self, family, model, mac):
        self.family = family
        self.model = model
        self.mac = mac
        self.is_esp32 = None

    def as_dict(self):
        return {
            'family': self.family,
            'model': self.model,
            'mac': self.mac,
            'is_esp32': self.is_esp32,
        }


class ESP32ChipInfo(ChipInfo):
    def __init__(self, model, mac, num_cores, cpu_frequency, has_bluetooth, has_embedded_flash,
                 has_factory_calibrated_adc):
        super(ESP32ChipInfo, self).__init__("ESP32", model, mac)
        self.num_cores = num_cores
        self.cpu_frequency = cpu_frequency
        self.has_bluetooth = has_bluetooth
        self.has_embedded_flash = has_embedded_flash
        self.has_factory_calibrated_adc = has_factory_calibrated_adc

    def as_dict(self):
        data = ChipInfo.as_dict(self)
        data.update({
            'num_cores': self.num_cores,
            'cpu_frequency': self.cpu_frequency,
            'has_bluetooth': self.has_bluetooth,
            'has_embedded_flash': self.has_embedded_flash,
            'has_factory_calibrated_adc': self.has_factory_calibrated_adc,
        })
        return data


def read_chip_property(func, *args, **kwargs):
    try:
        return prevent_print(func, *args, **kwargs)
    except esptool.FatalError as err:
        raise Smartspin2kflasherError("Reading chip details failed: {}".format(err))


def read_chip_info(chip):
    mac = ':'.join('{:02X}'.format(x) for x in read_chip_property(chip.read_mac))
    model = read_chip_property(chip.get_chip_description)
    features = read_chip_property(chip.get_chip_features)
    num_cores = 2 if 'Dual Core' in features else 1
    frequency = next((x for x in ('160MHz', '240MHz') if x in features), '80MHz')
    has_bluetooth = 'BT' in features
    has_embedded_flash = 'Embedded Flash' in features
    has_factory_calibrated_adc = 'VRef calibration in efuse' in features
    return ESP32ChipInfo(model, mac, num_cores, frequency, has_bluetooth,
                         has_embedded_flash, has_factory_calibrated_adc)


def chip_run_stub(chip):
    try:
        return chip.run_stub()
    except esptool.FatalError as err:
        raise Smartspin2kflasherError("Error putting ESP in stub flash mode: {}".format(err))


def detect_flash_size(stub_chip):
    flash_id = read_chip_property(stub_chip.flash_id)
    return esptool.DETECTED_FLASH_SIZES.get(flash_id >> 16, '4MB')


def read_firmware_info(firmware):
    header = firmware.read(4)
    firmware.seek(0)

    magic, _, flash_mode_raw, flash_size_freq = struct.unpack("BBBB", header)
    if magic != esptool.ESPLoader.ESP_IMAGE_MAGIC:
        raise Smartspin2kflasherError(
            "The firmware binary is invalid (magic byte={:02X}, should be {:02X})"
            "".format(magic, esptool.ESPLoader.ESP_IMAGE_MAGIC))
    flash_freq_raw = flash_size_freq & 0x0F
    flash_mode = {0: 'qio', 1: 'qout', 2: 'dio', 3: 'dout'}.get(flash_mode_raw)
    flash_freq = {0: '40m', 1: '26m', 2: '20m', 0xF: '80m'}.get(flash_freq_raw)
    return flash_mode, flash_freq


def open_downloadable_binary(path):
    if hasattr(path, 'seek'):
        path.seek(0)
        return path

    if HTTP_REGEX.match(path) is not None:
        import requests

        try:
            response = requests.get(path)
            response.raise_for_status()
        except requests.exceptions.Timeout as err:
            raise Smartspin2kflasherError(
                "Timeout while retrieving firmware file '{}': {}".format(path, err))
        except requests.exceptions.RequestException as err:
            raise Smartspin2kflasherError(
                "Error while retrieving firmware file '{}': {}".format(path, err))

        binary = io.BytesIO()
        binary.write(response.content)
        binary.seek(0)
        return binary

    try:
        return open(path, 'rb')
    except IOError as err:
        raise Smartspin2kflasherError("Error opening binary '{}': {}".format(path, err))


def format_bootloader_path(path, flash_mode, flash_freq):
    return path.replace('$FLASH_MODE$', flash_mode).replace('$FLASH_FREQ$', flash_freq)


def configure_write_flash_args(info, firmware_path, flash_size,
                                bootloader_path, partitions_path, otadata_path):
    addr_filename = []
    firmware = open_downloadable_binary(firmware_path)
    flash_mode, flash_freq = read_firmware_info(firmware)
    
    if flash_freq in ('26m', '20m'):
        raise Smartspin2kflasherError(
            "No bootloader available for flash frequency {}".format(flash_freq))
            
    bootloader = open_downloadable_binary(
        format_bootloader_path(bootloader_path, flash_mode, flash_freq))
    partitions = open_downloadable_binary(partitions_path)
    otadata = open_downloadable_binary(otadata_path)
    filesystem = open_downloadable_binary(ESP32_FILESYSTEM_URL)

    addr_filename.append((0x1000, bootloader))
    addr_filename.append((0x8000, partitions))
    addr_filename.append((0xE000, otadata))
    addr_filename.append((0x10000, firmware))
    addr_filename.append((0x3D0000, filesystem))
    
    return MockEsptoolArgs(flash_size, addr_filename, flash_mode, flash_freq)


class MockConnectArgs:
    def __init__(self, baud=None):
        self.no_stub = True  # Use no-stub option to avoid address conflicts
        self.baud = baud

def detect_chip(port, baudrate=None):
    try:
        args = MockConnectArgs(baud=baudrate)
        chip = esptool.ESP32ROM(port)
        chip.connect(args)
        return chip  # Return chip directly since we're in no-stub mode
    except esptool.FatalError as err:
        raise Smartspin2kflasherError("Error connecting to ESP32: {}".format(err))

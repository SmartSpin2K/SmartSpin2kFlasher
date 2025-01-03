from __future__ import print_function

import argparse
from datetime import datetime
import sys
import time

import esptool
import serial

from smartspin2kflasher import const
from smartspin2kflasher.common import ESP32ChipInfo, Smartspin2kflasherError, chip_run_stub, \
    configure_write_flash_args, detect_chip, detect_flash_size, read_chip_info
from smartspin2kflasher.const import ESP32_DEFAULT_BOOTLOADER_FORMAT, ESP32_DEFAULT_OTA_DATA, \
    ESP32_DEFAULT_PARTITIONS
from smartspin2kflasher.helpers import list_serial_ports


def parse_args(argv):
    parser = argparse.ArgumentParser(prog='smartspin2kflasher {}'.format(const.__version__))
    parser.add_argument('-p', '--port',
                        help="Select the USB/COM port for uploading.")
    parser.add_argument('--upload-baud-rate', type=int, default=921600,
                       help="Baud rate to upload with (not for logging)")
    parser.add_argument('--bootloader',
                        help="(ESP32-only) The bootloader to flash.",
                        default=ESP32_DEFAULT_BOOTLOADER_FORMAT)
    parser.add_argument('--partitions',
                        help="(ESP32-only) The partitions to flash.",
                        default=ESP32_DEFAULT_PARTITIONS)
    parser.add_argument('--otadata',
                        help="(ESP32-only) The otadata file to flash.",
                        default=ESP32_DEFAULT_OTA_DATA)
    parser.add_argument('--no-erase',
                        help="Do not erase flash before flashing",
                        action='store_true')
    parser.add_argument('--show-logs', help="Only show logs", action='store_true')
    parser.add_argument('binary', help="The binary image to flash.")

    return parser.parse_args(argv[1:])


def select_port(args):
    if args.port is not None:
        print(u"Using '{}' as serial port.".format(args.port))
        return args.port
    ports = list_serial_ports()
    if not ports:
        raise Smartspin2kflasherError("No serial port found!")
    if len(ports) != 1:
        print("Found more than one serial port:")
        for port, desc in ports:
            print(u" * {} ({})".format(port, desc))
        print("Please choose one with the --port argument.")
        raise Smartspin2kflasherError
    print(u"Auto-detected serial port: {}".format(ports[0][0]))
    return ports[0][0]


def show_logs(serial_port):
    print("Showing logs:")
    with serial_port:
        while True:
            try:
                raw = serial_port.readline()
            except serial.SerialException:
                print("Serial port closed!")
                return
            text = raw.decode(errors='ignore')
            line = text.replace('\r', '').replace('\n', '')
            time = datetime.now().time().strftime('[%H:%M:%S]')
            message = time + line
            try:
                print(message)
            except UnicodeEncodeError:
                print(message.encode('ascii', 'backslashreplace'))


def run_smartspin2kflasher(argv):
    args = parse_args(argv)
    port = select_port(args)

    # If only showing logs, do that directly
    if args.show_logs:
        serial_port = serial.Serial(port, baudrate=115200)
        show_logs(serial_port)
        return

    # Open firmware binary
    try:
        firmware = open(args.binary, 'rb')
    except IOError as err:
        raise Smartspin2kflasherError("Error opening binary: {}".format(err))

    # Detect chip and gather information
    baudrate = serial.Serial(port).baudrate
    chip = detect_chip(port, baudrate)
    info = read_chip_info(chip)

    print("\nChip Info:")
    print(" - Chip Family: {}".format(info.family))
    print(" - Chip Model: {}".format(info.model))
    print(" - Number of Cores: {}".format(info.num_cores))
    print(" - Max CPU Frequency: {}".format(info.cpu_frequency))
    print(" - Has Bluetooth: {}".format('YES' if info.has_bluetooth else 'NO'))
    print(" - Has Embedded Flash: {}".format('YES' if info.has_embedded_flash else 'NO'))
    print(" - Has Factory-Calibrated ADC: {}".format(
        'YES' if info.has_factory_calibrated_adc else 'NO'))
    print(" - MAC Address: {}".format(info.mac))

    stub_chip = chip_run_stub(chip)
    flash_size = None

    # Try changing the baud rate if it's different from 115200
    if args.upload_baud_rate != 115200:
        try:
            stub_chip.change_baud(args.upload_baud_rate)
        except esptool.FatalError as err:
            raise Smartspin2kflasherError("Error changing ESP upload baud rate: {}".format(err))

        # Verify if the higher baud rate works by checking the flash size
        try:
            flash_size = detect_flash_size(stub_chip)
        except Smartspin2kflasherError as err:
            print("Chip does not support baud rate {}, changing back to 115200".format(args.upload_baud_rate))
            stub_chip._port.close()
            chip = detect_chip(port, baudrate)
            stub_chip = chip_run_stub(chip)

    if flash_size is None:
        flash_size = detect_flash_size(stub_chip)

    print(" - Flash Size: {}".format(flash_size))

    # Configure write flash arguments for firmware
    firmware_mock_args = configure_write_flash_args(info, firmware, flash_size, 
                                                    args.bootloader, args.partitions, 
                                                    args.otadata)

    print(" - Flash Mode: {}".format(firmware_mock_args.flash_mode))
    print(" - Flash Frequency: {}Hz".format(firmware_mock_args.flash_freq.upper()))

    # Set flash parameters
    try:
        stub_chip.flash_set_parameters(esptool.flash_size_bytes(flash_size))
    except esptool.FatalError as err:
        raise Smartspin2kflasherError("Error setting flash parameters: {}".format(err))
    
    # Flash firmware and filesystem in a single operation

    try:
        mock_args = configure_write_flash_args(info, firmware, flash_size, args.bootloader, args.partitions, args.otadata)
        mock_args.force = True
        mock_args.chip = "esp32"
        esptool.write_flash(stub_chip, mock_args)
        esptool.write_mem
    except esptool.FatalError as err:
        raise Smartspin2kflasherError("Error while writing flash: {}".format(err))

    print("Hard Resetting...")
    stub_chip.hard_reset()

    print("Done! Flashing is complete!")
    print()

    # Close port after flashing
    try:
        stub_chip._port.close()
    except:
        pass

def main():
    try:
        if len(sys.argv) <= 1:
            from smartspin2kflasher import gui

            return gui.main() or 0
        return run_smartspin2kflasher(sys.argv) or 0
    except Smartspin2kflasherError as err:
        msg = str(err)
        if msg:
            print(msg)
        return 1
    except KeyboardInterrupt:
        return 1


if __name__ == "__main__":
    sys.exit(main())

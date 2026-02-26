const String appVersion = '1.3.1';

// Standard ESP32 OTA data (boot_app0.bin) from arduino-esp32
const String esp32DefaultOtaData =
    'https://raw.githubusercontent.com/espressif/arduino-esp32/master/tools/partitions/boot_app0.bin';

// Bootloader, partitions, and filesystem are all fetched from the latest SmartSpin2k release
const String esp32DefaultBootloader = 'SMARTSPIN2K_RELEASE:bootloader.bin';
const String esp32DefaultPartitions = 'SMARTSPIN2K_RELEASE:partitions.bin';
const String esp32FilesystemUrl = 'SMARTSPIN2K_RELEASE:littlefs.bin';

// Flash addresses for ESP32 (min_spiffs partition layout)
const int bootloaderAddress = 0x1000;
const int partitionsAddress = 0x8000;
const int otadataAddress = 0xE000;
const int firmwareAddress = 0x10000; // app0 (ota_0)
const int firmware1Address = 0x1F0000; // app1 (ota_1)
const int filesystemAddress = 0x3D0000;

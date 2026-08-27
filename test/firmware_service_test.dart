import 'package:flutter_test/flutter_test.dart';
import 'package:smartspin2k_flasher/models/chip_info.dart';
import 'package:smartspin2k_flasher/services/firmware_service.dart';

void main() {
  group('FirmwareService.factoryImageSetFor', () {
    test('selects the original ESP32 factory image and LittleFS map', () {
      final imageSet = FirmwareService.factoryImageSetFor(
        SmartSpin2kChip.esp32,
      );

      expect(imageSet.factoryFilename, 'firmware.factory.bin');
      expect(imageSet.littlefsFilename, 'littlefs.bin');
      expect(imageSet.littlefsAddress, 0x3D0000);
    });

    test('selects the ESP32-S3 factory image and LittleFS map', () {
      final imageSet = FirmwareService.factoryImageSetFor(
        SmartSpin2kChip.esp32s3,
      );

      expect(imageSet.factoryFilename, 'S3firmware.factory.bin');
      expect(imageSet.littlefsFilename, 'S3littlefs.bin');
      expect(imageSet.littlefsAddress, 0x860000);
    });
  });
}

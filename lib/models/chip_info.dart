/// ESP targets supported by SmartSpin2k release artifacts.
enum SmartSpin2kChip {
  esp32('ESP32', 'esp32'),
  esp32s3('ESP32-S3', 'esp32s3');

  const SmartSpin2kChip(this.displayName, this.esptoolName);

  final String displayName;
  final String esptoolName;
}

class ChipInfo {
  final String family;
  final String model;
  final String mac;

  ChipInfo({required this.family, required this.model, required this.mac});

  Map<String, dynamic> toMap() => {
    'family': family,
    'model': model,
    'mac': mac,
  };
}

class ESP32ChipInfo extends ChipInfo {
  final int numCores;
  final String cpuFrequency;
  final bool hasBluetooth;
  final bool hasEmbeddedFlash;
  final bool hasFactoryCalibratedAdc;

  ESP32ChipInfo({
    required super.model,
    required super.mac,
    required this.numCores,
    required this.cpuFrequency,
    required this.hasBluetooth,
    required this.hasEmbeddedFlash,
    required this.hasFactoryCalibratedAdc,
  }) : super(family: 'ESP32');

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'num_cores': numCores,
    'cpu_frequency': cpuFrequency,
    'has_bluetooth': hasBluetooth,
    'has_embedded_flash': hasEmbeddedFlash,
    'has_factory_calibrated_adc': hasFactoryCalibratedAdc,
  };
}

class FlashConfig {
  final String port;
  final String? firmwarePath;
  final int baudRate;

  FlashConfig({required this.port, this.firmwarePath, this.baudRate = 921600});
}

/// SmartSpin2k board types recognisable from their USB IDs, in order of
/// preference when several are connected.
enum SmartSpin2kUsbBoard {
  /// ESP32-S3 boards use the chip's native USB (Espressif VID 0x303A).
  esp32s3('ESP32-S3'),

  /// Older ESP32 boards use a Silicon Labs CP210x USB-to-UART bridge.
  esp32Cp210x('ESP32');

  const SmartSpin2kUsbBoard(this.displayName);

  final String displayName;

  static SmartSpin2kUsbBoard? fromUsbIds(int? vendorId, int? productId) {
    if (vendorId == 0x303A && productId == 0x1001) return esp32s3;
    if (vendorId == 0x10C4 && productId == 0xEA60) return esp32Cp210x;
    return null;
  }
}

class SerialPortInfo {
  final String port;
  final String description;
  final SmartSpin2kUsbBoard? board;

  SerialPortInfo({required this.port, required this.description, this.board});

  @override
  String toString() => '$port ($description)';
}

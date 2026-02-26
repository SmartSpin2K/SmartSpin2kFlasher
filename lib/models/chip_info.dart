class ChipInfo {
  final String family;
  final String model;
  final String mac;

  ChipInfo({
    required this.family,
    required this.model,
    required this.mac,
  });

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

  FlashConfig({
    required this.port,
    this.firmwarePath,
    this.baudRate = 921600,
  });
}

class SerialPortInfo {
  final String port;
  final String description;

  SerialPortInfo({required this.port, required this.description});

  @override
  String toString() => '$port ($description)';
}

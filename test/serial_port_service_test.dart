import 'package:flutter_test/flutter_test.dart';
import 'package:smartspin2k_flasher/models/models.dart';
import 'package:smartspin2k_flasher/services/serial_port_service.dart';

SerialPortInfo _port(String name, [SmartSpin2kUsbBoard? board]) =>
    SerialPortInfo(port: name, description: name, board: board);

void main() {
  group('SmartSpin2kUsbBoard.fromUsbIds', () {
    test('recognises ESP32-S3 native USB', () {
      expect(
        SmartSpin2kUsbBoard.fromUsbIds(0x303A, 0x1001),
        SmartSpin2kUsbBoard.esp32s3,
      );
    });

    test('recognises CP210x bridge on older boards', () {
      expect(
        SmartSpin2kUsbBoard.fromUsbIds(0x10C4, 0xEA60),
        SmartSpin2kUsbBoard.esp32Cp210x,
      );
    });

    test('ignores other and missing IDs', () {
      expect(SmartSpin2kUsbBoard.fromUsbIds(0x1A86, 0x7523), isNull);
      expect(SmartSpin2kUsbBoard.fromUsbIds(null, null), isNull);
    });
  });

  group('SerialPortService.choosePort', () {
    final s3 = _port('COM4', SmartSpin2kUsbBoard.esp32s3);
    final cp210x = _port('COM3', SmartSpin2kUsbBoard.esp32Cp210x);
    final other = _port('COM1');

    test('returns null when there are no ports', () {
      expect(SerialPortService.choosePort([], 'COM4'), isNull);
    });

    test('keeps the preferred port when it is a SmartSpin2k board', () {
      expect(SerialPortService.choosePort([other, cp210x, s3], 'COM3'), 'COM3');
    });

    test('switches from a non-board port to a detected board', () {
      expect(SerialPortService.choosePort([other, cp210x], 'COM1'), 'COM3');
    });

    test('prefers the S3 when several boards are connected', () {
      expect(SerialPortService.choosePort([other, cp210x, s3], null), 'COM4');
    });

    test('falls back to the preferred port, then the first port', () {
      final bt = _port('COM5');
      expect(SerialPortService.choosePort([other, bt], 'COM5'), 'COM5');
      expect(SerialPortService.choosePort([other, bt], 'COM9'), 'COM1');
    });
  });
}

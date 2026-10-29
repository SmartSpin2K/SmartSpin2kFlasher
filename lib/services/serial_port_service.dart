import 'dart:io';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../models/models.dart';

class SerialPortService {
  /// List available serial ports by scanning system COM/tty ports.
  static List<SerialPortInfo> listSerialPorts() {
    final ports = <SerialPortInfo>[];

    if (Platform.isWindows) {
      // On Windows, query the registry for COM ports
      try {
        final result = Process.runSync('powershell', [
          '-Command',
          'Get-CimInstance -ClassName Win32_SerialPort | '
              'Select-Object DeviceID, Caption | '
              'ForEach-Object { "\$(\$_.DeviceID)|\$(\$_.Caption)" }',
        ]);
        if (result.exitCode == 0) {
          final output = (result.stdout as String).trim();
          if (output.isNotEmpty) {
            for (final line in output.split('\n')) {
              final parts = line.trim().split('|');
              if (parts.length >= 2) {
                ports.add(SerialPortInfo(
                  port: parts[0].trim(),
                  description: parts[1].trim(),
                ));
              }
            }
          }
        }
        // Also check for USB serial devices via PnP
        final result2 = Process.runSync('powershell', [
          '-Command',
          'Get-CimInstance -ClassName Win32_PnPEntity | '
              'Where-Object { \$_.Name -match "COM\\d+" } | '
              'ForEach-Object { '
              'if (\$_.Name -match "(COM\\d+)") { '
              '"\$(\$Matches[1])|\$(\$_.Name)" '
              '} }',
        ]);
        if (result2.exitCode == 0) {
          final output = (result2.stdout as String).trim();
          if (output.isNotEmpty) {
            for (final line in output.split('\n')) {
              final parts = line.trim().split('|');
              if (parts.length >= 2) {
                final port = parts[0].trim();
                // Skip if already found
                if (!ports.any((p) => p.port == port)) {
                  ports.add(SerialPortInfo(
                    port: port,
                    description: parts[1].trim(),
                  ));
                }
              }
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isLinux) {
      // On Linux, look for /dev/ttyUSB* and /dev/ttyACM* devices
      try {
        final devDir = Directory('/dev');
        if (devDir.existsSync()) {
          for (final entity in devDir.listSync()) {
            final name = entity.path.split('/').last;
            if (name.startsWith('ttyUSB') || name.startsWith('ttyACM')) {
              ports.add(SerialPortInfo(
                port: entity.path,
                description: name,
              ));
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isMacOS) {
      // On macOS, look for /dev/cu.* devices
      try {
        final devDir = Directory('/dev');
        if (devDir.existsSync()) {
          for (final entity in devDir.listSync()) {
            final name = entity.path.split('/').last;
            if (name.startsWith('cu.') && name != 'cu.Bluetooth-Incoming-Port') {
              ports.add(SerialPortInfo(
                port: entity.path,
                description: name,
              ));
            }
          }
        }
      } catch (_) {}
    }

    ports.sort((a, b) => a.port.compareTo(b.port));
    return ports
        .map(
          (p) => SerialPortInfo(
            port: p.port,
            description: p.description,
            board: _detectBoard(p.port),
          ),
        )
        .toList();
  }

  /// Identify a SmartSpin2k board from the port's USB vendor/product IDs.
  static SmartSpin2kUsbBoard? _detectBoard(String port) {
    SerialPort? serialPort;
    try {
      serialPort = SerialPort(port);
      if (serialPort.transport != SerialPortTransport.usb) return null;
      return SmartSpin2kUsbBoard.fromUsbIds(
        serialPort.vendorId,
        serialPort.productId,
      );
    } catch (_) {
      return null;
    } finally {
      serialPort?.dispose();
    }
  }

  /// Pick the port to select: keep [preferred] if it is a SmartSpin2k board,
  /// otherwise the best detected board (S3 first), otherwise [preferred] if it
  /// still exists, otherwise the first port.
  static String? choosePort(List<SerialPortInfo> ports, String? preferred) {
    if (ports.isEmpty) return null;
    final current = ports.where((p) => p.port == preferred);
    if (current.isNotEmpty && current.first.board != null) return preferred;
    final boards = ports.where((p) => p.board != null).toList()
      ..sort((a, b) => a.board!.index.compareTo(b.board!.index));
    if (boards.isNotEmpty) return boards.first.port;
    if (current.isNotEmpty) return preferred;
    return ports.first.port;
  }
}

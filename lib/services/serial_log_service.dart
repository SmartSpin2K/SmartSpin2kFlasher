import 'dart:async';
import 'dart:convert';

import 'package:flutter_libserialport/flutter_libserialport.dart';

/// Service for reading serial port logs.
class SerialLogService {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<String>? _dataSub;
  bool _stopped = false;

  /// Start reading logs from a serial port.
  /// Uses a platform-appropriate method to read serial data.
  Future<void> startLogs({
    required String port,
    required void Function(String) onData,
    int baudRate = 115200,
    void Function(Object? error)? onClosed,
  }) async {
    await stopLogs();
    _stopped = false;
    var closedNotified = false;
    void notifyClosed(Object? error) {
      if (_stopped || closedNotified) return;
      closedNotified = true;
      onClosed?.call(error);
    }

    final serialPort = SerialPort(port);
    if (!serialPort.openReadWrite()) {
      serialPort.dispose();
      throw Exception('Could not open $port: ${SerialPort.lastError}');
    }

    try {
      final config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..setFlowControl(SerialPortFlowControl.none);
      serialPort.config = config;

      _port = serialPort;
      _reader = SerialPortReader(serialPort);
      _dataSub = _reader!.stream
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            (line) => onData('$line\n'),
            onError: (Object error) => notifyClosed(error),
            onDone: () => notifyClosed(null),
          );
    } catch (_) {
      serialPort.close();
      serialPort.dispose();
      rethrow;
    }
  }

  /// Stop reading logs.
  Future<void> stopLogs() async {
    _stopped = true;
    await _dataSub?.cancel();
    _dataSub = null;
    _reader?.close();
    _reader = null;
    _port?.close();
    _port?.dispose();
    _port = null;
  }

  bool get isRunning => _port?.isOpen ?? false;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Service for reading serial port logs.
class SerialLogService {
  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  /// Start reading logs from a serial port.
  /// Uses a platform-appropriate method to read serial data.
  Future<void> startLogs({
    required String port,
    required void Function(String) onData,
    int baudRate = 115200,
  }) async {
    await stopLogs();

    if (Platform.isWindows) {
      // On Windows, use PowerShell to read from the COM port
      _process = await Process.start('powershell', [
        '-Command',
        '''
        \$port = New-Object System.IO.Ports.SerialPort "$port", $baudRate
        \$port.Open()
        try {
          while (\$port.IsOpen) {
            try {
              \$line = \$port.ReadLine()
              Write-Output \$line
            } catch { }
          }
        } finally {
          \$port.Close()
        }
        '''
      ]);
    } else {
      // On Linux/macOS, use stty + cat
      // macOS uses -f while GNU/Linux uses -F. Configure raw mode so stty
      // does not translate or echo bytes from the device.
      final sttyResult = await Process.run('stty', [
        Platform.isMacOS ? '-f' : '-F',
        port,
        baudRate.toString(),
        'raw',
        '-echo',
      ]);
      if (sttyResult.exitCode != 0) {
        throw ProcessException(
          'stty',
          [port, baudRate.toString()],
          sttyResult.stderr.toString().trim(),
          sttyResult.exitCode,
        );
      }
      _process = await Process.start('cat', [port]);
    }

    final lineDecoder = const Utf8Decoder(
      allowMalformed: true,
    ).fuse(const LineSplitter());
    _stdoutSub = _process!.stdout
        .transform(lineDecoder)
        .listen((line) => onData('$line\n'));
    _stderrSub = _process!.stderr
        .transform(lineDecoder)
        .listen((line) => onData('$line\n'));
  }

  /// Stop reading logs.
  Future<void> stopLogs() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process?.kill();
    _process = null;
  }

  bool get isRunning => _process != null;
}

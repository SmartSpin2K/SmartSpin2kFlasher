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
      // First configure the port
      await Process.run('stty', ['-F', port, baudRate.toString()]);
      _process = await Process.start('cat', [port]);
    }

    _stdoutSub = _process!.stdout.transform(utf8.decoder).listen(onData);
    _stderrSub = _process!.stderr.transform(utf8.decoder).listen(onData);
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

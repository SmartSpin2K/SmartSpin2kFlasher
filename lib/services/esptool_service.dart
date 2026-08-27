import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/chip_info.dart';

/// Service that manages calling esptool as a subprocess for ESP32 flashing.
class EsptoolService {
  /// Locate esptool executable, checking bundled location first.
  static Future<String> findEsptool() async {
    // Check bundled esptool next to the running executable
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundledPaths = Platform.isWindows
        ? [p.join(exeDir, 'esptool', 'esptool.exe')]
        : [p.join(exeDir, 'esptool', 'esptool')];

    // On macOS .app bundles, also check Resources
    if (Platform.isMacOS) {
      final resourcesDir = p.join(p.dirname(exeDir), 'Resources');
      bundledPaths.add(p.join(resourcesDir, 'esptool', 'esptool'));
    }

    for (final path in bundledPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    // Fallback: find esptool in PATH. A `pip3 install esptool` on macOS
    // commonly installs only the Python module in a user site-packages
    // directory; its console-script directory is not inherited by app debug
    // sessions. The explicit system-Python path also works when an IDE starts
    // the debug process with a minimal PATH.
    final candidates = [
      'esptool',
      'esptool.py',
      if (Platform.isWindows) 'esptool.exe',
      if (Platform.isMacOS) '/usr/bin/python3 -m esptool',
      if (!Platform.isWindows) 'python3 -m esptool',
      if (!Platform.isWindows) 'python -m esptool',
    ];

    for (final candidate in candidates) {
      try {
        final result = await Process.run(candidate, [
          'version',
        ], runInShell: true);
        if (result.exitCode == 0) {
          return candidate;
        }
      } catch (_) {}
    }

    throw Exception(
      'esptool not found. Install it with: pip install esptool\n'
      'Or download from: https://github.com/espressif/esptool',
    );
  }

  /// Run esptool with the given arguments, streaming output.
  static Future<int> runEsptool({
    required List<String> args,
    required void Function(String) onOutput,
    String? esptoolPath,
  }) async {
    final esptool = esptoolPath ?? await findEsptool();
    final parts = esptool.split(' ');
    final executable = parts.first;
    final baseArgs = parts.skip(1).toList();

    onOutput('Running: $esptool ${args.join(' ')}\n');

    final process = await Process.start(executable, [...baseArgs, ...args]);

    final stdoutCompleter = Completer<void>();
    final stderrCompleter = Completer<void>();

    process.stdout
        .transform(utf8.decoder)
        .listen(
          (data) => onOutput(data),
          onDone: () => stdoutCompleter.complete(),
        );
    process.stderr
        .transform(utf8.decoder)
        .listen(
          (data) => onOutput(data),
          onDone: () => stderrCompleter.complete(),
        );

    await Future.wait([stdoutCompleter.future, stderrCompleter.future]);
    return await process.exitCode;
  }

  /// Detect the ESP target connected to [port].
  static Future<SmartSpin2kChip> detectChip({
    required String port,
    required void Function(String) onOutput,
  }) async {
    final output = StringBuffer();
    final exitCode = await runEsptool(
      args: ['--port', port, 'chip-id'],
      onOutput: (data) {
        output.write(data);
        onOutput(data);
      },
    );

    final chipOutput = output.toString();
    if (exitCode != 0) {
      throw Exception(
        'Unable to detect chip type (esptool exited with code $exitCode)',
      );
    }
    if (RegExp(r'ESP32-S3', caseSensitive: false).hasMatch(chipOutput)) {
      return SmartSpin2kChip.esp32s3;
    }
    // Check S3 before ESP32 because the S3 output contains both strings.
    if (RegExp(r'ESP32(?!-)', caseSensitive: false).hasMatch(chipOutput)) {
      return SmartSpin2kChip.esp32;
    }
    throw Exception(
      'Unsupported chip. SmartSpin2k supports ESP32 and ESP32-S3 boards.',
    );
  }

  /// Flash a complete SmartSpin2k installation in one esptool invocation.
  ///
  /// Factory images include the bootloader, partitions and application. The
  /// release keeps LittleFS separate, so it is written alongside the factory
  /// image to produce a complete clean install.
  static Future<void> flashDevice({
    required String port,
    required SmartSpin2kChip chip,
    required String factoryFirmwarePath,
    String? littlefsPath,
    int? littlefsAddress,
    required void Function(String) onOutput,
    int baudRate = 921600,
  }) async {
    final esptool = await findEsptool();
    onOutput('Preparing complete ${chip.displayName} installation...\n');

    final factoryFile = File(factoryFirmwarePath);
    if (!await factoryFile.exists()) {
      throw Exception('Factory firmware file not found: $factoryFirmwarePath');
    }

    // Keep the flash settings embedded in the factory bootloader intact.
    final args = [
      '--chip',
      chip.esptoolName,
      '--port',
      port,
      '--baud',
      baudRate.toString(),
      '--before',
      'default-reset',
      '--after',
      'hard-reset',
      'write-flash',
      '-z',
      '--flash-mode',
      'keep',
      '--flash-freq',
      'keep',
      '--flash-size',
      'keep',
      '0x0',
      factoryFirmwarePath,
    ];
    if (littlefsPath != null && littlefsAddress != null) {
      if (!await File(littlefsPath).exists()) {
        throw Exception('LittleFS file not found: $littlefsPath');
      }
      args.addAll(['0x${littlefsAddress.toRadixString(16)}', littlefsPath]);
    }

    onOutput('\nFlashing ${chip.displayName}...\n');

    final exitCode = await runEsptool(
      args: args,
      onOutput: onOutput,
      esptoolPath: esptool,
    );

    if (exitCode != 0) {
      throw Exception('esptool exited with code $exitCode');
    }

    onOutput('\nDone! Flashing is complete!\n');
  }

  /// Read chip info from ESP32.
  static Future<void> readChipInfo({
    required String port,
    required void Function(String) onOutput,
  }) async {
    await runEsptool(args: ['--port', port, 'chip-id'], onOutput: onOutput);
  }
}

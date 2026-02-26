import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../constants.dart';
import 'firmware_service.dart';

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

    // Fallback: find esptool in PATH
    final candidates = [
      'esptool',
      'esptool.py',
      if (Platform.isWindows) 'esptool.exe',
    ];

    for (final candidate in candidates) {
      try {
        final result = await Process.run(
          candidate,
          ['version'],
          runInShell: true,
        );
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

    final process = await Process.start(
      executable,
      [...baseArgs, ...args],
    );

    final stdoutCompleter = Completer<void>();
    final stderrCompleter = Completer<void>();

    process.stdout.transform(utf8.decoder).listen(
      (data) => onOutput(data),
      onDone: () => stdoutCompleter.complete(),
    );
    process.stderr.transform(utf8.decoder).listen(
      (data) => onOutput(data),
      onDone: () => stderrCompleter.complete(),
    );

    await Future.wait([stdoutCompleter.future, stderrCompleter.future]);
    return await process.exitCode;
  }

  /// Flash firmware to ESP32 device.
  static Future<void> flashDevice({
    required String port,
    required String firmwarePath,
    required void Function(String) onOutput,
    String? releaseTag,
    int baudRate = 921600,
    bool eraseFlash = true,
  }) async {
    final esptool = await findEsptool();

    onOutput('Preparing firmware files...\n');

    // Download OTA data (boot_app0.bin)
    final otaData = await FirmwareService.downloadBinary(
      esp32DefaultOtaData,
      onLog: onOutput,
    );
    final otaDataPath = await FirmwareService.saveTempFile(otaData, 'boot_app0.bin');

    // Extract supporting files from the specified release or latest
    Future<Uint8List> extractFile(String filename) {
      if (releaseTag != null) {
        return FirmwareService.extractFileFromReleaseTag(
          releaseTag,
          filename,
          onLog: onOutput,
        );
      }
      return FirmwareService.extractFileFromRelease(
        filename,
        onLog: onOutput,
      );
    }

    final bootloader = await extractFile('bootloader.bin');
    final bootloaderPath = await FirmwareService.saveTempFile(bootloader, 'bootloader.bin');

    final partitions = await extractFile('partitions.bin');
    final partitionsPath = await FirmwareService.saveTempFile(partitions, 'partitions.bin');

    final filesystem = await extractFile('littlefs.bin');
    final filesystemPath = await FirmwareService.saveTempFile(filesystem, 'littlefs.bin');

    // Read firmware header to determine flash mode and frequency
    final firmwareFile = File(firmwarePath);
    final header = await firmwareFile.openRead(0, 4).fold<List<int>>(
      [],
      (prev, chunk) => [...prev, ...chunk],
    );

    if (header.length < 4 || header[0] != 0xE9) {
      throw Exception(
        'Invalid firmware binary (magic byte=0x${header[0].toRadixString(16)}, expected 0xE9)',
      );
    }

    final flashModeRaw = header[2];
    final flashSizeFreq = header[3];
    final flashFreqRaw = flashSizeFreq & 0x0F;

    final flashMode = {0: 'qio', 1: 'qout', 2: 'dio', 3: 'dout'}[flashModeRaw] ?? 'dio';
    final flashFreq = {0: '40m', 1: '26m', 2: '20m', 0x0F: '80m'}[flashFreqRaw] ?? '40m';

    onOutput('\nFlash Mode: $flashMode\n');
    onOutput('Flash Frequency: ${flashFreq.toUpperCase()}Hz\n');

    // Build esptool command (use hyphenated flags for esptool v5+)
    final args = [
      '--chip', 'esp32',
      '--port', port,
      '--baud', baudRate.toString(),
      '--before', 'default-reset',
      '--after', 'hard-reset',
      'write-flash',
      '-z',
      '--flash-mode', flashMode,
      '--flash-freq', flashFreq,
      '--flash-size', 'detect',
      '0x1000', bootloaderPath,
      '0x8000', partitionsPath,
      '0xe000', otaDataPath,
      '0x10000', firmwarePath, // app0 (ota_0)
      '0x1f0000', firmwarePath, // app1 (ota_1)
      '0x3d0000', filesystemPath,
    ];

    onOutput('\nFlashing ESP32...\n');

    final exitCode = await runEsptool(
      args: args,
      onOutput: onOutput,
      esptoolPath: esptool,
    );

    // Clean up temp files
    for (final path in [bootloaderPath, partitionsPath, otaDataPath, filesystemPath]) {
      try {
        await File(path).delete();
        await File(path).parent.delete();
      } catch (_) {}
    }

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
    await runEsptool(
      args: ['--chip', 'esp32', '--port', port, 'chip_id'],
      onOutput: onOutput,
    );
  }
}

/// Downloads the latest esptool release from GitHub for the current (or specified) platform
/// and extracts it to assets/esptool/.
///
/// Usage:
///   dart run tool/download_esptool.dart [platform]
///
/// Platform can be: windows, linux, macos
/// If omitted, auto-detects the current platform.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

const _repo = 'espressif/esptool';
const _outputDir = 'assets/esptool';

// v5.3.1's macOS PyInstaller bundle contains a Python.framework that fails
// Gatekeeper validation when extracted at runtime. Espressif re-uploaded the
// v5.3.0 macOS bundle after correcting its notarization.
const _macosVersion = 'v5.3.0';

Future<void> main(List<String> args) async {
  final platform = args.isNotEmpty ? args[0] : _detectPlatform();
  print('Downloading latest esptool for $platform...');

  final release = await _getRelease(platform);
  final version = release['tag_name'] as String;
  print('Latest release: $version');

  final assetName = _getAssetName(version, platform);
  final asset = (release['assets'] as List).firstWhere(
    (a) => a['name'] == assetName,
    orElse: () =>
        throw Exception('Asset $assetName not found in release $version'),
  );

  final downloadUrl = asset['browser_download_url'] as String;
  print('Downloading $assetName...');

  final response = await http.get(Uri.parse(downloadUrl));
  if (response.statusCode != 200) {
    throw Exception('Failed to download: HTTP ${response.statusCode}');
  }
  print(
    'Downloaded ${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(1)} MB',
  );

  // Clean output directory
  final outputDir = Directory(_outputDir);
  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);

  // Extract
  print('Extracting to $_outputDir/...');
  if (assetName.endsWith('.zip')) {
    _extractZip(response.bodyBytes, outputDir.path);
  } else if (assetName.endsWith('.tar.gz')) {
    _extractTarGz(response.bodyBytes, outputDir.path);
  }

  // Verify esptool binary exists
  final esptoolBinary = platform == 'windows' ? 'esptool.exe' : 'esptool';
  final esptoolFile = File('${outputDir.path}/$esptoolBinary');
  if (!esptoolFile.existsSync()) {
    throw Exception('esptool binary not found at ${esptoolFile.path}');
  }

  // Make executable on Unix
  if (platform != 'windows') {
    Process.runSync('chmod', ['+x', esptoolFile.path]);
  }

  print('✓ esptool $version for $platform ready at $_outputDir/$esptoolBinary');
}

String _detectPlatform() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  throw Exception('Unsupported platform');
}

Future<Map<String, dynamic>> _getRelease(String platform) async {
  final endpoint = platform == 'macos'
      ? 'releases/tags/$_macosVersion'
      : 'releases/latest';
  final response = await http.get(
    Uri.parse('https://api.github.com/repos/$_repo/$endpoint'),
    headers: {'Accept': 'application/vnd.github.v3+json'},
  );
  if (response.statusCode != 200) {
    throw Exception('GitHub API error: HTTP ${response.statusCode}');
  }
  return json.decode(response.body) as Map<String, dynamic>;
}

String _getAssetName(String version, String platform) {
  switch (platform) {
    case 'windows':
      return 'esptool-$version-windows-amd64.zip';
    case 'linux':
      return 'esptool-$version-linux-amd64.tar.gz';
    case 'macos':
      return 'esptool-$version-macos-amd64.tar.gz';
    default:
      throw Exception('Unsupported platform: $platform');
  }
}

void _extractZip(List<int> bytes, String outputDir) {
  final archive = ZipDecoder().decodeBytes(bytes);
  _extractArchive(archive, outputDir);
}

void _extractTarGz(List<int> bytes, String outputDir) {
  final tempDir = Directory.systemTemp.createTempSync('esptool_extract_');
  final archiveFile = File('${tempDir.path}/esptool.tar.gz');

  try {
    archiveFile.writeAsBytesSync(bytes);
    final result = Process.runSync('tar', [
      '-xzf',
      archiveFile.path,
      '--strip-components',
      '1',
      '-C',
      outputDir,
    ]);
    if (result.exitCode != 0) {
      throw Exception('Failed to extract esptool: ${result.stderr}');
    }
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}

/// Extracts archive files, flattening the top-level directory so binaries
/// end up directly in [outputDir].
void _extractArchive(Archive archive, String outputDir) {
  for (final file in archive) {
    if (file.isFile) {
      // Strip the top-level directory (e.g., "esptool-v5.2.0-win64/")
      final parts = file.name.split('/');
      final flatName = parts.length > 1
          ? parts.sublist(1).join('/')
          : file.name;
      if (flatName.isEmpty) continue;

      final outFile = File('$outputDir/$flatName');
      outFile.parent.createSync(recursive: true);
      outFile.writeAsBytesSync(file.content as List<int>);
    }
  }
}

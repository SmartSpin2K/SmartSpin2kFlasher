import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

/// Represents a SmartSpin2k firmware release from GitHub.
class FirmwareRelease {
  final String tag;
  final String name;
  final String publishedAt;

  const FirmwareRelease({
    required this.tag,
    required this.name,
    required this.publishedAt,
  });

  String get displayName => '$name ($tag)';
}

class FirmwareService {
  // Cache for release zip data, keyed by tag
  static final Map<String, Uint8List> _zipCache = {};

  /// Fetch available releases from GitHub.
  static Future<List<FirmwareRelease>> listReleases({
    void Function(String)? onLog,
  }) async {
    onLog?.call('Fetching SmartSpin2k releases...\n');

    final response = await http.get(
      Uri.parse('https://api.github.com/repos/doudar/SmartSpin2k/releases'),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch releases: HTTP ${response.statusCode}',
      );
    }

    final List<dynamic> data = jsonDecode(response.body);
    final releases = <FirmwareRelease>[];

    for (final release in data) {
      final tag = release['tag_name'] as String? ?? '';
      final name = release['name'] as String? ?? tag;
      final publishedAt = release['published_at'] as String? ?? '';
      // Only include releases that have a zip asset
      final assets = release['assets'] as List<dynamic>? ?? [];
      final hasZip = assets.any(
        (a) => (a['name'] as String? ?? '').endsWith('.zip'),
      );
      if (hasZip) {
        releases.add(FirmwareRelease(
          tag: tag,
          name: name,
          publishedAt: publishedAt,
        ));
      }
    }

    onLog?.call('Found ${releases.length} releases\n');
    return releases;
  }

  /// Download the firmware zip for a specific release tag and extract a file.
  static Future<Uint8List> extractFileFromReleaseTag(
    String tag,
    String filename, {
    void Function(String)? onLog,
  }) async {
    if (!_zipCache.containsKey(tag)) {
      final downloadUrl =
          'https://github.com/doudar/SmartSpin2k/releases/download/$tag/SmartSpin2kFirmware-$tag.bin.zip';
      onLog?.call('Downloading release $tag...\n');
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download release $tag: HTTP ${response.statusCode}',
        );
      }
      _zipCache[tag] = response.bodyBytes;
      onLog?.call(
        'Download complete (${(response.bodyBytes.length / 1024).toStringAsFixed(0)} KB)\n',
      );
    }

    final archive = ZipDecoder().decodeBytes(_zipCache[tag]!);
    for (final file in archive) {
      if (file.name.toLowerCase() == filename.toLowerCase()) {
        onLog?.call('Extracted $filename from release\n');
        return Uint8List.fromList(file.content as List<int>);
      }
    }

    throw Exception("File '$filename' not found in release $tag");
  }

  /// Get the latest SmartSpin2k firmware release URL from GitHub.
  static Future<String> getLatestReleaseUrl({
    void Function(String)? onLog,
  }) async {
    onLog?.call('Fetching latest SmartSpin2k release...');

    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('https://github.com/doudar/SmartSpin2k/releases/latest'),
      );
      request.followRedirects = false;

      final response = await client.send(request);
      final location = response.headers['location'];
      await response.stream.drain();

      String tag;
      if (location != null && location.contains('/releases/tag/')) {
        tag = location.split('/releases/tag/').last;
      } else {
        final fullResponse = await http.get(
          Uri.parse('https://github.com/doudar/SmartSpin2k/releases/latest'),
        );
        final finalUrl = fullResponse.request?.url.toString() ?? '';
        if (!finalUrl.contains('/releases/tag/')) {
          throw Exception('Could not determine latest release tag');
        }
        tag = finalUrl.split('/releases/tag/').last;
      }

      final downloadUrl =
          'https://github.com/doudar/SmartSpin2k/releases/download/$tag/SmartSpin2kFirmware-$tag.bin.zip';

      final headResponse = await http.head(Uri.parse(downloadUrl));
      if (headResponse.statusCode == 404) {
        throw Exception('Firmware zip not found at: $downloadUrl');
      }

      onLog?.call('Found release: $tag');
      return downloadUrl;
    } finally {
      client.close();
    }
  }

  /// Download firmware zip and extract a specific file (uses latest release).
  static Future<Uint8List> extractFileFromRelease(
    String filename, {
    void Function(String)? onLog,
  }) async {
    final releaseUrl = await getLatestReleaseUrl(onLog: onLog);

    if (!_zipCache.containsKey('__latest__')) {
      onLog?.call('Downloading firmware package...');
      final response = await http.get(Uri.parse(releaseUrl));
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download firmware: HTTP ${response.statusCode}',
        );
      }
      _zipCache['__latest__'] = response.bodyBytes;
      onLog?.call(
        'Download complete (${(response.bodyBytes.length / 1024).toStringAsFixed(0)} KB)',
      );
    }

    final archive = ZipDecoder().decodeBytes(_zipCache['__latest__']!);
    for (final file in archive) {
      if (file.name.toLowerCase() == filename.toLowerCase()) {
        onLog?.call('Extracted $filename from release');
        return Uint8List.fromList(file.content as List<int>);
      }
    }

    throw Exception("File '$filename' not found in firmware package");
  }

  /// Download a binary file from a URL.
  static Future<Uint8List> downloadBinary(
    String url, {
    void Function(String)? onLog,
  }) async {
    onLog?.call('Downloading: $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download $url: HTTP ${response.statusCode}');
    }
    onLog?.call(
      'Downloaded ${(response.bodyBytes.length / 1024).toStringAsFixed(0)} KB',
    );
    return response.bodyBytes;
  }

  /// Clear cached data.
  static void clearCache() {
    _zipCache.clear();
  }

  /// Save bytes to a temporary file and return its path.
  static Future<String> saveTempFile(
    Uint8List data,
    String filename,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('ss2k_');
    final file = File('${tempDir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(data);
    return file.path;
  }
}

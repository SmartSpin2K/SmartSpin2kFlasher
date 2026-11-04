import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

SecurityContext? _windowsContext;

/// Create a client that verifies TLS even when Windows has not downloaded a
/// public CA root yet (https://github.com/dart-lang/sdk/issues/52266).
Future<http.Client> createFirmwareHttpClient() async {
  if (!Platform.isWindows) return http.Client();

  if (_windowsContext == null) {
    final bundle = await rootBundle.load('assets/certificates/cacert.pem');
    final context = SecurityContext(withTrustedRoots: true);
    context.setTrustedCertificatesBytes(
      bundle.buffer.asUint8List(bundle.offsetInBytes, bundle.lengthInBytes),
    );
    _windowsContext = context;
  }

  return IOClient(HttpClient(context: _windowsContext));
}

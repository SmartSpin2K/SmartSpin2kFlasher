import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartspin2k_flasher/services/firmware_http_client.dart';

// Widget tests normally replace HTTP with a fake client. These tests need real
// loopback TLS to check certificate verification without internet access.
class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the packaged Mozilla roots can be loaded by Dart TLS', () async {
    final bundle = await rootBundle.load('assets/certificates/cacert.pem');
    final context = SecurityContext();
    expect(
      () => context.setTrustedCertificatesBytes(
        bundle.buffer.asUint8List(bundle.offsetInBytes, bundle.lengthInBytes),
      ),
      returnsNormally,
    );
  });

  test('the firmware client rejects an untrusted server certificate', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      const certificate = 'test/fixtures/tls/localhost-cert.pem';
      final serverContext = SecurityContext()
        ..useCertificateChain(certificate)
        ..usePrivateKey('test/fixtures/tls/localhost-key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.write('OK');
        await request.response.close();
      }, onError: (Object _) {});

      final url = Uri.parse('https://127.0.0.1:${server.port}/firmware.bin');

      // First prove that the local server works when its test CA is trusted.
      final trustedContext = SecurityContext()
        ..setTrustedCertificates(certificate);
      final trustedClient = HttpClient(context: trustedContext);
      addTearDown(() => trustedClient.close(force: true));
      final request = await trustedClient.getUrl(url);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();

      // The production client trusts public roots, never this private test CA.
      final client = await createFirmwareHttpClient();
      addTearDown(client.close);
      await expectLater(
        client.get(url).timeout(const Duration(seconds: 10)),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('CERTIFICATE_VERIFY_FAILED'),
          ),
        ),
      );
    }, _RealHttpOverrides());
  });
}

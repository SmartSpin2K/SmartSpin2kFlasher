import 'dart:async';
import 'dart:io';

/// Service for receiving UDP log broadcasts.
class UdpLogService {
  static const int defaultPort = 10000;

  RawDatagramSocket? _socket;
  StreamSubscription? _subscription;

  /// Get available network interfaces with their IPv4 addresses.
  static Future<List<NetworkInterfaceInfo>> getNetworkInterfaces() async {
    final interfaces = <NetworkInterfaceInfo>[];

    try {
      final networkInterfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      for (final iface in networkInterfaces) {
        for (final addr in iface.addresses) {
          interfaces.add(NetworkInterfaceInfo(
            name: iface.name,
            address: addr.address,
          ));
        }
      }
    } catch (_) {}

    return interfaces;
  }

  /// Start listening for UDP log messages on the specified interface.
  Future<void> startListening({
    required String address,
    required void Function(String) onData,
    int port = defaultPort,
  }) async {
    await stopListening();

    try {
      _socket = await RawDatagramSocket.bind(address, port);
      _subscription = _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            final message = String.fromCharCodes(datagram.data);
            onData(message);
          }
        }
      });
    } catch (e) {
      throw Exception('Cannot bind to $address:$port - $e');
    }
  }

  /// Stop listening.
  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }

  bool get isListening => _socket != null;
}

class NetworkInterfaceInfo {
  final String name;
  final String address;

  NetworkInterfaceInfo({required this.name, required this.address});

  @override
  String toString() => '$name ($address)';
}

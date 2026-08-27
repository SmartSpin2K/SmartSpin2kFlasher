import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../services/services.dart';
import 'console_output.dart';

/// UDP log viewer dialog window.
class UdpLoggerDialog extends StatefulWidget {
  const UdpLoggerDialog({super.key});

  @override
  State<UdpLoggerDialog> createState() => _UdpLoggerDialogState();
}

class _UdpLoggerDialogState extends State<UdpLoggerDialog> {
  final UdpLogService _udpService = UdpLogService();
  final LogFileWriter _logFileWriter = LogFileWriter();
  final GlobalKey<ConsoleOutputState> _consoleKey = GlobalKey();

  List<NetworkInterfaceInfo> _interfaces = [];
  NetworkInterfaceInfo? _selectedInterface;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInterfaces();
  }

  @override
  void dispose() {
    _udpService.stopListening();
    _logFileWriter.close();
    super.dispose();
  }

  Future<void> _loadInterfaces() async {
    final interfaces = await UdpLogService.getNetworkInterfaces();
    setState(() {
      _interfaces = interfaces;
      _selectedInterface = interfaces.isNotEmpty ? interfaces.first : null;
      _isLoading = false;
    });

    // Auto-start listening on the first interface
    if (_selectedInterface != null) {
      _startListening(_selectedInterface!);
    }
  }

  Future<void> _startListening(NetworkInterfaceInfo iface) async {
    await _udpService.stopListening();
    _consoleKey.currentState?.clear();

    try {
      await _udpService.startListening(
        address: iface.address,
        onData: (data) {
          _logFileWriter.write(data);
          _consoleKey.currentState?.appendText(data);
        },
      );
      _consoleKey.currentState?.appendText(
        'Listening on: ${iface.name} (${iface.address}:${UdpLogService.defaultPort})\n',
        color: Colors.green,
      );
    } catch (e) {
      _consoleKey.currentState?.appendText('Error: $e\n', color: Colors.red);
    }
  }

  Future<void> _toggleFileRecording() async {
    if (_logFileWriter.isOpen) {
      await _logFileWriter.close();
      if (!mounted) return;
      _consoleKey.currentState?.appendText(
        'UDP file recording stopped.\n',
        color: Colors.orange,
      );
      setState(() {});
      return;
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save UDP Logs',
      fileName: 'smartspin2k-udp.log',
      type: FileType.custom,
      allowedExtensions: const ['log', 'txt'],
    );
    if (path == null) return;

    try {
      await _logFileWriter.open(path);
      if (!mounted) return;
      _consoleKey.currentState?.appendText(
        'Writing UDP logs to: $path\n',
        color: Colors.green,
      );
      setState(() {});
    } catch (e) {
      if (mounted) {
        _consoleKey.currentState?.appendText('Error saving logs: $e\n');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 700,
        height: 500,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'UDP Logger',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Network Interface: '),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _isLoading
                        ? const LinearProgressIndicator()
                        : DropdownButton<NetworkInterfaceInfo>(
                            isExpanded: true,
                            value: _selectedInterface,
                            items: _interfaces
                                .map(
                                  (iface) => DropdownMenuItem(
                                    value: iface,
                                    child: Text(
                                      '${iface.name} (${iface.address})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() => _selectedInterface = value);
                              if (value != null) _startListening(value);
                            },
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _toggleFileRecording,
                  icon: Icon(
                    _logFileWriter.isOpen ? Icons.stop : Icons.save_alt,
                    size: 18,
                  ),
                  label: Text(
                    _logFileWriter.isOpen
                        ? 'Stop Saving to File'
                        : 'Save UDP Logs to File',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: ConsoleOutput(key: _consoleKey)),
            ],
          ),
        ),
      ),
    );
  }
}

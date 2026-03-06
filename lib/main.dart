import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'constants.dart';
import 'models/models.dart';
import 'services/services.dart';
import 'theme.dart';
import 'widgets/widgets.dart';

/// On Windows, Dart's default SecurityContext may not include system root
/// certificates, causing CERTIFICATE_VERIFY_FAILED errors. This override
/// accepts certificates for the GitHub hosts this app connects to.
class _SmartSpin2kHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      return host.endsWith('github.com') ||
          host.endsWith('githubusercontent.com');
    };
    return client;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _SmartSpin2kHttpOverrides();
  await PreferencesService.init();
  runApp(const SmartSpin2kFlasherApp());
}

class SmartSpin2kFlasherApp extends StatefulWidget {
  const SmartSpin2kFlasherApp({super.key});

  static ThemeController of(BuildContext context) =>
      context.findAncestorStateOfType<_SmartSpin2kFlasherAppState>()!;

  @override
  State<SmartSpin2kFlasherApp> createState() => _SmartSpin2kFlasherAppState();
}

/// Public interface for theme switching.
abstract class ThemeController {
  void toggleTheme();
  bool get isDark;
}

class _SmartSpin2kFlasherAppState extends State<SmartSpin2kFlasherApp>
    implements ThemeController {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode =
        PreferencesService.themeMode == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  @override
  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      PreferencesService.setThemeMode(
        _themeMode == ThemeMode.dark ? 'dark' : 'light',
      );
    });
  }

  @override
  bool get isDark => _themeMode == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartSpin2kFlasher',
      theme: buildSS2KTheme(Brightness.light),
      darkTheme: buildSS2KTheme(Brightness.dark),
      themeMode: _themeMode,
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<ConsoleOutputState> _consoleKey = GlobalKey();
  final SerialLogService _serialLogService = SerialLogService();

  List<SerialPortInfo> _ports = [];
  String? _selectedPort;
  bool _isFlashing = false;
  bool _isShowingLogs = false;

  // Firmware source
  List<FirmwareRelease> _releases = [];
  bool _loadingReleases = true;
  String _firmwareSource = 'github';
  FirmwareRelease? _selectedRelease;
  String? _localFirmwarePath;

  @override
  void initState() {
    super.initState();
    // Restore saved preferences
    _firmwareSource = PreferencesService.firmwareSource;
    _localFirmwarePath = PreferencesService.localFirmwarePath;
    _refreshPorts();
    _loadReleases();
  }

  @override
  void dispose() {
    _serialLogService.stopLogs();
    super.dispose();
  }

  void _refreshPorts() {
    setState(() {
      _ports = SerialPortService.listSerialPorts();
      // Try to restore saved port first
      final savedPort = PreferencesService.selectedPort;
      if (savedPort != null && _ports.any((p) => p.port == savedPort)) {
        _selectedPort = savedPort;
      } else if (_ports.isNotEmpty &&
          (_selectedPort == null ||
              !_ports.any((p) => p.port == _selectedPort))) {
        _selectedPort = _ports.first.port;
      }
      if (_ports.isEmpty) {
        _selectedPort = null;
      }
    });
  }

  Future<void> _loadReleases() async {
    try {
      final releases = await FirmwareService.listReleases();
      final savedTag = PreferencesService.selectedReleaseTag;
      setState(() {
        _releases = releases;
        _loadingReleases = false;
        if (releases.isNotEmpty) {
          // Restore saved release if it exists in the list
          final match = releases.where((r) => r.tag == savedTag);
          _selectedRelease = match.isNotEmpty ? match.first : releases.first;
        }
      });
    } catch (e) {
      setState(() {
        _loadingReleases = false;
      });
    }
  }

  Future<void> _browseFirmware() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Firmware Binary',
      type: FileType.any,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _localFirmwarePath = result.files.single.path;
      });
      PreferencesService.setLocalFirmwarePath(_localFirmwarePath);
    }
  }

  void _log(String message) {
    _consoleKey.currentState?.appendText(message);
  }

  Future<void> _flash() async {
    if (_selectedPort == null) {
      _log('Error: No serial port selected\n');
      return;
    }

    // Stop serial logger if it's using the port
    if (_isShowingLogs) {
      await _serialLogService.stopLogs();
      setState(() => _isShowingLogs = false);
      _log('Stopped log viewer to free serial port.\n');
    }

    String firmwarePath;
    String? releaseTag;

    if (_firmwareSource == 'github') {
      if (_selectedRelease == null) {
        _log('Error: No release selected\n');
        return;
      }
      releaseTag = _selectedRelease!.tag;
      // Download firmware.bin from the selected release
      setState(() => _isFlashing = true);
      _consoleKey.currentState?.clear();
      try {
        _log('Downloading firmware from release ${_selectedRelease!.tag}...\n');
        final firmwareData = await FirmwareService.extractFileFromReleaseTag(
          releaseTag,
          'firmware.bin',
          onLog: _log,
        );
        firmwarePath =
            await FirmwareService.saveTempFile(firmwareData, 'firmware.bin');
      } catch (e) {
        _log('\nError: $e\n');
        setState(() => _isFlashing = false);
        return;
      }
    } else {
      if (_localFirmwarePath == null || _localFirmwarePath!.isEmpty) {
        _log('Error: No firmware file selected\n');
        return;
      }
      if (!File(_localFirmwarePath!).existsSync()) {
        _log('Error: Firmware file not found: $_localFirmwarePath\n');
        return;
      }
      firmwarePath = _localFirmwarePath!;
      setState(() => _isFlashing = true);
      _consoleKey.currentState?.clear();
    }

    try {
      await EsptoolService.flashDevice(
        port: _selectedPort!,
        firmwarePath: firmwarePath,
        releaseTag: releaseTag,
        onOutput: _log,
      );

      _log('\nAutomatically showing logs after successful flash:\n');
      await Future.delayed(const Duration(seconds: 1));
      _startLogs();
    } catch (e) {
      _log('\nError: $e\n');
    } finally {
      setState(() => _isFlashing = false);
    }
  }

  void _startLogs() async {
    if (_selectedPort == null) {
      _log('Error: No serial port selected\n');
      return;
    }

    _consoleKey.currentState?.clear();
    setState(() => _isShowingLogs = true);

    try {
      await _serialLogService.startLogs(
        port: _selectedPort!,
        onData: (data) {
          final timestamp = DateTime.now().toString().substring(11, 19);
          _log('[$timestamp] $data');
        },
      );
    } catch (e) {
      _log('Error starting logs: $e\n');
      setState(() => _isShowingLogs = false);
    }
  }

  void _stopLogs() async {
    await _serialLogService.stopLogs();
    setState(() => _isShowingLogs = false);
    _log('\nLog viewing stopped.\n');
  }

  void _showUdpLogger() {
    showDialog(
      context: context,
      builder: (context) => const UdpLoggerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/ss2kv3.png'),
          ),
        ),
        title: const Text(
          'SmartSpin2k Flasher',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: Icon(
              SmartSpin2kFlasherApp.of(context).isDark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            tooltip: 'Toggle theme',
            onPressed: () => SmartSpin2kFlasherApp.of(context).toggleTheme(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'v$appVersion',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Configuration card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Serial Port
                    _sectionLabel('SERIAL PORT'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: SS2KColors.bg(brightness),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: SS2KColors.border(brightness)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _selectedPort,
                                hint: const Text(
                                  'No serial ports found',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                dropdownColor: SS2KColors.surface(brightness),
                                items: _ports
                                    .map(
                                      (p) => DropdownMenuItem(
                                        value: p.port,
                                        child: Text(
                                          '${p.port} — ${p.description}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _isFlashing
                                    ? null
                                    : (value) {
                                        setState(() => _selectedPort = value);
                                        PreferencesService.setSelectedPort(value);
                                      },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _iconButton(
                          icon: Icons.refresh,
                          tooltip: 'Refresh ports',
                          onPressed: _isFlashing ? null : _refreshPorts,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Firmware
                    _sectionLabel('FIRMWARE'),
                    const SizedBox(height: 8),

                    // Source toggle
                    Row(
                      children: [
                        _sourceToggle(
                          label: 'GitHub Release',
                          icon: Icons.cloud_download,
                          selected: _firmwareSource == 'github',
                          onTap: _isFlashing
                              ? null
                              : () {
                                  setState(() => _firmwareSource = 'github');
                                  PreferencesService.setFirmwareSource('github');
                                },
                        ),
                        const SizedBox(width: 8),
                        _sourceToggle(
                          label: 'Local File',
                          icon: Icons.folder_open,
                          selected: _firmwareSource == 'local',
                          onTap: _isFlashing
                              ? null
                              : () {
                                  setState(() => _firmwareSource = 'local');
                                  PreferencesService.setFirmwareSource('local');
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Source-specific content
                    if (_firmwareSource == 'github')
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: SS2KColors.bg(brightness),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: SS2KColors.border(brightness),
                                ),
                              ),
                              child: _loadingReleases
                                  ? const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 14),
                                      child: SizedBox(
                                        height: 18,
                                        child: Center(
                                          child: LinearProgressIndicator(),
                                        ),
                                      ),
                                    )
                                  : DropdownButtonHideUnderline(
                                      child:
                                          DropdownButton<FirmwareRelease>(
                                        isExpanded: true,
                                        value: _selectedRelease,
                                        hint: const Text(
                                          'No releases found',
                                          style:
                                              TextStyle(color: Colors.grey),
                                        ),
                                        dropdownColor:
                                            SS2KColors.surface(brightness),
                                        items: _releases
                                            .map(
                                              (r) => DropdownMenuItem(
                                                value: r,
                                                child: Text(
                                                  r.displayName,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: _isFlashing
                                            ? null
                                            : (value) {
                                                setState(
                                                    () => _selectedRelease =
                                                        value);
                                                PreferencesService
                                                    .setSelectedReleaseTag(
                                                        value?.tag);
                                              },
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _iconButton(
                            icon: Icons.refresh,
                            tooltip: 'Refresh releases',
                            onPressed: _isFlashing
                                ? null
                                : () {
                                    setState(() => _loadingReleases = true);
                                    _loadReleases();
                                  },
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: SS2KColors.bg(brightness),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: SS2KColors.border(brightness),
                                ),
                              ),
                              child: Text(
                                _localFirmwarePath ?? 'No file selected',
                                style: TextStyle(
                                  color: _localFirmwarePath != null
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                      : SS2KColors.textMuted(brightness),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed:
                                _isFlashing ? null : _browseFirmware,
                            child: const Text('Browse'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Flash Button
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isFlashing ? null : _flash,
                icon: _isFlashing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.flash_on),
                label: Text(
                  _isFlashing ? 'FLASHING...' : 'FLASH SMARTSPIN2K',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SS2KColors.red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      SS2KColors.red.withValues(alpha: 0.4),
                  disabledForegroundColor: Colors.white54,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Log Buttons Row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isFlashing
                        ? null
                        : (_isShowingLogs ? _stopLogs : _startLogs),
                    icon: Icon(
                      _isShowingLogs ? Icons.stop : Icons.terminal,
                      size: 18,
                    ),
                    label: Text(
                      _isShowingLogs ? 'Stop Logs' : 'View Logs',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isFlashing ? null : _showUdpLogger,
                    icon: const Icon(Icons.wifi, size: 18),
                    label: const Text('View UDP Logs'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Console header
            _sectionLabel('CONSOLE', icon: Icons.terminal),
            const SizedBox(height: 6),
            Expanded(
              child: ConsoleOutput(key: _consoleKey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceToggle({
    required String label,
    required IconData icon,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? SS2KColors.red : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? SS2KColors.red
                  : SS2KColors.border(Theme.of(context).brightness),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? Colors.white
                    : SS2KColors.textMuted(Theme.of(context).brightness),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, {IconData? icon}) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: SS2KColors.red,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        if (icon != null) ...[
          Icon(icon, size: 14, color: SS2KColors.red),
          const SizedBox(width: 6),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: SS2KColors.border(brightness)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Icon(icon, color: SS2KColors.red),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

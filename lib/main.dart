import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'models/models.dart';
import 'services/services.dart';
import 'theme.dart';
import 'widgets/widgets.dart';

late final String appVersion;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  appVersion = (await PackageInfo.fromPlatform()).version;
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
    _themeMode = PreferencesService.themeMode == 'light'
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  @override
  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
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
  final LogFileWriter _serialLogFileWriter = LogFileWriter();

  List<SerialPortInfo> _ports = [];
  String? _selectedPort;
  bool _isFlashing = false;
  bool _isShowingLogs = false;

  // Post-flash boot detection
  BootState? _flashResult;
  BootMonitor? _bootMonitor;
  Timer? _portWatchTimer;
  bool _handlingDisconnect = false;
  bool _awaitingPort = false;
  String _flashedChip = '';
  String _flashedFirmware = '';

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
    _bootMonitor?.dispose();
    _portWatchTimer?.cancel();
    _serialLogService.stopLogs();
    _serialLogFileWriter.close();
    super.dispose();
  }

  void _refreshPorts() {
    setState(() {
      _ports = SerialPortService.listSerialPorts();
      // Prefer a connected SmartSpin2k board, then the saved port.
      _selectedPort = SerialPortService.choosePort(
        _ports,
        PreferencesService.selectedPort ?? _selectedPort,
      );
    });
  }

  Future<void> _loadReleases() async {
    try {
      final releases = await FirmwareService.listReleases(onLog: _log);
      final savedTag = PreferencesService.selectedReleaseTag;
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _loadingReleases = false;
      });
      _log('Error loading GitHub releases: $e\n');
    }
  }

  Future<void> _browseFirmware() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Factory Firmware Binary',
        type: FileType.custom,
        allowedExtensions: const ['bin'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _localFirmwarePath = result.files.single.path;
        });
        PreferencesService.setLocalFirmwarePath(_localFirmwarePath);
      }
    } catch (e) {
      _log('Error opening firmware file picker: $e\n');
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

    setState(_clearFlashResult);

    // Stop serial logger if it's using the port
    if (_isShowingLogs) {
      await _stopLogs(showMessage: false);
      _log('Stopped log viewer to free serial port.\n');
    }

    SmartSpin2kChip chip;
    String factoryFirmwarePath;
    String? littlefsPath;
    int? littlefsAddress;

    setState(() => _isFlashing = true);
    _consoleKey.currentState?.clear();
    try {
      _log('Detecting connected board...\n');
      chip = await EsptoolService.detectChip(
        port: _selectedPort!,
        onOutput: _log,
      );
      _log('Detected ${chip.displayName}.\n');
    } catch (e) {
      _log('\nError: $e\n');
      setState(() => _isFlashing = false);
      return;
    }

    if (_firmwareSource == 'github') {
      if (_selectedRelease == null) {
        _log('Error: No release selected\n');
        setState(() => _isFlashing = false);
        return;
      }
      final imageSet = FirmwareService.factoryImageSetFor(chip);
      try {
        _log(
          'Downloading ${chip.displayName} factory firmware from release ${_selectedRelease!.tag}...\n',
        );
        final factoryData = await FirmwareService.extractFileFromReleaseTag(
          _selectedRelease!.tag,
          imageSet.factoryFilename,
          onLog: _log,
        );
        factoryFirmwarePath = await FirmwareService.saveTempFile(
          factoryData,
          imageSet.factoryFilename,
        );
        final littlefsData = await FirmwareService.extractFileFromReleaseTag(
          _selectedRelease!.tag,
          imageSet.littlefsFilename,
          onLog: _log,
        );
        littlefsPath = await FirmwareService.saveTempFile(
          littlefsData,
          imageSet.littlefsFilename,
        );
        littlefsAddress = imageSet.littlefsAddress;
      } catch (e) {
        _log('\nError: $e\n');
        setState(() => _isFlashing = false);
        return;
      }
    } else {
      if (_localFirmwarePath == null || _localFirmwarePath!.isEmpty) {
        _log('Error: No firmware file selected\n');
        setState(() => _isFlashing = false);
        return;
      }
      if (!File(_localFirmwarePath!).existsSync()) {
        _log('Error: Firmware file not found: $_localFirmwarePath\n');
        setState(() => _isFlashing = false);
        return;
      }
      if (!p.basename(_localFirmwarePath!).toLowerCase().contains('factory')) {
        _log(
          'Error: Local flashing requires a factory firmware file '
          '(for example, firmware.factory.bin).\n',
        );
        setState(() => _isFlashing = false);
        return;
      }
      factoryFirmwarePath = _localFirmwarePath!;
    }

    try {
      await EsptoolService.flashDevice(
        port: _selectedPort!,
        chip: chip,
        factoryFirmwarePath: factoryFirmwarePath,
        littlefsPath: littlefsPath,
        littlefsAddress: littlefsAddress,
        onOutput: _log,
      );

      _log('\nWaiting for the device to restart...\n');
      _flashedChip = chip.displayName;
      _flashedFirmware = _firmwareSource == 'github'
          ? (_selectedRelease?.tag ?? 'the selected release')
          : p.basename(_localFirmwarePath!);
      final monitor = BootMonitor(
        onStateChanged: (state) {
          if (!mounted) return;
          setState(() => _flashResult = state);
          // The port can drop out while the board resets, so only watch for
          // an unplug once the device has started talking (or we gave up).
          if (state != BootState.waiting && _portWatchTimer == null) {
            _startPortWatch();
          }
        },
      );
      _bootMonitor = monitor;
      monitor.start();
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      if (_bootMonitor != monitor) return;
      unawaited(
        _startLogs(
          initialMessage: 'Waiting for the device to restart...\n',
          onRawLine: monitor.addLine,
        ),
      );
    } catch (e) {
      _log('\nError: $e\n');
    } finally {
      if (mounted) setState(() => _isFlashing = false);
    }
  }

  Future<bool> _startLogs({
    String? logFilePath,
    String? initialMessage,
    void Function(String line)? onRawLine,
    bool clearConsole = true,
  }) async {
    if (_selectedPort == null) {
      _log('Error: No serial port selected\n');
      return false;
    }

    if (clearConsole) _consoleKey.currentState?.clear();
    if (initialMessage != null) _log(initialMessage);
    setState(() => _isShowingLogs = true);

    try {
      if (logFilePath != null) {
        await _serialLogFileWriter.open(logFilePath);
        _log('Writing serial logs to: $logFilePath\n');
      }
      await _serialLogService.startLogs(
        port: _selectedPort!,
        onClosed: (_) {
          if (mounted && _isShowingLogs) {
            final monitor = _bootMonitor;
            if (monitor != null && !monitor.isTerminal) {
              unawaited(_awaitPortReturn(monitor));
            } else {
              unawaited(_handleDeviceDisconnected());
            }
          }
        },
        onData: (data) {
          onRawLine?.call(
            data.endsWith('\n') ? data.substring(0, data.length - 1) : data,
          );
          final timestamp = DateTime.now().toString().substring(11, 19);
          final entry = '[$timestamp] $data';
          _serialLogFileWriter.write(entry);
          _log(entry);
        },
      );
      return true;
    } catch (e) {
      await _serialLogFileWriter.close();
      _log('Error starting logs: $e\n');
      setState(() => _isShowingLogs = false);
      return false;
    }
  }

  /// Keeps the banner alive while the port drops during a planned restart,
  /// then resumes logging once the port re-enumerates.
  Future<void> _awaitPortReturn(BootMonitor monitor) async {
    if (_awaitingPort) return;
    _awaitingPort = true;
    try {
      await _stopLogs(showMessage: false);
      monitor.notePortReset();
      _log(
        '\nSerial port closed while the device restarts; waiting for it to reconnect...\n',
      );
      while (true) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted || _bootMonitor != monitor || monitor.isTerminal) return;
        if (_selectedPort == null ||
            !SerialPort.availablePorts.contains(_selectedPort)) {
          continue;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted || _bootMonitor != monitor || monitor.isTerminal) return;
        if (await _startLogs(clearConsole: false, onRawLine: monitor.addLine)) {
          return;
        }
      }
    } finally {
      _awaitingPort = false;
    }
  }

  Future<void> _stopLogs({bool showMessage = true}) async {
    await _serialLogService.stopLogs();
    await _serialLogFileWriter.close();
    setState(() => _isShowingLogs = false);
    if (showMessage) _log('\nLog viewing stopped.\n');
  }

  Future<void> _recordSerialLogs() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Serial Logs',
      fileName: 'smartspin2k-serial.log',
      type: FileType.custom,
      allowedExtensions: const ['log', 'txt'],
    );
    if (path != null) {
      if (mounted) setState(_clearFlashResult);
      await _startLogs(logFilePath: path);
    }
  }

  Future<void> _viewLogs() async {
    setState(_clearFlashResult);
    await _startLogs();
  }

  void _clearFlashResult() {
    _bootMonitor?.dispose();
    _bootMonitor = null;
    _portWatchTimer?.cancel();
    _portWatchTimer = null;
    _flashResult = null;
  }

  void _startPortWatch() {
    _portWatchTimer?.cancel();
    _portWatchTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (_flashResult == null || _selectedPort == null) return;
      final monitor = _bootMonitor;
      if (monitor != null && !monitor.isTerminal) return;
      if (!SerialPort.availablePorts.contains(_selectedPort)) {
        unawaited(_handleDeviceDisconnected());
      }
    });
  }

  Future<void> _handleDeviceDisconnected() async {
    if (!mounted || _handlingDisconnect) return;
    final hadBanner = _flashResult != null;
    if (!hadBanner && !_isShowingLogs) return;
    _handlingDisconnect = true;
    try {
      if (_isShowingLogs) {
        await _stopLogs(showMessage: false);
      }
      if (!mounted) return;
      setState(_clearFlashResult);
      _log(
        hadBanner
            ? '\nDevice disconnected.\n'
            : '\nSerial port closed.\n',
      );
    } finally {
      _handlingDisconnect = false;
    }
  }

  void _showUdpLogger() {
    showDialog(context: context, builder: (context) => const UdpLoggerDialog());
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
                              border: Border.all(
                                color: SS2KColors.border(brightness),
                              ),
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
                                          p.board != null
                                              ? '${p.port} — SmartSpin2k '
                                                    '(${p.board!.displayName})'
                                              : '${p.port} — ${p.description}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _isFlashing
                                    ? null
                                    : (value) {
                                        setState(() => _selectedPort = value);
                                        PreferencesService.setSelectedPort(
                                          value,
                                        );
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
                                  PreferencesService.setFirmwareSource(
                                    'github',
                                  );
                                  if (_releases.isEmpty && !_loadingReleases) {
                                    setState(() => _loadingReleases = true);
                                    unawaited(_loadReleases());
                                  }
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
                                  unawaited(_browseFirmware());
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: SS2KColors.bg(brightness),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: SS2KColors.border(brightness),
                                ),
                              ),
                              child: _loadingReleases
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      child: SizedBox(
                                        height: 18,
                                        child: Center(
                                          child: LinearProgressIndicator(),
                                        ),
                                      ),
                                    )
                                  : DropdownButtonHideUnderline(
                                      child: DropdownButton<FirmwareRelease>(
                                        isExpanded: true,
                                        value: _selectedRelease,
                                        hint: const Text(
                                          'No releases found',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                        dropdownColor: SS2KColors.surface(
                                          brightness,
                                        ),
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
                                                  () =>
                                                      _selectedRelease = value,
                                                );
                                                PreferencesService.setSelectedReleaseTag(
                                                  value?.tag,
                                                );
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
                                      ? Theme.of(context).colorScheme.onSurface
                                      : SS2KColors.textMuted(brightness),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _isFlashing ? null : _browseFirmware,
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
                  disabledBackgroundColor: SS2KColors.red.withValues(
                    alpha: 0.4,
                  ),
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
                        : (_isShowingLogs ? _stopLogs : _viewLogs),
                    icon: Icon(
                      _isShowingLogs ? Icons.stop : Icons.terminal,
                      size: 18,
                    ),
                    label: Text(_isShowingLogs ? 'Stop Logs' : 'View Logs'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isFlashing || _isShowingLogs
                        ? null
                        : _recordSerialLogs,
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('Save Serial Logs'),
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

            if (_flashResult != null) ...[
              _flashBanner(),
              const SizedBox(height: 12),
            ],

            // Console header
            _sectionLabel('CONSOLE', icon: Icons.terminal),
            const SizedBox(height: 6),
            Expanded(child: ConsoleOutput(key: _consoleKey)),
          ],
        ),
      ),
    );
  }

  Widget _flashBanner() {
    final state = _flashResult!;
    final isWaiting = state == BootState.waiting || state == BootState.booting;

    if (isWaiting) {
      final brightness = Theme.of(context).brightness;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: SS2KColors.surface(brightness),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SS2KColors.border(brightness)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Flashed successfully — waiting for the device to restart…',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final Color color;
    final IconData icon;
    final String title;
    final String subtitle;
    switch (state) {
      case BootState.booted:
        color = Colors.green.shade700;
        icon = Icons.check_circle;
        title = 'Flashing Complete';
        subtitle =
            'SmartSpin2k ($_flashedChip) restarted and is running '
            '$_flashedFirmware. You can unplug the board.';
      case BootState.timedOut:
        color = Colors.amber.shade800;
        icon = Icons.check_circle_outline;
        title = 'Flashing Complete';
        subtitle =
            "Firmware was written and verified, but the device didn't report "
            'a restart. Check the logs below or press the reset button.';
      case BootState.crashed:
      default:
        color = Colors.red.shade700;
        icon = Icons.error;
        title = 'Flashed, but the device restarted unexpectedly';
        subtitle = 'Check the logs below.';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 40, color: Colors.white),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Dismiss',
            onPressed: () => setState(_clearFlashResult),
          ),
        ],
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

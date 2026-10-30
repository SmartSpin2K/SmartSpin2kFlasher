import 'dart:async';

/// Progress of the device restart after flashing.
enum BootState { waiting, booting, booted, crashed, timedOut }

/// Watches serial log lines after a flash and decides whether the new
/// firmware booted. Pure Dart: feed it raw lines via [addLine].
class BootMonitor {
  BootMonitor({
    required this.onStateChanged,
    this.settleDuration = const Duration(seconds: 3),
    this.timeout = const Duration(seconds: 30),
  });

  final void Function(BootState state) onStateChanged;
  final Duration settleDuration;
  final Duration timeout;

  /// SS2K logger format, e.g. `[    40][E](Main): Compiled ...`.
  static final RegExp _appLine = RegExp(r'^\[\s*\d+\]\[[VDIWE]\]\([^)]+\):');

  static final RegExp _compiledLine = RegExp(r'\(Main\): Compiled');

  static const List<String> _crashSignatures = [
    'Guru Meditation',
    'abort() was called',
    'Backtrace:',
    'Rebooting...',
    'Brownout detector was triggered',
  ];

  /// ROM reset line, e.g. `rst:0xc (RTC_SW_CPU_RST),boot:0x8 (...)`.
  static final RegExp _resetLine = RegExp(r'rst:0x([0-9a-fA-F]+)');

  /// Reset code for a software CPU reset (`ESP.restart()`), a planned reboot.
  static const int _softwareResetCode = 0xc;

  BootState _state = BootState.waiting;
  Timer? _timeoutTimer;
  Timer? _settleTimer;
  bool _started = false;
  bool _disposed = false;
  bool _restartPending = false;
  bool _resetSeen = false;

  BootState get state => _state;

  bool get isTerminal =>
      _state == BootState.booted ||
      _state == BootState.crashed ||
      _state == BootState.timedOut;

  void start() {
    if (_disposed || _started) return;
    _started = true;
    _setState(BootState.waiting);
    _timeoutTimer = Timer(timeout, () {
      if (_state == BootState.waiting) {
        _setState(BootState.timedOut);
      }
    });
  }

  void addLine(String line) {
    if (_disposed || !_started || isTerminal) return;
    final text = line.trim();
    if (text.isEmpty) return;

    if (_state == BootState.waiting) {
      if (_appLine.hasMatch(text)) {
        _timeoutTimer?.cancel();
        _setState(BootState.booting);
        _startSettle();
      }
      return;
    }

    if (_state != BootState.booting) return;

    if (_crashSignatures.any(text.contains)) {
      _crash();
      return;
    }

    final reset = _resetLine.firstMatch(text);
    if (reset != null) {
      final code = int.parse(reset.group(1)!, radix: 16);
      if (code != _softwareResetCode) {
        _crash();
        return;
      }
      _markRestartPending();
      _resetSeen = true;
      return;
    }

    if (text.contains('Reboot flagged')) {
      _markRestartPending();
      return;
    }

    if (_restartPending &&
        ((_resetSeen && _appLine.hasMatch(text)) ||
            text.contains(_compiledLine))) {
      // New boot after the planned restart: settle again.
      _restartPending = false;
      _resetSeen = false;
      _timeoutTimer?.cancel();
      _startSettle();
    }
  }

  /// The serial port dropped while booting (S3 native USB re-enumerates on
  /// reset), so the next app line belongs to the new boot.
  void notePortReset() {
    if (_disposed || _state != BootState.booting) return;
    _markRestartPending();
    _resetSeen = true;
  }

  void _startSettle() {
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDuration, () {
      if (_state == BootState.booting) _setState(BootState.booted);
    });
  }

  void _markRestartPending() {
    _settleTimer?.cancel();
    if (!_restartPending) {
      _restartPending = true;
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(timeout, () {
        if (_state == BootState.booting && _restartPending) {
          _setState(BootState.timedOut);
        }
      });
    }
  }

  void _crash() {
    _settleTimer?.cancel();
    _timeoutTimer?.cancel();
    _setState(BootState.crashed);
  }

  void dispose() {
    _disposed = true;
    _timeoutTimer?.cancel();
    _settleTimer?.cancel();
  }

  void _setState(BootState s) {
    if (_disposed) return;
    _state = s;
    onStateChanged(s);
  }
}

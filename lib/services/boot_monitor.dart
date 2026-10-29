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

  static const List<String> _crashSignatures = [
    'Guru Meditation',
    'abort() was called',
    'Backtrace:',
    'rst:0x',
    'Rebooting...',
  ];

  BootState _state = BootState.waiting;
  Timer? _timeoutTimer;
  Timer? _settleTimer;
  bool _started = false;
  bool _disposed = false;

  BootState get state => _state;

  bool get _isTerminal =>
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
    if (_disposed || !_started || _isTerminal) return;
    final text = line.trim();
    if (text.isEmpty) return;

    if (_state == BootState.waiting) {
      if (_appLine.hasMatch(text)) {
        _timeoutTimer?.cancel();
        _setState(BootState.booting);
        _settleTimer = Timer(settleDuration, () {
          if (_state == BootState.booting) _setState(BootState.booted);
        });
      }
      return;
    }

    if (_state == BootState.booting && _crashSignatures.any(text.contains)) {
      _settleTimer?.cancel();
      _setState(BootState.crashed);
    }
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

import 'dart:io';

/// Streams log output to a user-selected file without retaining it in memory.
class LogFileWriter {
  IOSink? _sink;

  bool get isOpen => _sink != null;

  /// Opens [path] for appending, creating parent directories when necessary.
  Future<void> open(String path) async {
    await close();
    final file = File(path);
    await file.parent.create(recursive: true);
    _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
  }

  /// Writes data directly to the file stream.
  void write(String data) {
    _sink?.write(data);
  }

  /// Flushes and closes the file.
  Future<void> close() async {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }
}

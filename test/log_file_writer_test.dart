import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartspin2k_flasher/services/log_file_writer.dart';

void main() {
  test('LogFileWriter appends output and flushes it on close', () async {
    final directory = await Directory.systemTemp.createTemp('ss2k_logs_');
    final file = File('${directory.path}/session.log');
    final writer = LogFileWriter();

    await writer.open(file.path);
    writer.write('first line\n');
    writer.write('second line\n');
    await writer.close();

    expect(await file.readAsString(), 'first line\nsecond line\n');
    await directory.delete(recursive: true);
  });
}

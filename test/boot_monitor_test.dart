import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartspin2k_flasher/services/boot_monitor.dart';

const _capturedLog = [
  'I (402) boot: Loaded app from partition at offset 0x60000',
  'I (402) boot: Disabling RNG early entropy source...',
  '[    40][E](Main): Compiled Oct 13 202604:00:15',
  '[    41][E](Main): Current Board Revision is: Revision Three (ESP32-S3)',
  '[    63][E](Main): Mounting Filesystem',
  'LittleFS Total Bytes:7995392, Used Bytes:57344',
  '[   173][E](Main): S3 heap: 329643 bytes, PSRAM: 2097152 bytes',
  '[   941][E](BLE_Setup): End BLE Setup',
  '[   944][E](HTTP_Server): HTTP server started',
  '[  1962][E](Main): W=0 C=0 H=0 G=8 R=0 P=9600->9600',
];

void main() {
  test('captured log reaches booted after settle', () {
    fakeAsync((async) {
      final states = <BootState>[];
      final m = BootMonitor(onStateChanged: states.add)..start();
      _capturedLog.forEach(m.addLine);
      expect(m.state, BootState.booting);
      async.elapse(const Duration(seconds: 3));
      expect(m.state, BootState.booted);
      expect(states, [BootState.waiting, BootState.booting, BootState.booted]);
      m.dispose();
    });
  });

  test('bootloader-only lines stay waiting then time out', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine('I (402) boot: Loaded app from partition at offset 0x60000');
      m.addLine('LittleFS Total Bytes:7995392, Used Bytes:57344');
      async.elapse(const Duration(seconds: 29));
      expect(m.state, BootState.waiting);
      async.elapse(const Duration(seconds: 2));
      expect(m.state, BootState.timedOut);
      m.dispose();
    });
  });

  test('crash after app line becomes crashed and never booted', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine('[    40][E](Main): Compiled');
      m.addLine('Guru Meditation Error: Core 1 panic\'ed');
      expect(m.state, BootState.crashed);
      async.elapse(const Duration(seconds: 10));
      expect(m.state, BootState.crashed);
      m.dispose();
    });
  });

  test('crash signature before any app line is ignored', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine('rst:0x1 (POWERON),boot:0x8');
      expect(m.state, BootState.waiting);
      m.addLine('  [    40][E](Main): Compiled\n');
      expect(m.state, BootState.booting);
      m.dispose();
    });
  });

  test('crash after booted does not change state', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine('[    40][E](Main): Compiled');
      async.elapse(const Duration(seconds: 3));
      m.addLine('Backtrace: 0x1');
      expect(m.state, BootState.booted);
      m.dispose();
    });
  });

  test('dispose cancels timers without callbacks', () {
    fakeAsync((async) {
      final states = <BootState>[];
      final m = BootMonitor(onStateChanged: states.add)..start();
      m.addLine('[    40][E](Main): Compiled');
      m.dispose();
      async.elapse(const Duration(minutes: 1));
      expect(states, [BootState.waiting, BootState.booting]);

      final states2 = <BootState>[];
      final m2 = BootMonitor(onStateChanged: states2.add)..start();
      m2.dispose();
      async.elapse(const Duration(minutes: 1));
      expect(states2, [BootState.waiting]);
    });
  });
}

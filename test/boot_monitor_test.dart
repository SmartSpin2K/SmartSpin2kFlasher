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

  const compiled = '[    40][E](Main): Compiled Oct 13 202604:00:15';
  const marker =
      '[  1000][E](HTTP_Server): Recovery persisted (fsOk=1 nvsOk=1). Reboot flagged.';
  const status = '[  1962][E](Main): W=0 C=0 H=0 G=8 R=0 P=9600->9600';
  const swReset = 'rst:0xc (RTC_SW_CPU_RST),boot:0x8 (SPI_FAST_FLASH_BOOT)';
  const three = Duration(seconds: 3);

  test('planned restart with marker ends booted after the new boot', () {
    fakeAsync((async) {
      final states = <BootState>[];
      final m = BootMonitor(onStateChanged: states.add)..start();
      m.addLine(compiled);
      m.addLine(marker);
      async.elapse(three);
      expect(m.state, BootState.booting);
      m.addLine(status);
      async.elapse(three);
      expect(m.state, BootState.booting);
      m.addLine(swReset);
      expect(m.state, BootState.booting);
      m.addLine(compiled);
      async.elapse(three);
      expect(m.state, BootState.booted);
      expect(states, [BootState.waiting, BootState.booting, BootState.booted]);
      m.dispose();
    });
  });

  test('software reset without marker is not a crash', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine(compiled);
      m.addLine(swReset);
      expect(m.state, BootState.booting);
      async.elapse(three);
      expect(m.state, BootState.booting);
      m.addLine(status);
      async.elapse(three);
      expect(m.state, BootState.booted);
      m.dispose();
    });
  });

  test('marker then Compiled without reset line (port dropped) boots', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine(compiled);
      m.addLine(marker);
      m.addLine(compiled);
      expect(m.state, BootState.booting);
      async.elapse(three);
      expect(m.state, BootState.booted);
      m.dispose();
    });
  });

  test('port drop after marker boots on the next status line', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine(compiled);
      m.addLine(marker);
      m.notePortReset();
      // Reopened port missed the Compiled line; the status line still counts.
      m.addLine(status);
      async.elapse(three);
      expect(m.state, BootState.booted);
      m.dispose();
    });
  });

  test('port drop while waiting is ignored', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.notePortReset();
      expect(m.state, BootState.waiting);
      m.addLine(compiled);
      async.elapse(three);
      expect(m.state, BootState.booted);
      m.dispose();
    });
  });

  test('marker then silence times out', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine(compiled);
      m.addLine(marker);
      async.elapse(const Duration(seconds: 29));
      expect(m.state, BootState.booting);
      async.elapse(const Duration(seconds: 2));
      expect(m.state, BootState.timedOut);
      m.dispose();
    });
  });

  test('non-software reset codes while booting are crashes', () {
    for (final line in [
      'rst:0x10 (RTCWDT_RTC_RESET),boot:0x8',
      'rst:0x7 (TG0WDT_SYS_RESET),boot:0x13',
    ]) {
      fakeAsync((async) {
        final m = BootMonitor(onStateChanged: (_) {})..start();
        m.addLine(compiled);
        m.addLine(line);
        expect(m.state, BootState.crashed);
        m.dispose();
      });
    }
  });

  test('guru meditation while restart pending is a crash', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine(compiled);
      m.addLine(marker);
      m.addLine('Guru Meditation Error: Core 1 panic\'ed');
      expect(m.state, BootState.crashed);
      async.elapse(const Duration(minutes: 1));
      expect(m.state, BootState.crashed);
      m.dispose();
    });
  });

  test('brownout while booting is a crash', () {
    fakeAsync((async) {
      final m = BootMonitor(onStateChanged: (_) {})..start();
      m.addLine(compiled);
      m.addLine('Brownout detector was triggered');
      expect(m.state, BootState.crashed);
      m.dispose();
    });
  });
}

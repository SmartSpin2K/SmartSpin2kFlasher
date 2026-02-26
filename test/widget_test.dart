import 'package:flutter_test/flutter_test.dart';

import 'package:smartspin2k_flasher/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartSpin2kFlasherApp());
    expect(find.text('SmartSpin2kFlasher'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartspin2k_flasher/main.dart';
import 'package:smartspin2k_flasher/services/preferences_service.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
    appVersion = 'test';

    await tester.pumpWidget(const SmartSpin2kFlasherApp());
    expect(find.text('SmartSpin2k Flasher'), findsOneWidget);
  });
}

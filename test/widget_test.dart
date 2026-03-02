// test/widget_test.dart (FIXED)
import 'package:flutter_chat_demo/main.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    // Initialize SharedPreferences
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Initialize FlutterLocalNotificationsPlugin
    final notificationsPlugin = FlutterLocalNotificationsPlugin();

    // Build our app and trigger a frame
    await tester.pumpWidget(MyApp(
      prefs: prefs,
      notificationsPlugin: notificationsPlugin,
    ));

    // Verify app builds without errors
    expect(find.byType(MyApp), findsOneWidget);
  });
}

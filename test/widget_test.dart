// test/widget_test.dart
import 'package:flutter_chat_demo/main.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notificationsPlugin = FlutterLocalNotificationsPlugin();

    await tester.pumpWidget(MyApp(
      prefs: prefs,
      notificationsPlugin: notificationsPlugin,
      chatBubbleService: ChatBubbleService(),
      notificationService: NotificationService(),
      unifiedBubbleService: UnifiedBubbleService(),
    ));

    expect(find.byType(MyApp), findsOneWidget);
  });
}

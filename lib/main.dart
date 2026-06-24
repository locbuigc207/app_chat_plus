import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/firebase_options.dart';
import 'package:flutter_chat_demo/models/call_model.dart';
import 'package:flutter_chat_demo/models/group_call_model.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/phone_auth_provider.dart'
as custom_auth;
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/utils/utils.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ─────────────────────────────────────────────────────────────────────────────
// Globals
// ─────────────────────────────────────────────────────────────────────────────

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

/// Navigator key dùng cho toàn app.
final GlobalKey<NavigatorState> globalNavigatorKey =
GlobalKey<NavigatorState>();

// ─────────────────────────────────────────────────────────────────────────────
// FCM background handler
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('🔔 Background FCM: ${message.messageId}');

  try {
    await BubbleFcmHandler.processMessage(message, fromBackground: true);
  } catch (e) {
    debugPrint('⚠️ BubbleFcmHandler process error in background: $e');
  }

  final type = message.data['type'] as String?;
  if (type == 'group_call_invite') {
    debugPrint('📞 Background group call invite: ${message.data['callId']}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HÀM TẠO PROVIDERS CHUNG - ĐẢM BẢO 100% KHÔNG THIẾU PROVIDER GÂY CRASH BUBBLE
// ─────────────────────────────────────────────────────────────────────────────
List<SingleChildWidget> buildAppProviders({
  required SharedPreferences prefs,
  required FirebaseFirestore firebaseFirestore,
  required FirebaseStorage firebaseStorage,
  required firebase_auth.FirebaseAuth firebaseAuth,
  required UnifiedBubbleService unifiedBubbleService,
  required NotificationService notificationService,
  required FlutterLocalNotificationsPlugin notificationsPlugin,
}) {
  return [
    ChangeNotifierProvider<AutoPilotProvider>(
      create: (_) => AutoPilotProvider(
        firebaseFirestore: firebaseFirestore,
        prefs: prefs,
      ),
    ),
    ChangeNotifierProvider<InsightsProvider>(
      create: (_) => InsightsProvider(firebaseFirestore: firebaseFirestore),
    ),
    ChangeNotifierProvider<AppModeProvider>(create: (_) => AppModeProvider()),
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(
        firebaseAuth: firebaseAuth,
        prefs: prefs,
        firebaseFirestore: firebaseFirestore,
      ),
    ),
    ChangeNotifierProvider<custom_auth.PhoneAuthProvider>(
      create: (_) => custom_auth.PhoneAuthProvider(
        firebaseAuth: firebaseAuth,
        firebaseFirestore: firebaseFirestore,
        prefs: prefs,
      ),
    ),
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(prefs: prefs),
    ),
    ChangeNotifierProvider<TelemetryProvider>(
      create: (_) => TelemetryProvider(),
    ),
    ChangeNotifierProvider<StoryProvider>(
      create: (_) => StoryProvider(
        firebaseFirestore: firebaseFirestore,
        firebaseStorage: firebaseStorage,
      ),
    ),
    Provider<SettingProvider>(
      create: (_) => SettingProvider(
        prefs: prefs,
        firebaseFirestore: firebaseFirestore,
        firebaseStorage: firebaseStorage,
      ),
    ),
    Provider<HomeProvider>(
      create: (_) => HomeProvider(firebaseFirestore: firebaseFirestore),
    ),
    Provider<ChatProvider>(
      create: (_) => ChatProvider(
        prefs: prefs,
        firebaseFirestore: firebaseFirestore,
        firebaseStorage: firebaseStorage,
      ),
    ),
    Provider<FriendProvider>(
      create: (_) => FriendProvider(firebaseFirestore: firebaseFirestore),
    ),
    Provider<ReactionProvider>(
      create: (_) => ReactionProvider(firebaseFirestore: firebaseFirestore),
    ),
    Provider<MessageProvider>(
      create: (_) => MessageProvider(firebaseFirestore: firebaseFirestore),
    ),
    Provider<ConversationProvider>(
      create: (_) => ConversationProvider(firebaseFirestore: firebaseFirestore),
    ),
    Provider<ReminderProvider>(
      create: (_) => ReminderProvider(
        firebaseFirestore: firebaseFirestore,
        notificationsPlugin: notificationsPlugin,
      ),
    ),
    Provider<AutoDeleteProvider>(
      create: (_) => AutoDeleteProvider(firebaseFirestore: firebaseFirestore),
    ),
    Provider<ConversationLockProvider>(
      create: (_) =>
          ConversationLockProvider(firebaseFirestore: firebaseFirestore),
    ),
    Provider<ViewOnceProvider>(
      create: (_) => ViewOnceProvider(firebaseFirestore: firebaseFirestore),
    ),
    Provider<SmartReplyProvider>(create: (_) => SmartReplyProvider()),
    Provider<UserPresenceProvider>(
      create: (_) => UserPresenceProvider(firebaseFirestore: firebaseFirestore),
    ),
    Provider<LocationProvider>(create: (_) => LocationProvider()),
    Provider<TranslationProvider>(create: (_) => TranslationProvider()),
    Provider<UnifiedBubbleService>(
      create: (_) => unifiedBubbleService,
      dispose: (_, s) => s.dispose(),
    ),
    Provider<NotificationService>(create: (_) => notificationService),
    ChangeNotifierProvider<BubbleSettingsService>(
      create: (_) => BubbleSettingsService(),
    ),
    Provider<BubbleSoundService>(create: (_) => BubbleSoundService()),
    Provider<ContextualBubbleService>(
      create: (_) => ContextualBubbleService.instance,
    ),
    ChangeNotifierProvider<GroupCallProvider>(
      create: (_) => GroupCallProvider(
        currentUserId: prefs.getString('currentUserId') ?? '',
      ),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry Points Độc Lập Cho Bubble & Mini Chat (Tránh Hive Conflict)
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> bubbleMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();

  runApp(BubbleChatEntryApp(prefs: prefs));
}

@pragma('vm:entry-point')
Future<void> miniChatMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();

  runApp(MiniChatEntryApp(prefs: prefs));
}

// ─────────────────────────────────────────────────────────────────────────────
// main()
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  await _initializeFirebase();
  await ErrorLogger.initialize();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
  await initializeDateFormatting('vi');

  final prefs = await SharedPreferences.getInstance();

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    await _initializeLocalNotifications(flutterLocalNotificationsPlugin);

    await BubbleSettingsService().load();
    await BubbleSoundService().initialize();

    try {
      await LinkMetadataService().loadFromDisk();
    } catch (_) {}

    await BubbleLifecycleObserver.instance.initialize();
    await BubbleFcmHandler.initialize();
    await _initializeFcm();

    await PushNotificationService.initialize(
      onNotificationTap: (payload) {
        final peerId = payload['senderId'] as String?;
        final peerName = payload['senderName'] as String?;
        if (peerId != null && peerName != null) {
          AppRouter.pushChatFromNotification(
            peerId: peerId,
            peerName: peerName,
            peerAvatar: payload['avatarUrl'] as String? ?? '',
          );
        }
      },
    );
  }

  final unifiedBubbleService = UnifiedBubbleService();
  final notificationService = NotificationService();

  runApp(
    ChatApp(
      prefs: prefs,
      notificationsPlugin: flutterLocalNotificationsPlugin,
      notificationService: notificationService,
      unifiedBubbleService: unifiedBubbleService,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Firebase init
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('✅ Firestore Offline Persistence bật');
    } catch (e) {
      debugPrint('⚠️ Offline Persistence (Web không hỗ trợ): $e');
    }

    const disableAppCheckForTesting = false;

    if (kDebugMode && disableAppCheckForTesting) {
      debugPrint('⚠️ App Check ĐÃ TẮT cho mục đích test (debug mode)');
    } else {
      await FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode
            ? AndroidProvider.debug
            : AndroidProvider.playIntegrity,
        appleProvider: kDebugMode
            ? AppleProvider.debug
            : AppleProvider.appAttest,
      );
    }

    try {
      await LocalDbService().initialize();
      debugPrint('✅ LocalDbService khởi tạo xong');
      SyncManager().startListening();
      debugPrint('✅ SyncManager đang lắng nghe');

      try {
        await GroupCallNotificationService.instance.initialize(
          flutterLocalNotificationsPlugin,
        );
        debugPrint('✅ GroupCallNotificationService ready');
      } catch (e) {
        debugPrint('⚠️ GroupCallNotificationService init: $e');
      }
    } catch (_) {}
  } catch (e, stack) {
    debugPrint('❌ Firebase init lỗi: $e');
    await ErrorLogger.logError(e, stack, context: 'Firebase.initializeApp');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FCM init
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _initializeFcm() async {
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('🔔 FCM permission: ${settings.authorizationStatus.name}');

    try {
      await FcmTokenManager.initialize(
        onTokenAvailable: (token) async {
          debugPrint('📱 FCM Token mới: ${token.substring(0, 20)}...');
          final uid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .update({'pushToken': token, 'fcmToken': token});
          }
        },
      );
    } catch (_) {
      final token = await messaging.getToken();
      if (token != null) {
        debugPrint('📱 FCM Token (Fallback): ${token.substring(0, 20)}...');
      }
      messaging.onTokenRefresh.listen((newToken) {
        debugPrint('🔄 FCM Token refreshed');
      });
    }
  } catch (e) {
    debugPrint('⚠️ FCM init lỗi: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local Notifications init
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _initializeLocalNotifications(
    FlutterLocalNotificationsPlugin plugin,
    ) async {
  try {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          'message_category',
          actions: [
            DarwinNotificationAction.plain('reply', 'Trả lời'),
            DarwinNotificationAction.plain('mark_read', 'Đã đọc'),
          ],
        ),
      ],
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse:
      _onBackgroundNotificationTapped,
    );

    if (Platform.isAndroid) await _setupAndroidNotificationChannels(plugin);
    if (Platform.isIOS) {
      await plugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
      >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    debugPrint('✅ Local Notifications khởi tạo xong');
  } catch (e, stack) {
    debugPrint('❌ Notification init lỗi: $e');
    await ErrorLogger.logError(
      e,
      stack,
      context: '_initializeLocalNotifications',
    );
  }
}

Future<void> _setupAndroidNotificationChannels(
    FlutterLocalNotificationsPlugin plugin,
    ) async {
  final androidPlugin = plugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin
  >();
  if (androidPlugin == null) return;

  await androidPlugin.requestNotificationsPermission();
  try {
    await androidPlugin.requestExactAlarmsPermission();
  } catch (e) {
    debugPrint('⚠️ Exact Alarms Permission: $e');
  }

  await androidPlugin.createNotificationChannel(
    const AndroidNotificationChannel(
      AppConstants.messageChannelId,
      'Tin nhắn mới',
      description: 'Thông báo khi nhận tin nhắn mới',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFF2196F3),
    ),
  );

  await androidPlugin.createNotificationChannel(
    const AndroidNotificationChannel(
      AppConstants.reminderChannelId,
      'Nhắc nhở tin nhắn',
      description: 'Nhắc nhở về các tin nhắn chưa đọc',
      importance: Importance.high,
    ),
  );

  await androidPlugin.createNotificationChannel(
    const AndroidNotificationChannel(
      AppConstants.callChannelId,
      'Cuộc gọi đến',
      description: 'Thông báo cuộc gọi thoại / video',
      importance: Importance.max,
      playSound: true,
    ),
  );

  await androidPlugin.createNotificationChannel(
    const AndroidNotificationChannel(
      AppConstants.groupCallChannelId,
      'Cuộc gọi nhóm đến',
      description: 'Thông báo cuộc gọi nhóm video/thoại',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFF3B82F6),
    ),
  );

  await androidPlugin.createNotificationChannel(
    const AndroidNotificationChannel(
      AppConstants.ongoingCallChannelId,
      'Cuộc gọi nhóm đang diễn ra',
      description: 'Hiển thị trong khi đang trong cuộc gọi nhóm',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
  );
}

void _onNotificationTapped(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null) return;
  debugPrint('🔔 Notification tapped: $payload');

  if (payload.startsWith('group_call:')) {
    final callId = payload.replaceFirst('group_call:', '');
    debugPrint('📞 Group call tapped: $callId');
    return;
  }

  try {
    final parts = payload.split('|');
    if (parts.length >= 2) {
      AppRouter.pushChatFromNotification(
        peerId: parts[0],
        peerName: parts[1],
        peerAvatar: parts.length > 2 ? parts[2] : '',
      );
    }
  } catch (e) {
    debugPrint('⚠️ Notification payload parse lỗi: $e');
  }
}

@pragma('vm:entry-point')
void _onBackgroundNotificationTapped(NotificationResponse response) {
  debugPrint('🔔 Background notification tapped: ${response.payload}');
}

// ─────────────────────────────────────────────────────────────────────────────
// BubbleChatChannelManager
// ─────────────────────────────────────────────────────────────────────────────

class BubbleChatChannelManager extends StatefulWidget {
  final Widget child;
  const BubbleChatChannelManager({super.key, required this.child});

  @override
  State<BubbleChatChannelManager> createState() =>
      _BubbleChatChannelManagerState();
}

class _BubbleChatChannelManagerState extends State<BubbleChatChannelManager> {
  static const _channel = MethodChannel('bubble_chat_channel');
  final _recentNavigations = <String>{};

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _channel.setMethodCallHandler(_handleMethodCall);
  }

  @override
  void dispose() {
    if (!kIsWeb) _channel.setMethodCallHandler(null);
    _recentNavigations.clear();
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'navigateToChat':
        return _handleNavigateToChat(call.arguments);
      case 'onBackPressed':
        if (globalNavigatorKey.currentState?.canPop() == true) {
          globalNavigatorKey.currentState!.pop();
        }
        break;
      case 'openApp':
        SystemNavigator.pop();
        break;
      case 'bubble_permission_lost':
        BubblePermissionService.instance.onPermissionLost();
        if (globalNavigatorKey.currentContext != null) {
          ScaffoldMessenger.maybeOf(
            globalNavigatorKey.currentContext!,
          )?.showSnackBar(
            const SnackBar(
              content: Text(
                'Quyền hiển thị bong bóng đã bị tắt. Vui lòng cấp quyền trong Cài đặt.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
        break;
    }
    return null;
  }

  Future<void> _handleNavigateToChat(dynamic args) async {
    debugPrint('👉 _handleNavigateToChat nhận args: $args');

    final peerId = (args['peerId'] ?? args['userId']) as String?;
    final peerNickname = (args['peerNickname'] ?? args['userName']) as String?;
    final peerAvatar = (args['peerAvatar'] ?? args['avatarUrl']) as String? ?? '';
    final isBubbleMode = args['isBubbleMode'] as bool? ?? true;

    final isGroup = (args['isGroup'] as bool?) ?? (peerId?.startsWith('group_') ?? false);

    if (peerId == null || peerNickname == null) {
      debugPrint('❌ Missing peerId or peerNickname trong args điều hướng');
      return;
    }

    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 2000;
    final dedupKey = '$peerId:$bucket';
    if (_recentNavigations.contains(dedupKey)) return;
    _recentNavigations.add(dedupKey);
    Future.delayed(
      const Duration(seconds: 10),
          () => _recentNavigations.remove(dedupKey),
    );

    await _waitForNavigator();

    if (globalNavigatorKey.currentState == null) {
      _recentNavigations.remove(dedupKey);
      debugPrint('❌ Không tìm thấy Navigator State sau khi chờ');
      return;
    }

    try {
      if (isGroup) {
        // [SỬA LỖI ĐIỀU HƯỚNG]: Xóa màn hình Loading và đè thẳng GroupChatPage
        globalNavigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(
            settings: const RouteSettings(name: '/group-chat'),
            builder: (_) => GroupChatPage(
              group: Group(
                id: peerId,
                groupName: peerNickname,
                groupPhotoUrl: peerAvatar,
                adminId: '',
                memberIds: const [],
                roles: const {},
                createdAt: DateTime.now().millisecondsSinceEpoch.toString(),
              ),
            ),
          ),
              (route) => false,
        );
      } else {
        // [SỬA LỖI ĐIỀU HƯỚNG]: Xóa màn hình Loading và đè thẳng ChatPage
        final chatArgs = ChatPageArguments(
          peerId: peerId,
          peerNickname: peerNickname,
          peerAvatar: peerAvatar,
        );
        globalNavigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(
            settings: const RouteSettings(name: '/chat'),
            builder: (_) => ChatPage(arguments: chatArgs, isBubbleMode: isBubbleMode),
          ),
              (route) => false,
        );
      }
    } catch (e, stack) {
      _recentNavigations.remove(dedupKey);
      await ErrorLogger.logError(
        e,
        stack,
        context: 'BubbleChatChannelManager.navigateToChat',
      );
    }
  }

  Future<void> _waitForNavigator({int maxRetries = 15}) async {
    for (int i = 0; i < maxRetries; i++) {
      if (globalNavigatorKey.currentState != null && mounted) return;
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────────────────────────────────────────
// BubbleModeDetector
// ─────────────────────────────────────────────────────────────────────────────

class BubbleModeDetector {
  BubbleModeDetector._();
  static const _channel = MethodChannel('bubble_chat_channel');
  static Future<bool> isBubbleMode() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('getBubbleMode') ?? false;
    } catch (_) {
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppInitializer
// ─────────────────────────────────────────────────────────────────────────────

class AppInitializer extends StatefulWidget {
  final NotificationService notificationService;
  final Widget child;

  const AppInitializer({
    super.key,
    required this.notificationService,
    required this.child,
  });

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer>
    with WidgetsBindingObserver {
  StreamSubscription<firebase_auth.User?>? _authSub;
  bool _notificationStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onReady());
  }

  void _onReady() {
    _startNotificationService();
    _handleFcmForegroundMessages();
    _handleNotificationLaunch();
  }

  void _startNotificationService() {
    _authSub = firebase_auth.FirebaseAuth.instance.authStateChanges().listen((
        user,
        ) async {
      if (user != null && !_notificationStarted) {
        widget.notificationService.initialize();
        widget.notificationService.listenForNewMessages(user.uid);
        _notificationStarted = true;
        ErrorLogger.setUserId(user.uid);

        try {
          await BubblePermissionService.instance.initialize();
        } catch (e) {
          debugPrint('⚠️ Failed to init BubblePermissionService: $e');
        }

        try {
          final callProvider = context.read<GroupCallProvider>();
          callProvider.updateUserId(user.uid);
        } catch (_) {}
      } else if (user == null) {
        widget.notificationService.stopListening();
        _notificationStarted = false;
        ErrorLogger.clearUserId();
      }
    });
  }

  Future<void> _routeFromNotificationMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'] as String?;

    if (type == 'incoming_call') {
      final callId = data['callId'] as String?;
      if (callId != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('calls')
              .doc(callId)
              .get();
          if (doc.exists && doc.data() != null) {
            final call = CallModel.fromMap(doc.data()!);
            if (call.status.isActive) {
              globalNavigatorKey.currentState?.push(
                MaterialPageRoute(builder: (_) => IncomingCallPage(call: call)),
              );
            }
          }
        } catch (e) {
          debugPrint('⚠️ Fetch call doc error: $e');
        }
      }
    } else if (type == 'group_call_invite') {
      final callId = data['callId'] as String?;
      if (callId != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('group_calls')
              .doc(callId)
              .get();
          if (doc.exists && doc.data() != null) {
            final call = GroupCallModel.fromMap(doc.data()!, doc.id);
            if (!call.isEnded) {
              final uid =
                  firebase_auth.FirebaseAuth.instance.currentUser?.uid ?? '';
              final currentCtx = globalNavigatorKey.currentContext;
              String userName = '';
              String userAvatar = '';

              if (currentCtx != null) {
                final auth = currentCtx.read<AuthProvider>();
                userName = auth.currentUserName ?? '';
                userAvatar = auth.currentUserAvatar ?? '';
              }

              globalNavigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => IncomingGroupCallPage(
                    call: call,
                    currentUserId: uid,
                    currentUserName: userName,
                    currentUserAvatar: userAvatar,
                  ),
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('⚠️ Fetch group call doc error: $e');
        }
      }
    } else {
      final peerId = data['peerId'] as String?;
      final peerNickname = data['peerNickname'] as String?;
      if (peerId != null && peerNickname != null) {
        AppRouter.pushChatFromNotification(
          peerId: peerId,
          peerName: peerNickname,
          peerAvatar: data['peerAvatar'] ?? '',
        );
      }
    }
  }

  void _handleFcmForegroundMessages() {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('📩 Foreground FCM: ${message.notification?.title}');
      final type = message.data['type'] as String?;
      if (type == 'group_call_invite') {
        GroupCallNotificationService.instance.handleForegroundMessage(message);
        return;
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('🔔 FCM opened app: ${message.data}');
      _routeFromNotificationMessage(message);
    });
  }

  Future<void> _handleNotificationLaunch() async {
    try {
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) {
        await Future.delayed(const Duration(milliseconds: 800));
        await _routeFromNotificationMessage(initialMessage);
      }
    } catch (e) {
      debugPrint('⚠️ Initial FCM message lỗi: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    ErrorLogger.addBreadcrumb(state.name, category: 'lifecycle');

    switch (state) {
      case AppLifecycleState.resumed:
        _updatePresence(online: true);
        if (mounted) {
          try {
            context.read<UnifiedBubbleService>().onAppResumed();
          } catch (_) {}
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _updatePresence(online: false);
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _updatePresence({required bool online}) {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': online,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatApp
// ─────────────────────────────────────────────────────────────────────────────

class ChatApp extends StatefulWidget {
  final SharedPreferences prefs;
  final FlutterLocalNotificationsPlugin notificationsPlugin;
  final NotificationService notificationService;
  final UnifiedBubbleService unifiedBubbleService;

  const ChatApp({
    super.key,
    required this.prefs,
    required this.notificationsPlugin,
    required this.notificationService,
    required this.unifiedBubbleService,
  });

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> with BubbleLifecycleMixin {
  @override
  Widget build(BuildContext context) {
    final firebaseFirestore = FirebaseFirestore.instance;
    final firebaseStorage = FirebaseStorage.instance;
    final firebaseAuth = firebase_auth.FirebaseAuth.instance;

    return MultiProvider(
      providers: buildAppProviders(
        prefs: widget.prefs,
        firebaseFirestore: firebaseFirestore,
        firebaseStorage: firebaseStorage,
        firebaseAuth: firebaseAuth,
        unifiedBubbleService: widget.unifiedBubbleService,
        notificationService: widget.notificationService,
        notificationsPlugin: widget.notificationsPlugin,
      ),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: AppConstants.appTitle,
            debugShowCheckedModeBanner: false,
            navigatorKey: AppRouter.navigatorKey,
            themeMode: themeProvider.flutterThemeMode ?? ThemeMode.system,
            theme:
            themeProvider.lightTheme ??
                _buildFallbackTheme(Brightness.light),
            darkTheme:
            themeProvider.darkTheme ?? _buildFallbackTheme(Brightness.dark),
            initialRoute: AppRouter.splash,
            onGenerateRoute: AppRouter.onGenerateRoute,
            builder: (context, child) {
              Widget content = AppInitializer(
                notificationService: widget.notificationService,
                child: _AppBuilder(child: child!),
              );

              if (!kIsWeb) {
                content = GroupCallMiniManager(
                  child: BubbleChatChannelManager(
                    child: GroupCallListener(
                      child: CallListener(child: BubbleManager(child: content)),
                    ),
                  ),
                );
              }

              return content;
            },
          );
        },
      ),
    );
  }

  ThemeData _buildFallbackTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2979FF),
        brightness: brightness,
      ),
      fontFamily: 'Inter',
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF0D0D0D)
          : const Color(0xFFF4F7FF),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? const Color(0xFF1A1A2E)
            : const Color(0xFF2979FF),
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      extensions: [BubbleTheme.of(brightness)],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBuilder
// ─────────────────────────────────────────────────────────────────────────────

class _AppBuilder extends StatelessWidget {
  final Widget child;
  const _AppBuilder({required this.child});

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(
          MediaQuery.textScalerOf(context).scale(1.0).clamp(0.8, 1.3),
        ),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolated Apps & Pages Cho Các Tác Vụ Engine Nền
// ─────────────────────────────────────────────────────────────────────────────

class BubbleChatEntryApp extends StatelessWidget {
  final SharedPreferences prefs;

  const BubbleChatEntryApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    final firebaseFirestore = FirebaseFirestore.instance;
    final firebaseStorage = FirebaseStorage.instance;
    final firebaseAuth = firebase_auth.FirebaseAuth.instance;

    final unifiedBubbleService = UnifiedBubbleService();
    final notificationService = NotificationService();

    return MultiProvider(
      providers: buildAppProviders(
        prefs: prefs,
        firebaseFirestore: firebaseFirestore,
        firebaseStorage: firebaseStorage,
        firebaseAuth: firebaseAuth,
        unifiedBubbleService: unifiedBubbleService,
        notificationService: notificationService,
        notificationsPlugin: flutterLocalNotificationsPlugin,
      ),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final brightness = themeProvider.flutterThemeMode == ThemeMode.dark
              ? Brightness.dark
              : Brightness.light;
          final isDark = brightness == Brightness.dark;

          final defaultTheme = ThemeData(
            useMaterial3: true,
            brightness: brightness,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2979FF),
              brightness: brightness,
            ),
            scaffoldBackgroundColor: isDark
                ? const Color(0xFF0D0D0D)
                : const Color(0xFFF4F7FF),
          );

          return MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: globalNavigatorKey,
            themeMode: themeProvider.flutterThemeMode ?? ThemeMode.system,
            theme: themeProvider.lightTheme ?? defaultTheme,
            darkTheme: themeProvider.darkTheme ?? defaultTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.textScalerOf(context).scale(1.0).clamp(0.8, 1.3),
                ),
              ),
              child: BubbleChatChannelManager(child: child!),
            ),
            home: const BubbleEntryPage(),
            onGenerateRoute: AppRouter.onGenerateRoute,
          );
        },
      ),
    );
  }
}

class BubbleEntryPage extends StatefulWidget {
  const BubbleEntryPage({super.key});

  @override
  State<BubbleEntryPage> createState() => _BubbleEntryPageState();
}

// [SỬA LỖI P1] Đồng bộ Widget Binding Observer để bắn lại Ready Signal cho Native
class _BubbleEntryPageState extends State<BubbleEntryPage> with WidgetsBindingObserver {
  static const _channel = MethodChannel('bubble_chat_channel');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifyReady();
  }

  void _notifyReady() {
    _channel.invokeMethod('flutterReady').catchError((_) {});
    // Bắn thêm vài lần dự phòng trường hợp Engine Warmup khiến Native bị lỡ mất (miss) event
    for (int i = 1; i <= 3; i++) {
      Future.delayed(Duration(milliseconds: i * 400), () {
        if (mounted) _channel.invokeMethod('flutterReady').catchError((_) {});
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notifyReady();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Đang tải cuộc trò chuyện...', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Component cho Mini Chat Độc Lập
// ─────────────────────────────────────────────────────────────────────────────
class MiniChatEntryApp extends StatelessWidget {
  final SharedPreferences prefs;

  const MiniChatEntryApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    final firebaseFirestore = FirebaseFirestore.instance;
    final firebaseStorage = FirebaseStorage.instance;
    final firebaseAuth = firebase_auth.FirebaseAuth.instance;
    final unifiedBubbleService = UnifiedBubbleService();
    final notificationService = NotificationService();

    return MultiProvider(
      providers: buildAppProviders(
        prefs: prefs,
        firebaseFirestore: firebaseFirestore,
        firebaseStorage: firebaseStorage,
        firebaseAuth: firebaseAuth,
        unifiedBubbleService: unifiedBubbleService,
        notificationService: notificationService,
        notificationsPlugin: flutterLocalNotificationsPlugin,
      ),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final brightness = themeProvider.flutterThemeMode == ThemeMode.dark
              ? Brightness.dark
              : Brightness.light;
          final isDark = brightness == Brightness.dark;

          final defaultTheme = ThemeData(
            useMaterial3: true,
            brightness: brightness,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2979FF),
              brightness: brightness,
            ),
            scaffoldBackgroundColor: isDark
                ? const Color(0xFF0D0D0D)
                : const Color(0xFFF4F7FF),
          );

          return MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: globalNavigatorKey,
            themeMode: themeProvider.flutterThemeMode ?? ThemeMode.system,
            theme: themeProvider.lightTheme ?? defaultTheme,
            darkTheme: themeProvider.darkTheme ?? defaultTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.textScalerOf(context).scale(1.0).clamp(0.8, 1.3),
                ),
              ),
              child: child!, // KHÔNG SỬ DỤNG BubbleChatChannelManager để tránh conflict
            ),
            home: const MiniChatEntryPage(),
            onGenerateRoute: AppRouter.onGenerateRoute,
          );
        },
      ),
    );
  }
}

class MiniChatEntryPage extends StatefulWidget {
  const MiniChatEntryPage({super.key});

  @override
  State<MiniChatEntryPage> createState() => _MiniChatEntryPageState();
}

// [SỬA LỖI P1] Đồng bộ Widget Binding Observer để bắn lại Ready Signal cho Native
class _MiniChatEntryPageState extends State<MiniChatEntryPage> with WidgetsBindingObserver {
  static const _channel = MethodChannel('mini_chat_channel');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_handleMethodCall);
    _notifyReady();
  }

  void _notifyReady() {
    _channel.invokeMethod('flutterReady').catchError((_) {});
    for (int i = 1; i <= 3; i++) {
      Future.delayed(Duration(milliseconds: i * 400), () {
        if (mounted) _channel.invokeMethod('flutterReady').catchError((_) {});
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notifyReady();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'navigateToMiniChat':
      case 'navigateToChat':
        final args = call.arguments;
        final peerId = (args['peerId'] ?? args['userId']) as String?;
        final peerNickname = (args['peerNickname'] ?? args['userName']) as String?;
        final peerAvatar = (args['peerAvatar'] ?? args['avatarUrl']) as String? ?? '';
        final isGroup = (args['isGroup'] as bool?) ?? (peerId?.startsWith('group_') ?? false);

        if (peerId != null && peerNickname != null) {

          await _waitForNavigator();
          if (globalNavigatorKey.currentState == null) return null;

          if (isGroup) {
            globalNavigatorKey.currentState!.pushAndRemoveUntil(
              MaterialPageRoute(
                settings: const RouteSettings(name: '/group-chat'),
                builder: (_) => GroupChatPage(
                  group: Group(
                    id: peerId,
                    groupName: peerNickname,
                    groupPhotoUrl: peerAvatar,
                    adminId: '',
                    memberIds: const [],
                    roles: const {},
                    createdAt: DateTime.now().millisecondsSinceEpoch.toString(),
                  ),
                ),
              ),
                  (route) => false,
            );
          } else {
            globalNavigatorKey.currentState!.pushAndRemoveUntil(
              MaterialPageRoute(
                settings: const RouteSettings(name: '/chat'),
                builder: (_) => ChatPage(
                  arguments: ChatPageArguments(
                    peerId: peerId,
                    peerNickname: peerNickname,
                    peerAvatar: peerAvatar,
                  ),
                  isBubbleMode: true,
                ),
              ),
                  (route) => false,
            );
          }
        }
        break;
      case 'minimize':
      case 'close':
        SystemNavigator.pop();
        break;
      case 'getUserInfo':
        final user = firebase_auth.FirebaseAuth.instance.currentUser;
        if (user != null) {
          return {
            'userId': user.uid,
            'userName': user.displayName ?? '',
            'avatarUrl': user.photoURL ?? ''
          };
        }
        return null;
    }
    return null;
  }

  Future<void> _waitForNavigator({int maxRetries = 15}) async {
    for (int i = 0; i < maxRetries; i++) {
      if (globalNavigatorKey.currentState != null && mounted) return;
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Đang kết nối cuộc trò chuyện mini...', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppRouter
// ─────────────────────────────────────────────────────────────────────────────

class AppRouter {
  static final navigatorKey = globalNavigatorKey;

  static const splash = '/';
  static const login = '/login';
  static const home = '/home';
  static const chat = '/chat';
  static const profile = '/profile';
  static const settings = '/settings';
  static const bubbleSettings = '/bubble-settings';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _fade(const SplashPage());
      case login:
        return _fade(const LoginPage());
      case home:
        return _fade(const HomePage());
      case chat:
        final args = settings.arguments as ChatPageArguments?;
        if (args == null) {
          return _errorRoute('Chat page: arguments không hợp lệ');
        }
        return _slide(ChatPage(arguments: args));
      case bubbleSettings:
        return _slide(const BubbleSettingsPage());
      case '/group-call':
        return null;
      case '/group-call-history':
        final args = settings.arguments as Map<String, dynamic>?;
        if (args == null) return _errorRoute('Missing group call history args');
        return _slide(
          GroupCallHistoryPage(
            groupId: args['groupId'] as String,
            groupName: args['groupName'] as String,
            currentUserId: args['currentUserId'] as String,
          ),
        );
      default:
        return _fade(const _NotFoundPage());
    }
  }

  static PageRouteBuilder _fade(Widget page) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  );

  static PageRouteBuilder _slide(Widget page) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (_, anim, sec, child) {
      final tween = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: anim.drive(tween), child: child);
    },
  );

  static void pushChatFromNotification({
    required String peerId,
    required String peerName,
    required String peerAvatar,
  }) {
    globalNavigatorKey.currentState?.pushNamed(
      chat,
      arguments: ChatPageArguments(
        peerId: peerId,
        peerNickname: peerName,
        peerAvatar: peerAvatar,
      ),
    );
  }

  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Lỗi')),
        body: Center(child: Text(message)),
      ),
    );
  }
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Trang không tồn tại',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => AppRouter.navigatorKey.currentState
                ?.pushReplacementNamed(AppRouter.home),
            child: const Text('Về trang chủ'),
          ),
        ],
      ),
    ),
  );
}
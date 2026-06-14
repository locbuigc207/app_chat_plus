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
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/phone_auth_provider.dart'
    as custom_auth;
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/utils/utils.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  await _initializeFirebase();
  await ErrorLogger.initialize();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

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
  }

  final unifiedBubbleService = UnifiedBubbleService();
  final chatBubbleService = ChatBubbleService();
  final notificationService = NotificationService();

  runApp(ChatApp(
    prefs: prefs,
    notificationsPlugin: flutterLocalNotificationsPlugin,
    chatBubbleService: chatBubbleService,
    notificationService: notificationService,
    unifiedBubbleService: unifiedBubbleService,
  ));
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

    const disableAppCheckForTesting = true;

    if (kDebugMode && disableAppCheckForTesting) {
      debugPrint('⚠️ App Check ĐÃ TẮT cho mục đích test (debug mode)');
    } else {
      await FirebaseAppCheck.instance.activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider:
            kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
      );
    }

    try {
      await LocalDbService().initialize();
      debugPrint('✅ LocalDbService khởi tạo xong');
      SyncManager().startListening();
      debugPrint('✅ SyncManager đang lắng nghe');

      try {
        await GroupCallNotificationService.instance
            .initialize(flutterLocalNotificationsPlugin);
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
                .update({'fcmToken': token});
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
    FlutterLocalNotificationsPlugin plugin) async {
  try {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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

    final initSettings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

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
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    debugPrint('✅ Local Notifications khởi tạo xong');
  } catch (e, stack) {
    debugPrint('❌ Notification init lỗi: $e');
    await ErrorLogger.logError(e, stack,
        context: '_initializeLocalNotifications');
  }
}

Future<void> _setupAndroidNotificationChannels(
    FlutterLocalNotificationsPlugin plugin) async {
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
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
      'call_channel',
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
      'ongoing_call_channel',
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
      case 'openApp':
        SystemNavigator.pop();
    }
    return null;
  }

  Future<void> _handleNavigateToChat(dynamic args) async {
    final peerId = args['peerId'] as String?;
    final peerNickname = args['peerNickname'] as String?;
    final peerAvatar = args['peerAvatar'] as String? ?? '';
    final isBubbleMode = args['isBubbleMode'] as bool? ?? false;

    if (peerId == null || peerNickname == null) return;

    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 2000;
    final dedupKey = '$peerId:$bucket';
    if (_recentNavigations.contains(dedupKey)) return;
    _recentNavigations.add(dedupKey);
    Future.delayed(
        const Duration(seconds: 10), () => _recentNavigations.remove(dedupKey));

    await _waitForNavigator();

    if (globalNavigatorKey.currentState == null) {
      _recentNavigations.remove(dedupKey);
      return;
    }

    try {
      final chatArgs = ChatPageArguments(
        peerId: peerId,
        peerNickname: peerNickname,
        peerAvatar: peerAvatar,
      );
      globalNavigatorKey.currentState!.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/chat'),
          builder: (_) =>
              ChatPage(arguments: chatArgs, isBubbleMode: isBubbleMode),
        ),
      );
    } catch (e, stack) {
      _recentNavigations.remove(dedupKey);
      await ErrorLogger.logError(e, stack,
          context: 'BubbleChatChannelManager.navigateToChat');
    }
  }

  Future<void> _waitForNavigator({int maxRetries = 5}) async {
    for (int i = 0; i < maxRetries; i++) {
      if (globalNavigatorKey.currentState != null) return;
      await Future.delayed(Duration(milliseconds: 100 * (1 << i)));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────────────────────────────────────────
// MiniChatOverlayManager
// ─────────────────────────────────────────────────────────────────────────────

class MiniChatOverlayManager extends StatefulWidget {
  final Widget child;
  const MiniChatOverlayManager({super.key, required this.child});

  @override
  State<MiniChatOverlayManager> createState() => _MiniChatOverlayManagerState();
}

class _MiniChatOverlayManagerState extends State<MiniChatOverlayManager> {
  static const _channel = MethodChannel('mini_chat_channel');
  OverlayEntry? _overlay;
  // FIX lỗi 7: track insertion state để tránh double-remove
  bool _overlayInserted = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _channel.setMethodCallHandler(_handleCall);
  }

  @override
  void dispose() {
    _removeOverlay();
    if (!kIsWeb) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'navigateToMiniChat':
        final peerId = call.arguments['peerId'] as String?;
        final name = call.arguments['peerNickname'] as String?;
        final avatar = call.arguments['peerAvatar'] as String? ?? '';
        if (peerId != null && name != null && mounted) {
          _showOverlay(peerId, name, avatar);
        }
      case 'minimize':
      case 'close':
        _removeOverlay();
    }
    return null;
  }

  void _showOverlay(String userId, String userName, String avatarUrl) {
    // Luôn remove overlay cũ trước
    _removeOverlay();

    if (!mounted) return;

    _overlay = OverlayEntry(
      builder: (_) => _MiniChatOverlayScaffold(
        userId: userId,
        userName: userName,
        avatarUrl: avatarUrl,
        onMinimize: () {
          _removeOverlay();
          _channel.invokeMethod('minimize', {'userId': userId});
        },
        onClose: () {
          _removeOverlay();
          _channel.invokeMethod('close', {'userId': userId});
        },
      ),
    );

    // FIX lỗi 7: bọc insert trong try/catch, chỉ set flag khi insert thành công
    try {
      Overlay.of(context).insert(_overlay!);
      _overlayInserted = true;
    } catch (e) {
      debugPrint('❌ MiniChatOverlayManager: insert failed: $e');
      _overlay = null;
      _overlayInserted = false;
    }
  }

  void _removeOverlay() {
    // FIX lỗi 7: chỉ remove nếu đã insert thành công
    if (_overlay != null && _overlayInserted) {
      try {
        _overlay!.remove();
      } catch (e) {
        debugPrint('⚠️ MiniChatOverlayManager: remove failed: $e');
      }
    }
    _overlay = null;
    _overlayInserted = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────────────────────────────────────────
// _MiniChatOverlayScaffold & MiniChatOverlayWidget (giữ nguyên)
// ─────────────────────────────────────────────────────────────────────────────

class _MiniChatOverlayScaffold extends StatelessWidget {
  final String userId, userName, avatarUrl;
  final VoidCallback onMinimize, onClose;

  const _MiniChatOverlayScaffold({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black26,
      child: Stack(
        children: [
          GestureDetector(onTap: onMinimize),
          MiniChatOverlayWidget(
            userId: userId,
            userName: userName,
            avatarUrl: avatarUrl,
            onMinimize: onMinimize,
            onClose: onClose,
          ),
        ],
      ),
    );
  }
}

class MiniChatOverlayWidget extends StatefulWidget {
  final String userId, userName, avatarUrl;
  final VoidCallback onMinimize, onClose;

  const MiniChatOverlayWidget({
    super.key,
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  State<MiniChatOverlayWidget> createState() => _MiniChatOverlayWidgetState();
}

class _MiniChatOverlayWidgetState extends State<MiniChatOverlayWidget>
    with SingleTickerProviderStateMixin {
  Offset _position = Offset.zero;
  bool _positionInitialized = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;

  double get _width {
    final sw = MediaQuery.sizeOf(context).width;
    return sw > 480 ? 360.0 : sw * 0.88;
  }

  double get _height {
    final sh = MediaQuery.sizeOf(context).height;
    return sh > 750 ? 520.0 : sh * 0.72;
  }

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _animCtrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_positionInitialized) {
      final size = MediaQuery.sizeOf(context);
      _position =
          Offset((size.width - _width) / 2, (size.height - _height) / 2);
      _positionInitialized = true;
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final clampedX = _position.dx.clamp(0.0, size.width - _width);
    final clampedY = _position.dy.clamp(0.0, size.height - _height);

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: GestureDetector(
          onPanUpdate: (d) => setState(() => _position += d.delta),
          child: _buildCard(),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(20),
      shadowColor: Colors.black38,
      child: Container(
        width: _width,
        height: _height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.6),
              width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              _MiniChatHeader(
                userName: widget.userName,
                avatarUrl: widget.avatarUrl,
                onMinimize: widget.onMinimize,
                onClose: widget.onClose,
              ),
              Expanded(
                child: ChatPage(
                  arguments: ChatPageArguments(
                    peerId: widget.userId,
                    peerNickname: widget.userName,
                    peerAvatar: widget.avatarUrl,
                  ),
                  isMiniChat: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChatHeader extends StatelessWidget {
  final String userName, avatarUrl;
  final VoidCallback onMinimize, onClose;

  const _MiniChatHeader({
    required this.userName,
    required this.avatarUrl,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        gradient:
            LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF1565C0)]),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: Colors.white24,
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isEmpty
                ? Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(userName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                const Text('Mini Chat',
                    style: TextStyle(color: Colors.white60, fontSize: 10)),
              ],
            ),
          ),
          _HeaderButton(
              icon: Icons.remove_rounded,
              onTap: onMinimize,
              tooltip: 'Thu nhỏ'),
          _HeaderButton(
              icon: Icons.close_rounded, onTap: onClose, tooltip: 'Đóng'),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _HeaderButton(
      {required this.icon, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, color: Colors.white, size: 20)),
      ),
    );
  }
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

  const AppInitializer(
      {super.key, required this.notificationService, required this.child});

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
    _authSub =
        firebase_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && !_notificationStarted) {
        widget.notificationService.listenForNewMessages(user.uid);
        _notificationStarted = true;
        ErrorLogger.setUserId(user.uid);

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
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
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
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _updatePresence(online: false);
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
  final ChatBubbleService chatBubbleService;
  final NotificationService notificationService;
  final UnifiedBubbleService unifiedBubbleService;

  const ChatApp({
    super.key,
    required this.prefs,
    required this.notificationsPlugin,
    required this.chatBubbleService,
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
      providers: _buildProviders(
        firebaseFirestore: firebaseFirestore,
        firebaseStorage: firebaseStorage,
        firebaseAuth: firebaseAuth,
      ),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return BubbleSystemWrapper(
            child: MaterialApp(
              title: AppConstants.appTitle,
              debugShowCheckedModeBanner: false,
              navigatorKey: AppRouter.navigatorKey,
              themeMode: themeProvider.flutterThemeMode ?? ThemeMode.system,
              theme: themeProvider.lightTheme ??
                  _buildFallbackTheme(Brightness.light),
              darkTheme: themeProvider.darkTheme ??
                  _buildFallbackTheme(Brightness.dark),
              initialRoute: AppRouter.splash,
              onGenerateRoute: AppRouter.onGenerateRoute,
              builder: (context, child) {
                // FIX lỗi 3: BubbleManager và MiniChatOverlayManager nằm
                // bên trong MaterialApp builder — có đầy đủ Overlay và Navigator
                //
                // FIX thứ tự: AppInitializer bọc NGOÀI _AppBuilder để
                // context.read<Provider>() hoạt động đúng
                Widget tree = AppInitializer(
                  notificationService: widget.notificationService,
                  child: _AppBuilder(child: child!),
                );

                if (!kIsWeb) {
                  tree = GroupCallMiniManager(
                    child: BubbleChatChannelManager(
                      child: GroupCallListener(
                        child: CallListener(
                          // FIX lỗi 3: BubbleManager vào đây — trong builder
                          // nên có Overlay từ MaterialApp
                          child: BubbleManager(
                            child: MiniChatOverlayManager(
                              child: tree,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return tree;
              },
            ),
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
          seedColor: const Color(0xFF2979FF), brightness: brightness),
      fontFamily: 'Inter',
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F7FF),
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? const Color(0xFF1A1A2E) : const Color(0xFF2979FF),
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      extensions: [BubbleTheme.of(brightness)],
    );
  }

  List<SingleChildWidget> _buildProviders({
    required FirebaseFirestore firebaseFirestore,
    required FirebaseStorage firebaseStorage,
    required firebase_auth.FirebaseAuth firebaseAuth,
  }) {
    return [
      ChangeNotifierProvider<AutoPilotProvider>(
        create: (_) => AutoPilotProvider(
          firebaseFirestore: firebaseFirestore,
          prefs: widget.prefs,
        ),
      ),
      ChangeNotifierProvider<InsightsProvider>(
        create: (_) => InsightsProvider(
          firebaseFirestore: firebaseFirestore,
        ),
      ),
      ChangeNotifierProvider<AppModeProvider>(create: (_) => AppModeProvider()),
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(
            firebaseAuth: firebaseAuth,
            prefs: widget.prefs,
            firebaseFirestore: firebaseFirestore),
      ),
      ChangeNotifierProvider<custom_auth.PhoneAuthProvider>(
        create: (_) => custom_auth.PhoneAuthProvider(
            firebaseAuth: firebaseAuth,
            firebaseFirestore: firebaseFirestore,
            prefs: widget.prefs),
      ),
      ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(prefs: widget.prefs)),
      ChangeNotifierProvider<TelemetryProvider>(
          create: (_) => TelemetryProvider()),
      ChangeNotifierProvider<StoryProvider>(
        create: (_) => StoryProvider(
            firebaseFirestore: firebaseFirestore,
            firebaseStorage: firebaseStorage),
      ),
      Provider<SettingProvider>(
        create: (_) => SettingProvider(
            prefs: widget.prefs,
            firebaseFirestore: firebaseFirestore,
            firebaseStorage: firebaseStorage),
      ),
      Provider<HomeProvider>(
          create: (_) => HomeProvider(firebaseFirestore: firebaseFirestore)),
      Provider<ChatProvider>(
        create: (_) => ChatProvider(
            prefs: widget.prefs,
            firebaseFirestore: firebaseFirestore,
            firebaseStorage: firebaseStorage),
      ),
      Provider<FriendProvider>(
          create: (_) => FriendProvider(firebaseFirestore: firebaseFirestore)),
      Provider<ReactionProvider>(
          create: (_) =>
              ReactionProvider(firebaseFirestore: firebaseFirestore)),
      Provider<MessageProvider>(
          create: (_) => MessageProvider(firebaseFirestore: firebaseFirestore)),
      Provider<ConversationProvider>(
          create: (_) =>
              ConversationProvider(firebaseFirestore: firebaseFirestore)),
      Provider<ReminderProvider>(
        create: (_) => ReminderProvider(
            firebaseFirestore: firebaseFirestore,
            notificationsPlugin: widget.notificationsPlugin),
      ),
      Provider<AutoDeleteProvider>(
          create: (_) =>
              AutoDeleteProvider(firebaseFirestore: firebaseFirestore)),
      Provider<ConversationLockProvider>(
          create: (_) =>
              ConversationLockProvider(firebaseFirestore: firebaseFirestore)),
      Provider<ViewOnceProvider>(
          create: (_) =>
              ViewOnceProvider(firebaseFirestore: firebaseFirestore)),
      Provider<SmartReplyProvider>(create: (_) => SmartReplyProvider()),
      Provider<UserPresenceProvider>(
          create: (_) =>
              UserPresenceProvider(firebaseFirestore: firebaseFirestore)),
      Provider<LocationProvider>(create: (_) => LocationProvider()),
      Provider<TranslationProvider>(create: (_) => TranslationProvider()),
      Provider<ChatBubbleService>(create: (_) => widget.chatBubbleService),
      Provider<UnifiedBubbleService>(
          create: (_) => widget.unifiedBubbleService,
          dispose: (_, s) => s.dispose()),
      Provider<NotificationService>(create: (_) => widget.notificationService),
      ChangeNotifierProvider<BubbleSettingsService>(
          create: (_) => BubbleSettingsService()),
      Provider<BubbleSoundService>(create: (_) => BubbleSoundService()),
      Provider<ContextualBubbleService>(
          create: (_) => ContextualBubbleService.instance),
      ChangeNotifierProvider<GroupCallProvider>(
        create: (_) => GroupCallProvider(
          currentUserId: widget.prefs.getString('currentUserId') ?? '',
        ),
      ),
    ];
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
            MediaQuery.textScalerOf(context).scale(1.0).clamp(0.8, 1.3)),
      ),
      child: child,
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
        return _slide(GroupCallHistoryPage(
          groupId: args['groupId'] as String,
          groupName: args['groupName'] as String,
          currentUserId: args['currentUserId'] as String,
        ));
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
          final tween =
              Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic));
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
              const Icon(Icons.error_outline_rounded,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Trang không tồn tại',
                  style: Theme.of(context).textTheme.titleLarge),
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

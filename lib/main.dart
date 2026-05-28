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

// ─── Globals ──────────────────────────────────────────────────────────────────

/// Plugin thông báo cục bộ – được khởi tạo một lần, dùng toàn app
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// NavigatorKey toàn cục – dùng để navigate từ ngoài BuildContext
/// (notification tap, bubble chat, background message handler…)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ─── Background FCM Handler (phải là top-level function) ─────────────────────

/// Xử lý FCM message khi app ở background / terminated
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase cần được khởi tạo lại trong isolate nền
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('🔔 Background FCM: ${message.messageId}');
}

// ─── Entry point ─────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tải biến môi trường
  await dotenv.load(fileName: '.env');

  // Khóa hướng màn hình (portrait only trên mobile)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Cấu hình status bar / navigation bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // ── Khởi tạo Firebase ──────────────────────────────────────────────────────
  await _initializeFirebase();

  // ── Khởi tạo Error Logger ─────────────────────────────────────────────────
  await ErrorLogger.initialize();

  // ── Timezone ──────────────────────────────────────────────────────────────
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

  // ── SharedPreferences ─────────────────────────────────────────────────────
  final prefs = await SharedPreferences.getInstance();

  // ── Notifications ─────────────────────────────────────────────────────────
  if (!kIsWeb) {
    await _initializeLocalNotifications(flutterLocalNotificationsPlugin);
    await _initializeFcm();
  }

  // ── Services ──────────────────────────────────────────────────────────────
  final unifiedBubbleService = UnifiedBubbleService();
  final chatBubbleService = ChatBubbleService();
  final notificationService = NotificationService();

  runApp(MyApp(
    prefs: prefs,
    notificationsPlugin: flutterLocalNotificationsPlugin,
    chatBubbleService: chatBubbleService,
    notificationService: notificationService,
    unifiedBubbleService: unifiedBubbleService,
  ));
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ✅ PHẢI set settings NGAY ĐÂY — trước AppCheck và mọi thứ khác
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('✅ Firestore Offline Persistence bật');
    } catch (e) {
      debugPrint('⚠️ Offline Persistence (Web không hỗ trợ): $e');
    }

    // App Check — sau khi settings đã được set
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );

    // Local DB (Hive)
    await LocalDbService().initialize();
    debugPrint('✅ LocalDbService khởi tạo xong');

    // Sync Manager
    SyncManager().startListening();
    debugPrint('✅ SyncManager đang lắng nghe');
  } catch (e, stack) {
    debugPrint('❌ Firebase init lỗi: $e');
    await ErrorLogger.logError(e, stack, context: 'Firebase.initializeApp');
  }
}

// ─── FCM Setup ────────────────────────────────────────────────────────────────

Future<void> _initializeFcm() async {
  try {
    // Đăng ký handler background message
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;

    // Yêu cầu quyền thông báo (iOS / Android 13+)
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('🔔 FCM permission: ${settings.authorizationStatus.name}');

    // Lấy FCM token để lưu server-side
    final token = await messaging.getToken();
    if (token != null) {
      debugPrint('📱 FCM Token: ${token.substring(0, 20)}...');
      // TODO: Lưu token lên Firestore theo userId khi đăng nhập
    }

    // Refresh token
    messaging.onTokenRefresh.listen((newToken) {
      debugPrint('🔄 FCM Token refreshed');
      // TODO: Cập nhật token mới lên Firestore
    });
  } catch (e) {
    debugPrint('⚠️ FCM init lỗi: $e');
  }
}

// ─── Local Notifications Setup ───────────────────────────────────────────────

Future<void> _initializeLocalNotifications(
  FlutterLocalNotificationsPlugin plugin,
) async {
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

    if (Platform.isAndroid) {
      await _setupAndroidNotificationChannels(plugin);
    }

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
  FlutterLocalNotificationsPlugin plugin,
) async {
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin == null) return;

  await androidPlugin.requestNotificationsPermission();

  try {
    await androidPlugin.requestExactAlarmsPermission();
  } catch (e) {
    debugPrint('⚠️ Exact Alarms Permission: $e');
  }

  // Kênh tin nhắn
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

  // Kênh nhắc nhở
  await androidPlugin.createNotificationChannel(
    const AndroidNotificationChannel(
      AppConstants.reminderChannelId,
      'Nhắc nhở tin nhắn',
      description: 'Nhắc nhở về các tin nhắn chưa đọc',
      importance: Importance.high,
    ),
  );

  // Kênh cuộc gọi
  await androidPlugin.createNotificationChannel(
    const AndroidNotificationChannel(
      AppConstants.callChannelId,
      'Cuộc gọi đến',
      description: 'Thông báo cuộc gọi thoại / video',
      importance: Importance.max,
      playSound: true,
    ),
  );
}

/// Callback khi người dùng tap vào notification (foreground)
void _onNotificationTapped(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null) return;

  debugPrint('🔔 Notification tapped: $payload');

  // Parse payload JSON và navigate đến chat tương ứng
  try {
    // Payload format: "peerId|peerNickname|peerAvatar"
    final parts = payload.split('|');
    if (parts.length >= 2) {
      _navigateToChat(
        peerId: parts[0],
        peerNickname: parts[1],
        peerAvatar: parts.length > 2 ? parts[2] : '',
      );
    }
  } catch (e) {
    debugPrint('⚠️ Notification payload parse lỗi: $e');
  }
}

/// Callback khi tap notification từ background (top-level, không dùng được context)
@pragma('vm:entry-point')
void _onBackgroundNotificationTapped(NotificationResponse response) {
  debugPrint('🔔 Background notification tapped: ${response.payload}');
}

/// Navigate đến ChatPage từ notification tap
void _navigateToChat({
  required String peerId,
  required String peerNickname,
  required String peerAvatar,
}) {
  final state = navigatorKey.currentState;
  if (state == null) return;

  // Pop về root trước nếu đang ở màn hình khác
  state.pushNamedAndRemoveUntil(
    '/',
    (route) => route.isFirst,
  );

  state.push(
    MaterialPageRoute(
      settings: const RouteSettings(name: '/chat'),
      builder: (_) => ChatPage(
        arguments: ChatPageArguments(
          peerId: peerId,
          peerNickname: peerNickname,
          peerAvatar: peerAvatar,
        ),
      ),
    ),
  );
}

// ─── BubbleChatChannelManager ─────────────────────────────────────────────────

/// Quản lý MethodChannel để xử lý navigation từ Android Bubble Chat
class BubbleChatChannelManager extends StatefulWidget {
  final Widget child;
  const BubbleChatChannelManager({super.key, required this.child});

  @override
  State<BubbleChatChannelManager> createState() =>
      _BubbleChatChannelManagerState();
}

class _BubbleChatChannelManagerState extends State<BubbleChatChannelManager> {
  static const _channel = MethodChannel('bubble_chat_channel');

  /// Deduplicate navigation (tránh push cùng route 2 lần trong 2 giây)
  final _recentNavigations = <String>{};

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
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
        if (navigatorKey.currentState?.canPop() == true) {
          navigatorKey.currentState!.pop();
        }
      case 'openApp':
        // Bring app to foreground
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

    // Deduplicate: 2-second window per peerId
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 2000;
    final dedupKey = '$peerId:$bucket';
    if (_recentNavigations.contains(dedupKey)) return;
    _recentNavigations.add(dedupKey);
    Future.delayed(
      const Duration(seconds: 10),
      () => _recentNavigations.remove(dedupKey),
    );

    // Đợi navigator sẵn sàng (tối đa 5 lần retry)
    await _waitForNavigator();

    if (navigatorKey.currentState == null) {
      _recentNavigations.remove(dedupKey);
      return;
    }

    try {
      final args = ChatPageArguments(
        peerId: peerId,
        peerNickname: peerNickname,
        peerAvatar: peerAvatar,
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/chat'),
          builder: (_) => ChatPage(
            arguments: args,
            isBubbleMode: isBubbleMode,
          ),
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
      if (navigatorKey.currentState != null) return;
      await Future.delayed(Duration(milliseconds: 100 * (1 << i)));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─── MiniChatOverlayManager ───────────────────────────────────────────────────

/// Hiển thị floating mini-chat overlay qua MethodChannel
class MiniChatOverlayManager extends StatefulWidget {
  final Widget child;
  const MiniChatOverlayManager({super.key, required this.child});

  @override
  State<MiniChatOverlayManager> createState() => _MiniChatOverlayManagerState();
}

class _MiniChatOverlayManagerState extends State<MiniChatOverlayManager> {
  static const _channel = MethodChannel('mini_chat_channel');
  OverlayEntry? _overlay;

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
    _removeOverlay();
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
    if (mounted) Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    try {
      _overlay?.remove();
    } catch (_) {}
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─── MiniChat Overlay Scaffold ────────────────────────────────────────────────

/// Wrapper xử lý positioning + dismiss khi tap ngoài
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
          // Tap ngoài để minimize
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

// ─── MiniChatOverlayWidget ────────────────────────────────────────────────────

/// Floating, draggable cửa sổ mini chat
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

  // Adaptive size
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
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutBack,
    );
    _animCtrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_positionInitialized) {
      final size = MediaQuery.sizeOf(context);
      _position = Offset(
        (size.width - _width) / 2,
        (size.height - _height) / 2,
      );
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
            color: const Color(0xFF1E88E5).withOpacity(0.6),
            width: 1.5,
          ),
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

// ─── MiniChat Header ──────────────────────────────────────────────────────────

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
        gradient: LinearGradient(
          colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
        ),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 17,
            backgroundColor: Colors.white24,
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isEmpty
                ? Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 9),

          // Tên
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Mini Chat',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          // Minimize
          _HeaderButton(
            icon: Icons.remove_rounded,
            onTap: onMinimize,
            tooltip: 'Thu nhỏ',
          ),

          // Close
          _HeaderButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            tooltip: 'Đóng',
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _HeaderButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ─── BubbleModeDetector ───────────────────────────────────────────────────────

/// Phát hiện app có đang chạy trong Android Bubble Mode không
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

// ─── MyApp ────────────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  final FlutterLocalNotificationsPlugin notificationsPlugin;
  final ChatBubbleService chatBubbleService;
  final NotificationService notificationService;
  final UnifiedBubbleService unifiedBubbleService;

  const MyApp({
    super.key,
    required this.prefs,
    required this.notificationsPlugin,
    required this.chatBubbleService,
    required this.notificationService,
    required this.unifiedBubbleService,
  });

  @override
  Widget build(BuildContext context) {
    // Firebase instances
    final firebaseFirestore = FirebaseFirestore.instance;
    final firebaseStorage = FirebaseStorage.instance;
    final firebaseAuth = firebase_auth.FirebaseAuth.instance;

    // Widget tree – bọc các layer theo thứ tự từ ngoài vào trong
    Widget appTree = AppInitializer(
      notificationService: notificationService,
      child: const SplashPage(),
    );

    if (!kIsWeb) {
      appTree = BubbleChatChannelManager(
        child: GroupCallListener(
          child: CallListener(
            child: BubbleManager(
              child: MiniChatOverlayManager(
                child: appTree,
              ),
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: _buildProviders(
        firebaseFirestore: firebaseFirestore,
        firebaseStorage: firebaseStorage,
        firebaseAuth: firebaseAuth,
      ),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: AppConstants.appTitle,
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            themeMode: themeProvider.flutterThemeMode,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            // Routes được khai báo rõ ràng
            routes: AppRoutes.routes,
            // onGenerateRoute để xử lý dynamic routes
            onGenerateRoute: AppRoutes.onGenerateRoute,
            // Builder để inject overlay (safe area, accessibility)
            builder: (context, child) => _AppBuilder(child: child),
            home: appTree, // <--- GIỮ LẠI ĐỂ RENDER APPTREE TRÊN ROOT
          );
        },
      ),
    );
  }

  List<SingleChildWidget> _buildProviders({
    required FirebaseFirestore firebaseFirestore,
    required FirebaseStorage firebaseStorage,
    required firebase_auth.FirebaseAuth firebaseAuth,
  }) {
    return [
      // ── Auth & User ──────────────────────────────────────────────────────
      ChangeNotifierProvider<AppModeProvider>(
        create: (_) => AppModeProvider(),
      ),
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

      // ── UI & Theme ───────────────────────────────────────────────────────
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(prefs: prefs),
      ),
      ChangeNotifierProvider<TelemetryProvider>(
        create: (_) => TelemetryProvider(),
      ),

      // ── Feature Providers ────────────────────────────────────────────────
      ChangeNotifierProvider<StoryProvider>(
        create: (_) => StoryProvider(
          firebaseFirestore: firebaseFirestore,
          firebaseStorage: firebaseStorage,
        ),
      ),

      // ── Non-notifying Providers (Provider, không ChangeNotifier) ─────────
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
        create: (_) =>
            ConversationProvider(firebaseFirestore: firebaseFirestore),
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
      Provider<SmartReplyProvider>(
        create: (_) => SmartReplyProvider(),
      ),
      Provider<UserPresenceProvider>(
        create: (_) =>
            UserPresenceProvider(firebaseFirestore: firebaseFirestore),
      ),
      Provider<LocationProvider>(
        create: (_) => LocationProvider(),
      ),
      Provider<TranslationProvider>(
        create: (_) => TranslationProvider(),
      ),

      // ── Services ─────────────────────────────────────────────────────────
      Provider<ChatBubbleService>(create: (_) => chatBubbleService),
      Provider<UnifiedBubbleService>(create: (_) => unifiedBubbleService),
      Provider<NotificationService>(create: (_) => notificationService),
    ];
  }
}

// ─── AppBuilder ────────────────────────────────────────────────────────────────

/// Wrapper toàn cục: inject banner debug, connectivity snackbar, v.v.
class _AppBuilder extends StatelessWidget {
  final Widget? child;
  const _AppBuilder({this.child});

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      // Ngăn text scale vượt quá 1.3x (tránh vỡ layout)
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(
          MediaQuery.textScalerOf(context).scale(1.0).clamp(0.8, 1.3),
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }
}

// ─── AppRoutes ─────────────────────────────────────────────────────────────────

/// Tập trung định nghĩa tất cả routes của app
class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const chat = '/chat';
  static const profile = '/profile';
  static const settings = '/settings';
  static const login = '/login';

  static Map<String, WidgetBuilder> get routes => {
        // ĐÃ SỬA: Bỏ `home: (_) => const SplashPage()` để sửa lỗi
        // 'home == null || !routes.containsKey(Navigator.defaultRouteName)'
        // Vì MaterialApp đang dùng thuộc tính `home` để load `appTree`.
      };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case chat:
        final args = settings.arguments;
        if (args is ChatPageArguments) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => ChatPage(arguments: args),
          );
        }
        // Fallback nếu arguments sai kiểu
        return _errorRoute('Chat page: arguments không hợp lệ');

      default:
        return null; // Dùng routes map
    }
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

// ─── AppInitializer ───────────────────────────────────────────────────────────

/// Khởi động các service cần BuildContext sau khi cây widget sẵn sàng
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

  /// Được gọi sau frame đầu tiên – context đã đầy đủ
  void _onReady() {
    _startNotificationService();
    _handleFcmForegroundMessages();
    _handleNotificationLaunch();
  }

  /// Lắng nghe thay đổi auth → bật/tắt notification service
  void _startNotificationService() {
    _authSub =
        firebase_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && !_notificationStarted) {
        widget.notificationService.listenForNewMessages(user.uid);
        _notificationStarted = true;

        // Gán userId cho crash reporting & analytics
        ErrorLogger.setUserId(user.uid);
      } else if (user == null) {
        widget.notificationService.stopListening();
        _notificationStarted = false;
        ErrorLogger.clearUserId();
      }
    });
  }

  /// Xử lý FCM message khi app đang foreground
  void _handleFcmForegroundMessages() {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('📩 Foreground FCM: ${message.notification?.title}');
      // TODO: Hiển thị in-app notification banner
    });

    // Khi user tap notification từ background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('🔔 FCM opened app: ${message.data}');
      final peerId = message.data['peerId'] as String?;
      final peerNickname = message.data['peerNickname'] as String?;
      if (peerId != null && peerNickname != null) {
        _navigateToChat(
          peerId: peerId,
          peerNickname: peerNickname,
          peerAvatar: message.data['peerAvatar'] ?? '',
        );
      }
    });
  }

  /// Kiểm tra app có được mở từ notification terminated không
  Future<void> _handleNotificationLaunch() async {
    try {
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        final peerId = initialMessage.data['peerId'] as String?;
        final peerNickname = initialMessage.data['peerNickname'] as String?;
        if (peerId != null && peerNickname != null) {
          // Delay để đảm bảo navigator đã sẵn sàng
          await Future.delayed(const Duration(milliseconds: 800));
          _navigateToChat(
            peerId: peerId,
            peerNickname: peerNickname,
            peerAvatar: initialMessage.data['peerAvatar'] ?? '',
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Initial FCM message lỗi: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Track app lifecycle cho analytics
    ErrorLogger.addBreadcrumb(state.name, category: 'lifecycle');

    switch (state) {
      case AppLifecycleState.resumed:
        // App về foreground → cập nhật presence online
        _updatePresence(online: true);
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App vào background → cập nhật presence offline
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

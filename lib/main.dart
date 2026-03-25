import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/phone_auth_provider.dart'
    as custom_auth;
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/utils/utils.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    print('✅ Firebase initialized successfully');
  } catch (e) {
    print('❌ Firebase initialization error: $e');
  }

  // FIX #5: KHÔNG gọi setupBubbleChatChannel() ở đây nữa.
  // Handler được setup trong BubbleChatChannelManager widget (stateful),
  // đảm bảo cleanup đúng khi widget bị dispose (hot-reload, rebuild).
  // Xem class BubbleChatChannelManager bên dưới.

  await ErrorLogger.initialize();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
  final prefs = await SharedPreferences.getInstance();

  await _initializeNotifications(flutterLocalNotificationsPlugin);

  final unifiedBubbleService = UnifiedBubbleService();
  final chatBubbleService = ChatBubbleService();
  final notificationService = NotificationService();

  print('✅ App initialized successfully');

  runApp(MyApp(
    prefs: prefs,
    notificationsPlugin: flutterLocalNotificationsPlugin,
    chatBubbleService: chatBubbleService,
    notificationService: notificationService,
    unifiedBubbleService: unifiedBubbleService,
  ));
}

// ========================================
// FIX #5: BubbleChatChannelManager — Stateful widget quản lý channel lifecycle
// ========================================

/// Wraps toàn bộ app để quản lý MethodChannel handler cho bubble navigation.
///
/// FIX #5 — MethodChannel handler leak:
///   Trước: setupBubbleChatChannel() trong main() → handler toàn cục, không dispose,
///          navigatorKey giữ strong reference → hot-reload tạo duplicate handler,
///          mỗi navigate event bị handle 2+ lần.
///
///   Sau:  BubbleChatChannelManager là StatefulWidget, setup handler trong initState(),
///         dispose handler trong dispose(). Hot-reload → old State.dispose() → new
///         State.initState() → luôn chỉ có 1 handler active.
///         Dùng Set<String> để dedup navigation requests trong cùng session.
class BubbleChatChannelManager extends StatefulWidget {
  final Widget child;
  const BubbleChatChannelManager({super.key, required this.child});

  @override
  State<BubbleChatChannelManager> createState() =>
      _BubbleChatChannelManagerState();
}

class _BubbleChatChannelManagerState extends State<BubbleChatChannelManager> {
  // Channel duy nhất — tạo trong State để lifecycle gắn với widget
  static const _channel = MethodChannel('bubble_chat_channel');

  // FIX #5: Dedup set — tránh duplicate navigate khi handler bị gọi nhiều lần
  // Key = "$peerId:$timestamp_bucket" (bucket = giây hiện tại / 2)
  final _recentNavigations = <String>{};

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethodCall);
    print('✅ BubbleChatChannelManager: handler registered');
  }

  @override
  void dispose() {
    // FIX #5: Clear handler khi dispose → không còn leak
    _channel.setMethodCallHandler(null);
    _recentNavigations.clear();
    print('✅ BubbleChatChannelManager: handler disposed');
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('📞 Bubble channel received: ${call.method}');

    if (call.method == 'navigateToChat') {
      return await _handleNavigateToChat(call.arguments);
    } else if (call.method == 'onBackPressed') {
      print('⬅️ Back pressed in bubble');
      if (navigatorKey.currentState?.canPop() == true) {
        navigatorKey.currentState!.pop();
      }
    }
    return null;
  }

  Future<dynamic> _handleNavigateToChat(dynamic arguments) async {
    final peerId = arguments['peerId'] as String?;
    final peerNickname = arguments['peerNickname'] as String?;
    final peerAvatar = arguments['peerAvatar'] as String?;
    final isBubbleMode = arguments['isBubbleMode'] as bool? ?? false;

    if (peerId == null || peerNickname == null) {
      print('❌ Missing required args for bubble navigation');
      return null;
    }

    // FIX #5: Dedup — tạo key từ peerId + time bucket (2-giây window)
    final timeBucket = DateTime.now().millisecondsSinceEpoch ~/ 2000;
    final dedupKey = '$peerId:$timeBucket';

    if (_recentNavigations.contains(dedupKey)) {
      print('ℹ️ Duplicate navigation request ignored: $peerNickname');
      return null;
    }
    _recentNavigations.add(dedupKey);

    // Cleanup old dedup keys sau 10 giây để tránh set grow unbounded
    Future.delayed(const Duration(seconds: 10), () {
      _recentNavigations.remove(dedupKey);
    });

    print('🧭 Navigating to: $peerNickname (bubble=$isBubbleMode)');

    // Retry loop chờ navigator ready
    int retries = 0;
    const maxRetries = 5;
    while (navigatorKey.currentState == null && retries < maxRetries) {
      final delay = Duration(milliseconds: 100 * (1 << retries));
      print(
          '⏳ Navigator not ready, retry $retries/$maxRetries (${delay.inMilliseconds}ms)');
      await Future.delayed(delay);
      retries++;
    }

    if (navigatorKey.currentState == null) {
      print('❌ Navigator failed after $maxRetries retries');
      _recentNavigations.remove(dedupKey); // Cleanup để cho phép retry sau
      return null;
    }

    // FIX #5: Check route hiện tại để tránh push duplicate route
    try {
      final currentContext = navigatorKey.currentContext;
      if (currentContext != null) {
        final currentRoute = ModalRoute.of(currentContext);
        final routeName = currentRoute?.settings.name ?? '';

        if (routeName == '/chat') {
          final currentArgs = currentRoute?.settings.arguments;
          if (currentArgs is ChatPageArguments &&
              currentArgs.peerId == peerId) {
            print('ℹ️ Already on chat with $peerNickname, skipping push');
            return null;
          }
        }
      }
    } catch (e) {
      print('⚠️ Error checking current route: $e');
    }

    try {
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          settings: RouteSettings(
            name: '/chat',
            arguments: ChatPageArguments(
              peerId: peerId,
              peerNickname: peerNickname,
              peerAvatar: peerAvatar ?? '',
            ),
          ),
          builder: (_) => ChatPage(
            arguments: ChatPageArguments(
              peerId: peerId,
              peerNickname: peerNickname,
              peerAvatar: peerAvatar ?? '',
            ),
            isBubbleMode: isBubbleMode,
          ),
        ),
      );
      print('✅ Navigation complete to: $peerNickname');
    } catch (e) {
      print('❌ Navigation failed: $e');
      _recentNavigations.remove(dedupKey);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ========================================
// NOTIFICATION INIT
// ========================================

Future<void> _initializeNotifications(
  FlutterLocalNotificationsPlugin plugin,
) async {
  try {
    const initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    const initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('🔔 Notification clicked: ${response.payload}');
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        await androidPlugin.requestExactAlarmsPermission();
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'message_reminders',
            'Message Reminders',
            description: 'Reminders for messages',
            importance: Importance.high,
          ),
        );
      }
    }

    if (Platform.isIOS) {
      await plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    print('✅ Notifications initialized');
  } catch (e) {
    print('❌ Notification init error: $e');
  }
}

// ========================================
// MyApp
// ========================================

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
    final firebaseFirestore = FirebaseFirestore.instance;
    final firebaseStorage = FirebaseStorage.instance;
    final firebaseAuth = firebase_auth.FirebaseAuth.instance;
    final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(
            firebaseAuth: firebaseAuth,
            googleSignIn: googleSignIn,
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
          create: (_) =>
              ConversationProvider(firebaseFirestore: firebaseFirestore),
        ),
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(prefs: prefs),
        ),
        Provider<ReminderProvider>(
          create: (_) => ReminderProvider(
            firebaseFirestore: firebaseFirestore,
            notificationsPlugin: notificationsPlugin,
          ),
        ),
        Provider<AutoDeleteProvider>(
          create: (_) =>
              AutoDeleteProvider(firebaseFirestore: firebaseFirestore),
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
          create: (_) =>
              UserPresenceProvider(firebaseFirestore: firebaseFirestore),
        ),
        Provider<LocationProvider>(create: (_) => LocationProvider()),
        Provider<TranslationProvider>(create: (_) => TranslationProvider()),
        Provider<ChatBubbleService>(create: (_) => chatBubbleService),
        Provider<UnifiedBubbleService>(create: (_) => unifiedBubbleService),
        Provider<NotificationService>(create: (_) => notificationService),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: AppConstants.appTitle,
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            themeMode: themeProvider.getFlutterThemeMode(context),
            theme: AppThemes.lightTheme(themeProvider.getPrimaryColor()),
            darkTheme: AppThemes.darkTheme(themeProvider.getPrimaryColor()),
            // FIX #5: Wrap toàn bộ home tree với BubbleChatChannelManager
            // để channel handler có proper lifecycle management
            home: BubbleChatChannelManager(
              child: CallListener(
                child: BubbleManager(
                  child: MiniChatOverlayManager(
                    child: AppInitializer(
                      notificationService: notificationService,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ========================================
// AppInitializer
// ========================================

class AppInitializer extends StatefulWidget {
  final NotificationService notificationService;
  const AppInitializer({super.key, required this.notificationService});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startNotificationService();
    _logBubbleImplementation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('📱 App lifecycle: $state');
    if (state == AppLifecycleState.paused) {
      print('⏸️ App going to background');
    } else if (state == AppLifecycleState.resumed) {
      print('▶️ App resumed');
    }
  }

  Future<void> _logBubbleImplementation() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    final unifiedService = context.read<UnifiedBubbleService>();
    await Future.delayed(const Duration(seconds: 1));
    final impl = unifiedService.getImplementationInfo();
    print('🎈 Bubble Implementation: $impl');
  }

  Future<void> _startNotificationService() async {
    await Future.delayed(const Duration(milliseconds: 500));
    final auth = firebase_auth.FirebaseAuth.instance;
    auth.authStateChanges().listen((user) {
      if (user != null) {
        print('👤 User logged in, starting notification service');
        widget.notificationService.listenForNewMessages(user.uid);
      } else {
        print('👤 User logged out, stopping notification service');
        widget.notificationService.stopListening();
      }
    });
  }

  @override
  Widget build(BuildContext context) => SplashPage();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// ========================================
// MiniChatOverlayManager (giữ nguyên logic, không thay đổi)
// ========================================

class MiniChatOverlayManager extends StatefulWidget {
  final Widget child;
  const MiniChatOverlayManager({super.key, required this.child});

  @override
  State<MiniChatOverlayManager> createState() => _MiniChatOverlayManagerState();
}

class _MiniChatOverlayManagerState extends State<MiniChatOverlayManager> {
  static const MethodChannel _miniChatChannel =
      MethodChannel('mini_chat_channel');

  OverlayEntry? _miniChatOverlay;

  @override
  void initState() {
    super.initState();
    _setupMiniChatChannel();
  }

  @override
  void dispose() {
    _hideMiniChatOverlay();
    _miniChatChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _setupMiniChatChannel() {
    _miniChatChannel.setMethodCallHandler((call) async {
      if (call.method == 'navigateToMiniChat') {
        final peerId = call.arguments['peerId'] as String?;
        final peerNickname = call.arguments['peerNickname'] as String?;
        final peerAvatar = call.arguments['peerAvatar'] as String?;
        if (peerId != null && peerNickname != null && mounted) {
          _showMiniChatOverlay(peerId, peerNickname, peerAvatar ?? '');
        }
      } else if (call.method == 'minimize' || call.method == 'close') {
        _hideMiniChatOverlay();
      }
      return null;
    });
  }

  void _showMiniChatOverlay(String userId, String userName, String avatarUrl) {
    _hideMiniChatOverlay();
    _miniChatOverlay = OverlayEntry(
      builder: (context) => Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          alignment: Alignment.center,
          child: MiniChatOverlayWidget(
            userId: userId,
            userName: userName,
            avatarUrl: avatarUrl,
            onMinimize: () {
              _hideMiniChatOverlay();
              _miniChatChannel.invokeMethod('minimize', {'userId': userId});
            },
            onClose: () {
              _hideMiniChatOverlay();
              _miniChatChannel.invokeMethod('close', {'userId': userId});
            },
          ),
        ),
      ),
    );
    if (mounted) {
      Overlay.of(context).insert(_miniChatOverlay!);
    }
  }

  void _hideMiniChatOverlay() {
    try {
      _miniChatOverlay?.remove();
      _miniChatOverlay = null;
    } catch (e) {
      print('❌ Error removing mini chat overlay: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ========================================
// MiniChatOverlayWidget (giữ nguyên)
// ========================================

class MiniChatOverlayWidget extends StatefulWidget {
  final String userId;
  final String userName;
  final String avatarUrl;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

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

class _MiniChatOverlayWidgetState extends State<MiniChatOverlayWidget> {
  Offset _position = const Offset(20, 100);
  bool _isDragging = false;

  static const double _width = 340;
  static const double _height = 500;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    if (!_isDragging) {
      setState(() {
        _position = Offset(
          ((size.width - _width) / 2).clamp(0, size.width - _width),
          ((size.height - _height) / 2).clamp(0, size.height - _height),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxX = size.width - _width;
    final maxY = size.height - _height;

    return Positioned(
      left: _position.dx.clamp(0, maxX),
      top: _position.dy.clamp(0, maxY),
      child: GestureDetector(
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (details) => setState(() => _position += details.delta),
        onPanEnd: (_) => setState(() => _isDragging = false),
        child: Material(
          elevation: _isDragging ? 16 : 8,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xff2196f3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(14)),
                    child: ChatPage(
                      arguments: ChatPageArguments(
                        peerId: widget.userId,
                        peerNickname: widget.userName,
                        peerAvatar: widget.avatarUrl,
                      ),
                      isMiniChat: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xff2196f3),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          CircleAvatar(
            backgroundImage: widget.avatarUrl.isNotEmpty
                ? NetworkImage(widget.avatarUrl)
                : null,
            radius: 16,
            child: widget.avatarUrl.isEmpty
                ? const Icon(Icons.person, size: 16, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.userName,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove, color: Colors.white, size: 20),
            onPressed: widget.onMinimize,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class BubbleModeDetector {
  static const MethodChannel _channel = MethodChannel('bubble_chat_channel');

  static Future<bool> isBubbleMode() async {
    try {
      final result = await _channel.invokeMethod<bool>('getBubbleMode');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}

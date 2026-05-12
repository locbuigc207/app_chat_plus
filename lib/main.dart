// lib/main.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');
  } catch (e) {
    print('❌ Firebase initialization error: $e');
  }

  await ErrorLogger.initialize();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
  final prefs = await SharedPreferences.getInstance();

  // Chỉ khởi tạo Local Notifications trên Mobile
  if (!kIsWeb) {
    await _initializeNotifications(flutterLocalNotificationsPlugin);
  }

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

// ============================================================
// BubbleChatChannelManager
// ============================================================

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
    if (!kIsWeb) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      _channel.setMethodCallHandler(null);
    }
    _recentNavigations.clear();
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'navigateToChat') {
      return _handleNavigateToChat(call.arguments);
    } else if (call.method == 'onBackPressed') {
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

    if (peerId == null || peerNickname == null) return null;

    final timeBucket = DateTime.now().millisecondsSinceEpoch ~/ 2000;
    final dedupKey = '$peerId:$timeBucket';

    if (_recentNavigations.contains(dedupKey)) return null;
    _recentNavigations.add(dedupKey);
    Future.delayed(
        const Duration(seconds: 10), () => _recentNavigations.remove(dedupKey));

    int retries = 0;
    const maxRetries = 5;
    while (navigatorKey.currentState == null && retries < maxRetries) {
      await Future.delayed(Duration(milliseconds: 100 * (1 << retries)));
      retries++;
    }

    if (navigatorKey.currentState == null) {
      _recentNavigations.remove(dedupKey);
      return null;
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
    } catch (e) {
      _recentNavigations.remove(dedupKey);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ============================================================
// Notification init (Mobile only)
// ============================================================

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
      onDidReceiveNotificationResponse: (NotificationResponse response) {},
    );

    if (Platform.isAndroid) {
      final androidPlugin = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        try {
          await androidPlugin.requestExactAlarmsPermission();
        } catch (e) {
          print('⚠️ Exact Alarms Permission warning: $e');
        }
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
  } catch (e) {
    print('❌ Notification init error: $e');
  }
}

// ============================================================
// MyApp
// ============================================================

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

    Widget appTree = AppInitializer(
      notificationService: notificationService,
      child: SplashPage(),
    );

    // Không bọc Native MethodChannels trên Web
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
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          // ✅ Bỏ googleSignIn — AuthProvider tự khởi tạo nội bộ
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
            home: appTree,
          );
        },
      ),
    );
  }
}

// ============================================================
// AppInitializer
// ============================================================

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startNotificationService();
  }

  Future<void> _startNotificationService() async {
    await Future.delayed(const Duration(milliseconds: 500));
    final auth = firebase_auth.FirebaseAuth.instance;
    auth.authStateChanges().listen((user) {
      if (user != null) {
        widget.notificationService.listenForNewMessages(user.uid);
      } else {
        widget.notificationService.stopListening();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// ============================================================
// MiniChatOverlayManager
// ============================================================

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
    if (!kIsWeb) {
      _setupMiniChatChannel();
    }
  }

  @override
  void dispose() {
    _hideMiniChatOverlay();
    if (!kIsWeb) {
      _miniChatChannel.setMethodCallHandler(null);
    }
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
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ============================================================
// MiniChatOverlayWidget (Responsive)
// ============================================================

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

  double get _width => MediaQuery.of(context).size.width > 400
      ? 340
      : MediaQuery.of(context).size.width * 0.85;
  double get _height => MediaQuery.of(context).size.height > 700
      ? 500
      : MediaQuery.of(context).size.height * 0.7;

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

// ============================================================
// BubbleModeDetector
// ============================================================

class BubbleModeDetector {
  static const MethodChannel _channel = MethodChannel('bubble_chat_channel');

  static Future<bool> isBubbleMode() async {
    if (kIsWeb) return false;
    try {
      final result = await _channel.invokeMethod<bool>('getBubbleMode');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}

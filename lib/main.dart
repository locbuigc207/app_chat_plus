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

  setupBubbleChatChannel();

  await ErrorLogger.initialize();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
  final prefs = await SharedPreferences.getInstance();

  await _initializeNotifications(flutterLocalNotificationsPlugin);

  final unifiedBubbleService = UnifiedBubbleService();

  final chatBubbleService = ChatBubbleService();
  final notificationService = NotificationService();

  print(' App initialized successfully');

  runApp(MyApp(
    prefs: prefs,
    notificationsPlugin: flutterLocalNotificationsPlugin,
    chatBubbleService: chatBubbleService, // Legacy
    notificationService: notificationService,
    unifiedBubbleService: unifiedBubbleService, // NEW
  ));
}

void setupBubbleChatChannel() {
  const channel = MethodChannel('bubble_chat_channel');

  channel.setMethodCallHandler((call) async {
    print(' Bubble channel received: ${call.method}');

    if (call.method == 'navigateToChat') {
      final peerId = call.arguments['peerId'] as String?;
      final peerNickname = call.arguments['peerNickname'] as String?;
      final peerAvatar = call.arguments['peerAvatar'] as String?;
      final isBubbleMode = call.arguments['isBubbleMode'] as bool? ?? false;

      if (peerId == null || peerNickname == null) {
        print(' Missing required arguments for navigation');
        return null;
      }

      print(' Smart navigation to: $peerNickname (bubble: $isBubbleMode)');

      int retries = 0;
      const maxRetries = 5;

      while (navigatorKey.currentState == null && retries < maxRetries) {
        final delay = Duration(milliseconds: 100 * (1 << retries));
        print(
            ' Navigator not ready, retry $retries/$maxRetries (waiting ${delay.inMilliseconds}ms)');
        await Future.delayed(delay);
        retries++;
      }

      if (navigatorKey.currentState == null) {
        print(' Navigator failed to initialize after $maxRetries retries');
        return null;
      }

      try {
        final currentContext = navigatorKey.currentContext;
        if (currentContext != null) {
          final currentRoute = ModalRoute.of(currentContext);
          final routeName = currentRoute?.settings.name ?? '';

          print(' Current route: $routeName');

          if (routeName == '/chat') {
            final currentArgs = currentRoute?.settings.arguments;
            if (currentArgs is ChatPageArguments &&
                currentArgs.peerId == peerId) {
              print('ℹ Already on this chat, ignoring navigation');
              return null;
            }
          }
        }
      } catch (e) {
        print(' Error checking current route: $e');
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
                )),
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

        print(' Navigation complete');
      } catch (e) {
        print(' Navigation failed: $e');
      }
    } else if (call.method == 'onBackPressed') {
      print(' Back pressed in bubble');

      if (navigatorKey.currentState != null &&
          navigatorKey.currentState!.canPop()) {
        navigatorKey.currentState!.pop();
      }
    }

    return null;
  });

  print(' Bubble chat channel setup complete');
}

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
        print(' Notification clicked: ${response.payload}');
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
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
    print(' Notifications initialized successfully');
  } catch (e) {
    print(' Notification initialization error: $e');
  }
}

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

    final googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
    );

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

        // Data providers
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

        // Theme provider
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(prefs: prefs),
        ),

        // Feature providers
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

        Provider<ChatBubbleService>(
          create: (_) => chatBubbleService,
        ),
        Provider<UnifiedBubbleService>(
          create: (_) => unifiedBubbleService,
        ),
        Provider<NotificationService>(
          create: (_) => notificationService,
        ),
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
            home: CallListener(
              child: BubbleManager(
                child: MiniChatOverlayManager(
                  child: AppInitializer(
                    notificationService: notificationService,
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

class AppInitializer extends StatefulWidget {
  final NotificationService notificationService;

  const AppInitializer({
    super.key,
    required this.notificationService,
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
    _logBubbleImplementation();
  }

  Future<void> _logBubbleImplementation() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final unifiedService = context.read<UnifiedBubbleService>();

    await Future.delayed(const Duration(seconds: 1));

    final impl = unifiedService.getImplementationInfo();
    print(' Bubble Implementation: $impl');

    if (unifiedService.currentImplementation ==
        BubbleImplementation.bubbleApi) {
      print(' Using modern Bubble API (Android 11+)');
    } else if (unifiedService.currentImplementation ==
        BubbleImplementation.windowManager) {
      print('⚠️ Using legacy WindowManager (Android < 11)');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print(' App lifecycle: $state');

    if (state == AppLifecycleState.paused) {
      print(' App going to background');
    } else if (state == AppLifecycleState.resumed) {
      print(' App resumed');
    }
  }

  Future<void> _startNotificationService() async {
    await Future.delayed(const Duration(milliseconds: 500));

    final auth = firebase_auth.FirebaseAuth.instance;
    auth.authStateChanges().listen((user) {
      if (user != null) {
        print(' User logged in, starting notification service');
        widget.notificationService.listenForNewMessages(user.uid);
      } else {
        print(' User logged out, stopping notification service');
        widget.notificationService.stopListening();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SplashPage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

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
  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserAvatar;

  @override
  void initState() {
    super.initState();
    _setupMiniChatChannel();
  }

  void _setupMiniChatChannel() {
    print('✅ Setting up MiniChat MethodChannel');

    _miniChatChannel.setMethodCallHandler((call) async {
      print(' MiniChat Channel received: ${call.method}');
      print(' Arguments: ${call.arguments}');

      if (call.method == 'navigateToMiniChat') {
        final peerId = call.arguments['peerId'] as String?;
        final peerNickname = call.arguments['peerNickname'] as String?;
        final peerAvatar = call.arguments['peerAvatar'] as String?;

        if (peerId == null || peerNickname == null) {
          print(' Missing required arguments for navigation');
          return null;
        }

        print(' Showing mini chat overlay for: $peerNickname');

        if (mounted) {
          _showMiniChatOverlay(peerId, peerNickname, peerAvatar ?? '');
        }
      } else if (call.method == 'minimize') {
        print('📦 Minimizing mini chat');
        _hideMiniChatOverlay();
      } else if (call.method == 'close') {
        print('❌ Closing mini chat');
        _hideMiniChatOverlay();
      }

      return null;
    });

    print('✅ MiniChat MethodChannel setup complete');
  }

  void _showMiniChatOverlay(String userId, String userName, String avatarUrl) {
    // Xóa overlay cũ nếu có
    _hideMiniChatOverlay();

    _currentUserId = userId;
    _currentUserName = userName;
    _currentUserAvatar = avatarUrl;

    print('📍 Creating MiniChatOverlay for: $userName');

    // FIX: Tạo overlay TRỰC TIẾP với MiniChatOverlayWidget bên trong
    _miniChatOverlay = OverlayEntry(
      builder: (context) => Material(
        // Sử dụng Material/Colors.transparent để đảm bảo MiniChatOverlayWidget không bị ảnh hưởng bởi theme/widget tree.
        color: Colors.transparent,
        child: Container(
          // FIX: Full screen overlay để chứa mini chat
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          alignment: Alignment.center,
          child: MiniChatOverlayWidget(
            userId: userId,
            userName: userName,
            avatarUrl: avatarUrl,
            onMinimize: () {
              print('📦 Minimize button pressed');
              _hideMiniChatOverlay();
              // Thông báo cho Native để hiển thị lại bubble
              _miniChatChannel.invokeMethod('minimize', {'userId': userId});
            },
            onClose: () {
              print('❌ Close button pressed');
              _hideMiniChatOverlay();
              // Thông báo cho Native để xóa bubble
              _miniChatChannel.invokeMethod('close', {'userId': userId});
            },
          ),
        ),
      ),
    );

    // Chèn vào Overlay
    if (mounted) {
      Overlay.of(context).insert(_miniChatOverlay!);
      print('✅ Mini chat overlay inserted into Flutter widget tree');
    }
  }

  void _hideMiniChatOverlay() {
    if (_miniChatOverlay != null) {
      try {
        _miniChatOverlay!.remove();
        _miniChatOverlay = null;
        _currentUserId = null;
        _currentUserName = null;
        _currentUserAvatar = null;
        print('✅ Mini chat overlay removed');
      } catch (e) {
        print('❌ Error removing overlay: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Trả về widget con (AppInitializer)
    return widget.child;
  }

  @override
  void dispose() {
    _hideMiniChatOverlay();
    super.dispose();
  }
}

// ===========================================
// MiniChatOverlayWidget - Draggable với bounds validation
// ===========================================

/// Widget hiển thị Mini Chat (ChatPage) có thể kéo thả, nằm trong Overlay.
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
  // Vị trí ban đầu của cửa sổ mini chat
  Offset _position = const Offset(20, 100);
  bool _isDragging = false;

  // FIX: Kích thước cố định, đủ nhỏ để vừa màn hình
  static const double _width = 340;
  static const double _height = 500;

  @override
  void initState() {
    super.initState();
    print('🏗️ MiniChatOverlayWidget initialized');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Center vị trí ban đầu
    final size = MediaQuery.of(context).size;
    final centerX = (size.width - _width) / 2;
    final centerY = (size.height - _height) / 2;

    // Đảm bảo chỉ set vị trí ban đầu một lần (nếu đang không drag)
    if (!_isDragging) {
      setState(() {
        _position = Offset(
          centerX.clamp(0, size.width - _width),
          centerY.clamp(0, size.height - _height),
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
      // Giới hạn vị trí trong màn hình
      left: _position.dx.clamp(0, maxX),
      top: _position.dy.clamp(0, maxY),
      child: GestureDetector(
        // Cho phép kéo thả trên toàn bộ MiniChatOverlayWidget
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        onPanEnd: (_) => setState(() => _isDragging = false),
        child: Material(
          elevation: _isDragging ? 16 : 8,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: _width,
            height: _height,
            decoration: BoxDecoration(
              // Sử dụng màu cố định để dễ nhận biết
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xff2196f3), // Primary Color
                width: 2,
              ),
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
                // Header với chức năng kéo thả và nút điều khiển
                _buildHeader(context),

                // Nội dung Chat (ChatPage)
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(14),
                    ),
                    // Tái sử dụng ChatPage
                    child: ChatPage(
                      arguments: ChatPageArguments(
                        peerId: widget.userId,
                        peerNickname: widget.userName,
                        peerAvatar: widget.avatarUrl,
                      ),
                      isMiniChat:
                          true, // Flag để ChatPage có thể điều chỉnh UI nếu cần
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

  Widget _buildHeader(BuildContext context) {
    // Sử dụng màu cố định để dễ nhận biết
    const primaryColor = Color(0xff2196f3);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          // Drag handle indicator
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Avatar
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

          // Name
          Expanded(
            child: Text(
              widget.userName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Minimize button
          IconButton(
            icon: const Icon(Icons.remove, color: Colors.white, size: 20),
            onPressed: widget.onMinimize,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          // Close button
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

// ========================================
// BONUS: Bubble Mode Detector
// ========================================

/// Helper class to detect if app is running in bubble mode
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

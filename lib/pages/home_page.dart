// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/utils/utils.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// ─── Top-level FCM callback ────────────────────────────────────────────────
@pragma('vm:entry-point')
void _onNotificationResponse(NotificationResponse response) {
  debugPrint(
      '🔔 Notification tapped: id=${response.id}, payload=${response.payload}');
}

// ════════════════════════════════════════════════════════════════════════════
// HOME PAGE
// ════════════════════════════════════════════════════════════════════════════

class HomePage extends StatefulWidget {
  final bool isWebSidebar;
  final Function(Map<String, dynamic>)? onChatSelected;

  const HomePage({super.key, this.isWebSidebar = false, this.onChatSelected});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Firebase ───────────────────────────────────────────────────────────────
  final _firebaseMessaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  // ── Controllers ────────────────────────────────────────────────────────────
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _btnClearController = StreamController<bool>.broadcast();
  final _searchDebouncer = Debouncer(milliseconds: 260);

  // ── Providers ──────────────────────────────────────────────────────────────
  late final AuthProvider _authProvider;
  late final HomeProvider _homeProvider;
  late final FriendProvider _friendProvider;
  late final ConversationProvider _conversationProvider;
  late final String _currentUserId;

  // ── State ──────────────────────────────────────────────────────────────────
  String _textSearch = '';
  bool _isSearchFocused = false;
  bool _isLoading = false;
  bool _showScrollToTop = false;
  int _activeFilterIndex = 0;
  int _searchLimit = 20;
  bool _isLoadingMore = false;
  bool _isFabExpanded = false;
  static const int _limitIncrement = 20;
  static const List<String> _filterLabels = ['All', 'Unread', 'Groups'];

  // ── Friends / stories ──────────────────────────────────────────────────────
  List<String> _myFriendIds = [];
  StreamSubscription<QuerySnapshot>? _friendIdsSub;

  // ── Stable streams ─────────────────────────────────────────────────────────
  Stream<List<QueryDocumentSnapshot>>? _conversationsStream;
  late final Stream<QuerySnapshot> _friendRequestsStream;

  // ── Profile cache ──────────────────────────────────────────────────────────
  final Map<String, UserChat> _userProfileCache = {};
  final Map<String, Group> _groupCache = {};
  bool _isPrefetching = false;
  Timer? _prefetchDebouncer;

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _fabAnimCtrl;
  late Animation<double> _fabScaleAnim;
  late AnimationController _filterAnimCtrl;
  late Animation<double> _filterAnim;
  late AnimationController _headerAnimCtrl;
  late Animation<double> _headerFadeAnim;
  late Animation<Offset> _headerSlideAnim;
  late AnimationController _fabExpandCtrl;
  late Animation<double> _fabExpandAnim;

  late final List<MenuSetting> _menus;

  // ════════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authProvider = context.read<AuthProvider>();
    _homeProvider = context.read<HomeProvider>();

    if (_authProvider.userFirebaseId?.isNotEmpty != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _redirectToLogin());
      return;
    }
    _currentUserId = _authProvider.userFirebaseId!;

    _friendProvider =
        FriendProvider(firebaseFirestore: _homeProvider.firebaseFirestore);
    _conversationProvider = ConversationProvider(
        firebaseFirestore: _homeProvider.firebaseFirestore);

    _menus = [
      const MenuSetting(title: 'Friends', icon: Icons.people_outline_rounded),
      const MenuSetting(title: 'My Status', icon: Icons.auto_stories_rounded),
      const MenuSetting(title: 'Call History', icon: Icons.call_outlined),
      const MenuSetting(title: 'My QR Code', icon: Icons.qr_code_2_rounded),
      const MenuSetting(title: 'Create Group', icon: Icons.group_add_outlined),
      const MenuSetting(title: 'Bubble Chat', icon: Icons.bubble_chart_rounded),
      const MenuSetting(title: 'Theme', icon: Icons.palette_outlined),
      const MenuSetting(title: 'Settings', icon: Icons.settings_outlined),
      const MenuSetting(title: 'Log out', icon: Icons.logout_rounded),
    ];

    _updateConversationsStream();
    _friendRequestsStream = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathFriendRequestCollection)
        .where(FirestoreConstants.receiverId, isEqualTo: _currentUserId)
        .where(FirestoreConstants.status, isEqualTo: 'pending')
        .snapshots();

    _initAnimations();
    _registerNotification();
    _configLocalNotification();
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _listenToFriendIds();
    _initE2EE();

    BubbleLifecycleObserver.instance.attach();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await FcmTokenManager.initialize(
        onTokenAvailable: (token) async {
          if (!mounted) return;
          try {
            await _homeProvider.updateDataFirestore(
              FirestoreConstants.pathUserCollection,
              _currentUserId,
              {'pushToken': token, 'fcmToken': token},
            );
            debugPrint('📱 FCM token saved: ${token.substring(0, 20)}…');
          } catch (e) {
            debugPrint('⚠️ FCM token save: $e');
          }
        },
      );
    });
  }

  // ── Stable stream management ──────────────────────────────────────────────

  void _updateConversationsStream() {
    switch (_activeFilterIndex) {
      case 1:
        _conversationsStream =
            _conversationProvider.getUnreadConversations(_currentUserId);
      case 2:
        _conversationsStream = _conversationProvider
            .getConversationsWithPinned(_currentUserId)
            .map((docs) => docs
                .where((d) =>
                    (d.data() as Map<String, dynamic>)['isGroup'] == true)
                .toList());
      default:
        _conversationsStream =
            _conversationProvider.getConversationsWithPinned(_currentUserId);
    }
  }

  // ── Prefetch ──────────────────────────────────────────────────────────────

  void _schedulePrefetch(List<QueryDocumentSnapshot> docs) {
    _prefetchDebouncer?.cancel();
    _prefetchDebouncer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _prefetchConversationPeers(docs);
    });
  }

  Future<void> _prefetchConversationPeers(
      List<QueryDocumentSnapshot> docs) async {
    if (_isPrefetching) return;
    _isPrefetching = true;
    try {
      final missingUserIds = <String>[];
      final missingGroupIds = <String>[];
      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final isGroup = data['isGroup'] as bool? ?? false;
        if (isGroup) {
          if (!_groupCache.containsKey(doc.id)) missingGroupIds.add(doc.id);
        } else {
          final participants =
              List<String>.from(data['participants'] as List? ?? []);
          final otherId = participants.firstWhere((id) => id != _currentUserId,
              orElse: () => '');
          if (otherId.isNotEmpty && !_userProfileCache.containsKey(otherId)) {
            missingUserIds.add(otherId);
          }
        }
      }
      if (missingUserIds.isEmpty && missingGroupIds.isEmpty) return;
      final newUsers = missingUserIds.isNotEmpty
          ? await _homeProvider.batchFetchUserChats(missingUserIds)
          : <String, UserChat>{};
      final newGroups = missingGroupIds.isNotEmpty
          ? await _homeProvider.batchFetchGroups(missingGroupIds)
          : <String, Group>{};
      if (!mounted) return;
      if (newUsers.isEmpty && newGroups.isEmpty) return;
      setState(() {
        _userProfileCache.addAll(newUsers);
        _groupCache.addAll(newGroups);
      });
    } catch (e) {
      debugPrint('[HomePage] prefetch error: $e');
    } finally {
      _isPrefetching = false;
    }
  }

  // ── Animations ─────────────────────────────────────────────────────────────

  void _initAnimations() {
    _fabAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fabScaleAnim =
        CurvedAnimation(parent: _fabAnimCtrl, curve: Curves.elasticOut);

    _filterAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _filterAnim =
        CurvedAnimation(parent: _filterAnimCtrl, curve: Curves.easeOut);

    _headerAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _headerFadeAnim =
        CurvedAnimation(parent: _headerAnimCtrl, curve: Curves.easeOut);
    _headerSlideAnim =
        Tween<Offset>(begin: const Offset(0, -0.25), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _headerAnimCtrl, curve: Curves.easeOutCubic));

    _fabExpandCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _fabExpandAnim =
        CurvedAnimation(parent: _fabExpandCtrl, curve: Curves.easeOutBack);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _headerAnimCtrl.forward();
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _fabAnimCtrl.forward();
      });
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _filterAnimCtrl.forward();
      });
    });
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    BubbleLifecycleObserver.instance.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      if (_authProvider.userFirebaseId?.isNotEmpty == true) {
        _homeProvider.updateDataFirestore(
          FirestoreConstants.pathUserCollection,
          _currentUserId,
          {'isOnline': 'true'},
        );
      }
    } else if (state == AppLifecycleState.paused) {
      if (_authProvider.userFirebaseId?.isNotEmpty == true) {
        _homeProvider.updateDataFirestore(
          FirestoreConstants.pathUserCollection,
          _currentUserId,
          {'isOnline': 'false'},
        );
      }
    }
  }

  // ── E2EE ───────────────────────────────────────────────────────────────────

  Future<void> _initE2EE() async {
    await E2EEService().generateAndStoreUserKeys(_currentUserId);
  }

  // ── FCM ────────────────────────────────────────────────────────────────────

  void _registerNotification() {
    _firebaseMessaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null) {
        _showLocalNotification(message.notification!);
      }
    });

    _firebaseMessaging.getToken().catchError((err) {
      Fluttertoast.showToast(msg: err.message.toString());
    });
  }

  void _configLocalNotification() {
    const androidSettings = AndroidInitializationSettings('app_icon');
    const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false);
    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open notification');
    _localNotifications.initialize(
      const InitializationSettings(
          android: androidSettings,
          iOS: darwinSettings,
          macOS: darwinSettings,
          linux: linuxSettings),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onNotificationResponse,
    );
  }

  Future<void> _showLocalNotification(RemoteNotification n) async {
    final androidDetails = AndroidNotificationDetails(
      Platform.isAndroid
          ? 'com.dfa.flutterchatdemo'
          : 'com.duytq.flutterchatdemo',
      'Flutter chat demo',
      channelDescription: 'Chat message notifications',
      playSound: true,
      enableVibration: true,
      importance: Importance.max,
      priority: Priority.high,
      ticker: n.title,
      icon: 'app_icon',
      largeIcon: const DrawableResourceAndroidBitmap('app_icon'),
      styleInformation:
          BigTextStyleInformation(n.body ?? '', contentTitle: n.title),
    );
    const darwinDetails = DarwinNotificationDetails(
        presentAlert: true, presentBadge: true, presentSound: true);
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 & 0x7FFFFFFF,
      n.title,
      n.body,
      NotificationDetails(
          android: androidDetails, iOS: darwinDetails, macOS: darwinDetails),
      payload: n.title,
    );
  }

  // ── Friends stream ─────────────────────────────────────────────────────────

  void _listenToFriendIds() {
    final fs = _homeProvider.firebaseFirestore
        .collection(FirestoreConstants.pathFriendshipCollection);
    _friendIdsSub = fs
        .where(FirestoreConstants.userId1, isEqualTo: _currentUserId)
        .snapshots()
        .listen((snap1) async {
      final ids = <String>{};
      for (final d in snap1.docs) {
        ids.add(d[FirestoreConstants.userId2] as String);
      }
      final snap2 = await fs
          .where(FirestoreConstants.userId2, isEqualTo: _currentUserId)
          .get();
      for (final d in snap2.docs) {
        ids.add(d[FirestoreConstants.userId1] as String);
      }
      if (mounted) setState(() => _myFriendIds = ids.take(9).toList());
    });
  }

  // ── Scroll ─────────────────────────────────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    if (_textSearch.isNotEmpty &&
        !_isLoadingMore &&
        pos.pixels >= pos.maxScrollExtent - 300) {
      _isLoadingMore = true;
      setState(() => _searchLimit += _limitIncrement);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _isLoadingMore = false;
      });
    }
    final show = pos.pixels > 320;
    if (show != _showScrollToTop) setState(() => _showScrollToTop = show);
  }

  void _scrollToTop() {
    HapticFeedback.lightImpact();
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic);
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
  }

  // ── FAB expand ────────────────────────────────────────────────────────────

  void _toggleFab() {
    HapticFeedback.mediumImpact();
    setState(() => _isFabExpanded = !_isFabExpanded);
    if (_isFabExpanded) {
      _fabExpandCtrl.forward();
    } else {
      _fabExpandCtrl.reverse();
    }
  }

  void _closeFab() {
    if (_isFabExpanded) {
      setState(() => _isFabExpanded = false);
      _fabExpandCtrl.reverse();
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _redirectToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginPage()), (_) => false);
  }

  void _onMenuSelected(MenuSetting choice) {
    final prefs = _authProvider.prefs;
    switch (choice.title) {
      case 'Log out':
        _handleSignOut();
      case 'Friends':
        _push(FriendsPage());
      case 'Call History':
        _push(CallHistoryPage(currentUserId: _currentUserId));
      case 'My QR Code':
        _push(const MyQRCodePage());
      case 'Create Group':
        _push(CreateGroupPage());
      case 'Bubble Chat':
        _push(const BubbleSettingsPage());
      case 'Theme':
        _push(const ThemeSettingsPage());
      case 'My Status':
        _push(MyStoriesPage(
          userId: _currentUserId,
          userName: prefs.getString(FirestoreConstants.nickname) ?? '',
          userPhotoUrl: prefs.getString(FirestoreConstants.photoUrl) ?? '',
        ));
      default:
        _push(const SettingsPage());
    }
  }

  Future<void> _handleSignOut() async {
    await _authProvider.handleSignOut();
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginPage()), (_) => false);
  }

  void _scanQRCode() async {
    _closeFab();
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const QRScannerPage()));
    if (result is String) {
      setState(() => _isLoading = true);
      final userDoc = await _homeProvider.searchByQRCode(result);
      if (mounted) setState(() => _isLoading = false);
      if (!mounted) return;
      if (userDoc != null) {
        final userChat = UserChat.fromDocument(userDoc);
        if (userChat.id == _currentUserId) {
          Fluttertoast.showToast(msg: 'This is your own QR code!');
        } else {
          _push(UserProfilePage(userChat: userChat));
        }
      } else {
        Fluttertoast.showToast(msg: 'User not found');
      }
    }
  }

  void _push(Widget page) => Navigator.push(context, _slideRoute(page));

  // ── Conversation options ───────────────────────────────────────────────────

  void _showConversationOptions(Conversation conversation) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ConversationOptionsDialog(
        isPinned: conversation.isPinned,
        isMuted: conversation.isMuted,
        isArchived: conversation.archivedBy.contains(_currentUserId),
        onPin: () => _conversationProvider.togglePinConversation(
            conversation.id, conversation.isPinned),
        onMute: () => _conversationProvider.toggleMuteConversation(
            conversation.id, conversation.isMuted),
        onClearHistory: () =>
            _conversationProvider.clearConversationHistory(conversation.id),
        onMarkAsRead: () =>
            _conversationProvider.markAsRead(conversation.id, _currentUserId),
        onArchive: () => _conversationProvider.toggleArchiveConversation(
            conversation.id,
            _currentUserId,
            !conversation.archivedBy.contains(_currentUserId)),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _lastMessagePreview(String msg, int? type) {
    if (type == TypeMessage.image) return '📷 Photo';
    if (type == TypeMessage.sticker) return '😊 Sticker';
    if (type == TypeMessage.video) return '🎥 Video';
    if (type == TypeMessage.voice) return '🎵 Audio';
    if (type == TypeMessage.document) return '📄 Document';
    if (msg.isEmpty) return 'Start a conversation';
    return msg.length > 44 ? '${msg.substring(0, 44)}…' : msg;
  }

  String _timeAgo(String timestamp) {
    try {
      final t = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
      final diff = DateTime.now().difference(t);
      if (diff.inDays > 6) return DateFormat('MMM d').format(t);
      if (diff.inDays > 0) return DateFormat('EEE').format(t);
      if (diff.inHours > 0) return '${diff.inHours}h';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m';
      return 'now';
    } catch (_) {
      return '';
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  String _userName() =>
      _authProvider.prefs.getString(FirestoreConstants.nickname) ?? 'there';

  String _userPhotoUrl() =>
      _authProvider.prefs.getString(FirestoreConstants.photoUrl) ?? '';

  PageRoute _slideRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (_, a, __) => page,
      transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child),
      transitionDuration: const Duration(milliseconds: 280));

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    BubbleLifecycleObserver.instance.detach();
    FcmTokenManager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _prefetchDebouncer?.cancel();
    _fabAnimCtrl.dispose();
    _filterAnimCtrl.dispose();
    _headerAnimCtrl.dispose();
    _fabExpandCtrl.dispose();
    _searchController.dispose();
    _searchFocusNode
      ..removeListener(_onSearchFocusChanged)
      ..dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _btnClearController.close();
    _friendIdsSub?.cancel();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storyProvider = context.read<StoryProvider>();
    final bgColor = isDark ? const Color(0xFF080810) : const Color(0xFFF0F2F8);
    final surfaceColor = isDark ? const Color(0xFF0E0E18) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        onTap: _closeFab,
        behavior: HitTestBehavior.translucent,
        child: Stack(children: [
          // ── Background mesh gradient ──────────────────────────────────────
          Positioned.fill(
            child: _MeshBackground(isDark: isDark),
          ),

          SafeArea(
            child: Column(children: [
              // ── Dynamic Header ────────────────────────────────────────────
              SlideTransition(
                  position: _headerSlideAnim,
                  child: FadeTransition(
                      opacity: _headerFadeAnim,
                      child: _buildHeader(isDark, surfaceColor))),

              // ── Universal Search ──────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                color: surfaceColor,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _buildSearchBar(isDark),
              ),

              // ── Quick Actions ─────────────────────────────────────────────
              if (_textSearch.isEmpty)
                FadeTransition(
                    opacity: _filterAnim,
                    child: _buildQuickActions(isDark, surfaceColor)),

              // ── Filter Segmented Control ──────────────────────────────────
              if (_textSearch.isEmpty)
                FadeTransition(
                    opacity: _filterAnim, child: _buildFilterSegment(isDark)),

              // ── Body ──────────────────────────────────────────────────────
              Expanded(
                  child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  if (_textSearch.isEmpty) ...[
                    // Stories + Online combined
                    SliverToBoxAdapter(
                        child: _buildSocialSection(storyProvider, isDark)),
                    // Smart Priority / Pinned section
                    SliverToBoxAdapter(
                        child: _buildSmartPrioritySection(isDark)),
                    // Section label
                    SliverToBoxAdapter(child: _buildSectionLabel(isDark)),
                  ],
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverToBoxAdapter(
                        child: _buildListCard(
                            isDark, surfaceColor, storyProvider)),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 160)),
                ],
              )),
            ]),
          ),

          // ── Loading overlay ───────────────────────────────────────────────
          if (_isLoading) const LoadingView(),

          // ── Expandable FAB backdrop ───────────────────────────────────────
          if (_isFabExpanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeFab,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 280),
                  opacity: _isFabExpanded ? 1 : 0,
                  child: Container(color: Colors.black.withOpacity(0.48)),
                ),
              ),
            ),

          // ── Bubble Dock ───────────────────────────────────────────────────
          _BubbleDock(
            currentUserId: _currentUserId,
            isDark: isDark,
            onBubbleTap: (bubble) {
              final ctrl = BubbleManager.of(context);
              ctrl?.showMiniChat(
                  userId: bubble.userId,
                  userName: bubble.userName,
                  avatarUrl: bubble.avatarUrl);
            },
            onBubbleLongPress: (bubble) async {
              final ctrl = BubbleManager.of(context);
              await ctrl?.hideBubble(bubble.userId);
              if (mounted) {
                Fluttertoast.showToast(
                    msg: '💬 Bubble off — ${bubble.userName}',
                    backgroundColor: Colors.grey.shade700,
                    textColor: Colors.white);
              }
            },
            onSettingsTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BubbleSettingsPage())),
          ),

          // ── Expandable FAB ────────────────────────────────────────────────
          _buildExpandableFab(isDark),

          // ── Scroll-to-top button ──────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            bottom: _showScrollToTop ? 148 : -60,
            right: 20,
            child: _ScrollToTopButton(onTap: _scrollToTop),
          ),
        ]),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark, Color surfaceColor) {
    final photoUrl = _userPhotoUrl();
    final name = _userName();

    return Container(
      color: surfaceColor,
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Text('Messages',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.0,
                          color:
                              isDark ? Colors.white : const Color(0xFF0D1117))),
                  const SizedBox(width: 8),
                  _UnreadBadge(userId: _currentUserId, isDark: isDark),
                ]),
                const SizedBox(height: 2),
                Text('${_greeting()}, $name',
                    style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1)),
              ]),
        ),
        // Notification bell
        StreamBuilder<QuerySnapshot>(
          stream: _friendRequestsStream,
          builder: (_, snap) {
            final count = snap.hasData ? snap.data!.docs.length : 0;
            return Stack(clipBehavior: Clip.none, children: [
              _IconBtn(
                  icon: Icons.notifications_outlined,
                  isDark: isDark,
                  onTap: () => _push(const NotificationsPage())),
              if (count > 0)
                Positioned(
                    right: 6,
                    top: 6,
                    child: _AnimatedBadge(count: count, isDark: isDark)),
            ]);
          },
        ),
        const SizedBox(width: 6),
        // Archive shortcut
        _IconBtn(
            icon: Icons.archive_outlined,
            isDark: isDark,
            tooltip: 'Archived',
            onTap: () => _push(const ArchivedChatsPage())),
        const SizedBox(width: 6),
        // User avatar / profile
        GestureDetector(
          onTap: () => _push(const SettingsPage()),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [
                  ColorConstants.primaryColor,
                  const Color(0xFF2196F3)
                ]),
                boxShadow: [
                  BoxShadow(
                      color: ColorConstants.primaryColor.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]),
            child: ClipOval(
                child: photoUrl.isNotEmpty
                    ? Image.network(photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                            child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15))))
                    : Center(
                        child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15)))),
          ),
        ),
        const SizedBox(width: 6),
        // Menu
        _buildMenuButton(isDark),
      ]),
    );
  }

  // ── Universal Search ───────────────────────────────────────────────────────

  Widget _buildSearchBar(bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2A) : const Color(0xFFEEF0F7),
        borderRadius: BorderRadius.circular(16),
        border: _isSearchFocused
            ? Border.all(
                color: ColorConstants.primaryColor.withOpacity(0.6), width: 1.5)
            : Border.all(color: Colors.transparent),
        boxShadow: _isSearchFocused
            ? [
                BoxShadow(
                    color: ColorConstants.primaryColor.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 4))
              ]
            : [],
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.search_rounded,
                key: ValueKey(_isSearchFocused),
                color: _isSearchFocused
                    ? ColorConstants.primaryColor
                    : (isDark ? Colors.white38 : Colors.grey.shade500),
                size: 20)),
        const SizedBox(width: 10),
        Expanded(
            child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: TextStyle(
              fontSize: 14.5,
              color: isDark ? Colors.white : const Color(0xFF0D1117),
              fontWeight: FontWeight.w500),
          decoration: InputDecoration(
              hintText: 'Search messages, people, groups…',
              hintStyle: TextStyle(
                  color: isDark ? Colors.white30 : Colors.grey.shade400,
                  fontSize: 14,
                  fontWeight: FontWeight.w400),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero),
          onChanged: (value) {
            _searchDebouncer.run(() {
              if (!mounted) return;
              _btnClearController.add(value.isNotEmpty);
              setState(() {
                _textSearch = value;
                _searchLimit = 20;
              });
            });
          },
        )),
        StreamBuilder<bool>(
            stream: _btnClearController.stream,
            builder: (_, snap) {
              if (snap.data != true) return const SizedBox(width: 14);
              return GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    _btnClearController.add(false);
                    setState(() {
                      _textSearch = '';
                      _searchLimit = 20;
                    });
                    _searchFocusNode.unfocus();
                  },
                  child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.12)
                              : Colors.grey.withOpacity(0.25),
                          shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded,
                          size: 13,
                          color:
                              isDark ? Colors.white60 : Colors.grey.shade600)));
            }),
      ]),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────

  Widget _buildQuickActions(bool isDark, Color surfaceColor) {
    final actions = [
      _QuickAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'New Chat',
          color: const Color(0xFF4F8EFF),
          onTap: () => _push(FriendsPage())),
      _QuickAction(
          icon: Icons.qr_code_scanner_rounded,
          label: 'Scan QR',
          color: const Color(0xFF34C759),
          onTap: _scanQRCode),
      _QuickAction(
          icon: Icons.group_add_outlined,
          label: 'New Group',
          color: const Color(0xFFFF9F0A),
          onTap: () => _push(CreateGroupPage())),
      _QuickAction(
          icon: Icons.auto_awesome_rounded,
          label: 'AI Chat',
          color: const Color(0xFF7B61FF),
          onTap: () => _push(ChatPage(
              arguments: ChatPageArguments(
                  peerId: AppConstants.aiAssistantId,
                  peerAvatar: AppConstants.aiAssistantAvatar,
                  peerNickname: AppConstants.aiAssistantName)))),
      _QuickAction(
          icon: Icons.archive_outlined,
          label: 'Archived',
          color: const Color(0xFFFF6B6B),
          onTap: () => _push(const ArchivedChatsPage())),
    ];

    return Container(
      color: surfaceColor,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 14),
      child: SizedBox(
        height: 76,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const BouncingScrollPhysics(),
          itemCount: actions.length,
          itemBuilder: (_, i) =>
              _QuickActionPill(action: actions[i], isDark: isDark, index: i),
        ),
      ),
    );
  }

  // ── Filter Segmented Control ───────────────────────────────────────────────

  Widget _buildFilterSegment(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0E0E18) : const Color(0xFFF0F2F8),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: _SegmentedControl(
        labels: _filterLabels,
        activeIndex: _activeFilterIndex,
        isDark: isDark,
        onChanged: (i) {
          if (_activeFilterIndex == i) return;
          HapticFeedback.selectionClick();
          setState(() {
            _activeFilterIndex = i;
            _updateConversationsStream();
          });
        },
      ),
    );
  }

  // ── Social Section (Stories + Online) ─────────────────────────────────────

  Widget _buildSocialSection(StoryProvider provider, bool isDark) {
    final cardBg = isDark ? const Color(0xFF0E0E18) : Colors.white;
    return Container(
      color: cardBg,
      child: Column(children: [
        // Stories row
        StreamBuilder<List<UserStories>>(
          stream: provider.getStoriesStream(
              currentUserId: _currentUserId, friendIds: _myFriendIds),
          builder: (ctx, snap) {
            final stories = snap.data ?? [];
            return StoriesBar(
                storiesList: stories,
                currentUserId: _currentUserId,
                onAddStory: _openStoryCreator,
                onViewStories: (userStories) {
                  final others =
                      stories.where((s) => s.userId != _currentUserId).toList();
                  final idx =
                      others.indexWhere((s) => s.userId == userStories.userId);
                  _push(StoryViewerPage(
                      allUserStories: others.isNotEmpty ? others : stories,
                      initialUserIndex: idx < 0 ? 0 : idx,
                      currentUserId: _currentUserId,
                      currentUserName: _authProvider.prefs
                              .getString(FirestoreConstants.nickname) ??
                          '',
                      currentUserPhotoUrl: _authProvider.prefs
                              .getString(FirestoreConstants.photoUrl) ??
                          ''));
                });
          },
        ),
        // Online friends compact row
        _buildOnlineFriendsCompact(isDark),
        Divider(
            height: 1,
            thickness: 0.5,
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : const Color(0xFFEEEEF4)),
      ]),
    );
  }

  Widget _buildOnlineFriendsCompact(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(children: [
        Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                color: Color(0xFF34C759), shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('Online',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.grey.shade600)),
        const SizedBox(width: 8),
        Expanded(
          child: OnlineFriendsBar(currentUserId: _currentUserId),
        ),
        GestureDetector(
          onTap: () => _push(FriendsPage()),
          child: Text('View all',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ColorConstants.primaryColor)),
        ),
      ]),
    );
  }

  void _openStoryCreator() {
    final prefs = _authProvider.prefs;
    _push(StoryCreatorPage(
      userId: _currentUserId,
      userName: prefs.getString(FirestoreConstants.nickname) ?? '',
      userPhotoUrl: prefs.getString(FirestoreConstants.photoUrl) ?? '',
    ));
  }

  // ── Smart Priority Section ─────────────────────────────────────────────────

  Widget _buildSmartPrioritySection(bool isDark) {
    if (_conversationsStream == null) return const SizedBox.shrink();
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _conversationsStream,
      builder: (_, snap) {
        final docs = snap.data ?? [];
        final pinned = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return (data['isPinned'] as bool? ?? false) &&
              !(List<String>.from(data['archivedBy'] as List? ?? []))
                  .contains(_currentUserId);
        }).toList();

        if (pinned.isEmpty) return const SizedBox.shrink();

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Text('Pinned',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                    letterSpacing: 0.5)),
          ),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const BouncingScrollPhysics(),
              itemCount: pinned.length,
              itemBuilder: (_, i) => _buildPriorityCard(pinned[i], isDark),
            ),
          ),
          const SizedBox(height: 8),
        ]);
      },
    );
  }

  Widget _buildPriorityCard(QueryDocumentSnapshot doc, bool isDark) {
    final conversation = Conversation.fromDocument(doc);
    String name = '';
    String photoUrl = '';
    VoidCallback onTap = () {};

    if (conversation.isGroup) {
      final group = _groupCache[conversation.id];
      if (group == null) return const SizedBox(width: 80);
      name = group.groupName;
      photoUrl = group.groupPhotoUrl;
      onTap = () => _push(GroupChatPage(group: group));
    } else {
      final otherId = conversation.participants
          .firstWhere((id) => id != _currentUserId, orElse: () => '');
      if (otherId.isEmpty) return const SizedBox(width: 80);
      final userChat = _userProfileCache[otherId];
      if (userChat == null) return const SizedBox(width: 80);
      name = userChat.nickname;
      photoUrl = userChat.photoUrl;
      onTap = () => _push(ChatPage(
          arguments: ChatPageArguments(
              peerId: userChat.id,
              peerAvatar: userChat.photoUrl,
              peerNickname: userChat.nickname)));
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [
                    ColorConstants.primaryColor.withOpacity(0.3),
                    const Color(0xFF2196F3).withOpacity(0.3),
                  ]),
                  border: Border.all(
                      color: ColorConstants.primaryColor.withOpacity(0.6),
                      width: 2)),
              child: ClipOval(
                  child: photoUrl.isNotEmpty
                      ? Image.network(photoUrl, fit: BoxFit.cover)
                      : Center(
                          child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                  color: ColorConstants.primaryColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18)))),
            ),
            Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                        color: ColorConstants.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color:
                                isDark ? const Color(0xFF080810) : Colors.white,
                            width: 2)),
                    child: const Icon(Icons.push_pin_rounded,
                        color: Colors.white, size: 8))),
          ]),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF374151))),
        ]),
      ),
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────

  Widget _buildSectionLabel(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(
            _activeFilterIndex == 0
                ? 'Recent Chats'
                : '${_filterLabels[_activeFilterIndex]} Chats',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white38 : Colors.grey.shade500,
                letterSpacing: 0.5)),
        GestureDetector(
            onTap: () => _push(const ArchivedChatsPage()),
            child: Row(children: [
              Icon(Icons.archive_outlined,
                  size: 13, color: ColorConstants.primaryColor),
              const SizedBox(width: 4),
              Text('Archived',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ColorConstants.primaryColor)),
            ])),
      ]),
    );
  }

  // ── Conversation list card ─────────────────────────────────────────────────

  Widget _buildListCard(
      bool isDark, Color surfaceColor, StoryProvider storyProvider) {
    return Container(
      decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                blurRadius: 32,
                offset: const Offset(0, 8))
          ]),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: _textSearch.isEmpty
              ? _buildConversationList(isDark)
              : _buildSearchResults(isDark)),
    );
  }

  // ── Conversation list ──────────────────────────────────────────────────────

  Widget _buildConversationList(bool isDark) {
    if (_conversationsStream == null) return _buildSkeleton(isDark);
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _conversationsStream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return _buildSkeleton(isDark);
        }
        final allDocs = snap.data ?? [];
        final activeDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final archivedBy =
              List<String>.from(data['archivedBy'] as List? ?? []);
          return !archivedBy.contains(_currentUserId);
        }).toList();
        _schedulePrefetch(activeDocs);
        if (activeDocs.isEmpty) {
          return Column(children: [
            _buildAiAssistantCard(isDark),
            _buildEmptyState(isDark),
          ]);
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: activeDocs.length + 1,
          separatorBuilder: (_, i) => i == 0
              ? const SizedBox.shrink()
              : Divider(
                  height: 1,
                  indent: 80,
                  endIndent: 16,
                  color: isDark
                      ? Colors.white.withOpacity(0.04)
                      : const Color(0xFFF0F2F8)),
          itemBuilder: (_, i) {
            if (i == 0) return _buildAiAssistantCard(isDark);
            return _buildConversationItem(activeDocs[i - 1], isDark);
          },
        );
      },
    );
  }

  // ── AI Assistant Card ──────────────────────────────────────────────────────

  Widget _buildAiAssistantCard(bool isDark) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        final args = {
          'peerId': AppConstants.aiAssistantId,
          'peerAvatar': AppConstants.aiAssistantAvatar,
          'peerNickname': AppConstants.aiAssistantName
        };
        if (widget.isWebSidebar && widget.onChatSelected != null) {
          widget.onChatSelected!(args);
        } else {
          _push(ChatPage(
              arguments: ChatPageArguments(
                  peerId: AppConstants.aiAssistantId,
                  peerAvatar: AppConstants.aiAssistantAvatar,
                  peerNickname: AppConstants.aiAssistantName)));
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1A1040), const Color(0xFF0D1A3A)]
                  : [const Color(0xFFF0EBFF), const Color(0xFFE8F0FE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isDark
                  ? const Color(0xFF4A3080).withOpacity(0.6)
                  : const Color(0xFF7B61FF).withOpacity(0.2),
              width: 1),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF7B61FF).withOpacity(isDark ? 0.2 : 0.1),
                blurRadius: 20,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          // AI orb
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [Color(0xFF7B61FF), Color(0xFF4285F4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(AppConstants.aiAssistantName,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color:
                            isDark ? Colors.white : const Color(0xFF1A0040))),
                const SizedBox(width: 8),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF7B61FF), Color(0xFF4285F4)]),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('AI',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5))),
              ]),
              const SizedBox(height: 3),
              Text('Powered by Gemini · Ask me anything',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? Colors.white54
                          : const Color(0xFF7B61FF).withOpacity(0.7),
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: const Color(0xFF7B61FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF7B61FF), size: 18),
          ),
        ]),
      ),
    );
  }

  Widget _buildConversationItem(DocumentSnapshot doc, bool isDark) {
    final conversation = Conversation.fromDocument(doc);

    if (conversation.isGroup) {
      final group = _groupCache[conversation.id];
      if (group == null) return _SkeletonTile(isDark: isDark);
      return _ConversationTile(
        id: conversation.id,
        name: group.groupName,
        photoUrl: group.groupPhotoUrl,
        lastMessage: _lastMessagePreview(
            conversation.lastMessage ?? '', conversation.lastMessageType ?? 0),
        timeLabel: _timeAgo(conversation.lastMessageTime ?? ''),
        isPinned: conversation.isPinned,
        isMuted: conversation.isMuted,
        isGroup: true,
        isDark: isDark,
        unreadCount: conversation.unreadCount ?? 0,
        onTap: () {
          HapticFeedback.lightImpact();
          if (widget.isWebSidebar && widget.onChatSelected != null) {
            widget.onChatSelected!({
              'peerId': group.id,
              'peerAvatar': group.groupPhotoUrl,
              'peerNickname': group.groupName,
              'isGroup': true
            });
          } else {
            _push(GroupChatPage(group: group));
          }
        },
        onLongPress: () => _showConversationOptions(conversation),
      );
    }

    final otherId = conversation.participants
        .firstWhere((id) => id != _currentUserId, orElse: () => '');
    if (otherId.isEmpty) return const SizedBox.shrink();
    final userChat = _userProfileCache[otherId];
    if (userChat == null) return _SkeletonTile(isDark: isDark);
    return _ConversationTile(
      id: conversation.id,
      name: userChat.nickname,
      photoUrl: userChat.photoUrl,
      lastMessage: _lastMessagePreview(
          conversation.lastMessage ?? '', conversation.lastMessageType ?? 0),
      timeLabel: _timeAgo(conversation.lastMessageTime ?? ''),
      isPinned: conversation.isPinned,
      isMuted: conversation.isMuted,
      isGroup: false,
      isDark: isDark,
      onlineUserId: otherId,
      unreadCount: conversation.unreadCount ?? 0,
      onTap: () {
        HapticFeedback.lightImpact();
        if (widget.isWebSidebar && widget.onChatSelected != null) {
          widget.onChatSelected!({
            'peerId': userChat.id,
            'peerAvatar': userChat.photoUrl,
            'peerNickname': userChat.nickname
          });
        } else {
          _push(ChatPage(
              arguments: ChatPageArguments(
                  peerId: userChat.id,
                  peerAvatar: userChat.photoUrl,
                  peerNickname: userChat.nickname)));
        }
      },
      onLongPress: () => _showConversationOptions(conversation),
    );
  }

  // ── Search results ─────────────────────────────────────────────────────────

  Widget _buildSearchResults(bool isDark) {
    final query = _textSearch.trim();
    final isPhone = RegExp(r'^[+\d][\d\s-]*$').hasMatch(query);
    final stream = isPhone
        ? _homeProvider.firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .where(FirestoreConstants.phoneNumber, isEqualTo: query)
            .limit(_searchLimit)
            .snapshots()
        : _homeProvider.firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .where(FirestoreConstants.nickname, isGreaterThanOrEqualTo: query)
            .where(FirestoreConstants.nickname,
                isLessThanOrEqualTo: '$query\uf8ff')
            .limit(_searchLimit)
            .snapshots();
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (_, snap) {
        if (!snap.hasData) return _buildSkeleton(isDark);
        final docs =
            snap.data!.docs.where((d) => d.id != _currentUserId).toList();
        if (docs.isEmpty) return _buildSearchEmpty(isDark);
        return Column(children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 76,
                endIndent: 16,
                color: isDark
                    ? Colors.white.withOpacity(0.04)
                    : const Color(0xFFF0F2F8)),
            itemBuilder: (_, i) {
              final user = UserChat.fromDocument(docs[i]);
              return _SearchResultTile(
                  userChat: user,
                  isDark: isDark,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (widget.isWebSidebar && widget.onChatSelected != null) {
                      widget.onChatSelected!({
                        'peerId': user.id,
                        'peerAvatar': user.photoUrl,
                        'peerNickname': user.nickname
                      });
                    } else {
                      _push(UserProfilePage(userChat: user));
                    }
                  });
            },
          ),
          if (_isLoadingMore)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5))),
        ]);
      },
    );
  }

  // ── Expandable FAB ─────────────────────────────────────────────────────────

  Widget _buildExpandableFab(bool isDark) {
    final fabItems = [
      _FabItem(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'New Chat',
          color: const Color(0xFF4F8EFF),
          onTap: () {
            _closeFab();
            _push(FriendsPage());
          }),
      _FabItem(
          icon: Icons.qr_code_scanner_rounded,
          label: 'Scan QR',
          color: const Color(0xFF34C759),
          onTap: _scanQRCode),
      _FabItem(
          icon: Icons.group_add_outlined,
          label: 'Group',
          color: const Color(0xFFFF9F0A),
          onTap: () {
            _closeFab();
            _push(CreateGroupPage());
          }),
      _FabItem(
          icon: Icons.auto_awesome_rounded,
          label: 'AI Chat',
          color: const Color(0xFF7B61FF),
          onTap: () {
            _closeFab();
            _push(ChatPage(
                arguments: ChatPageArguments(
                    peerId: AppConstants.aiAssistantId,
                    peerAvatar: AppConstants.aiAssistantAvatar,
                    peerNickname: AppConstants.aiAssistantName)));
          }),
    ];

    return Positioned(
      right: 16,
      bottom: 82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Expanded items
          ...fabItems.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return AnimatedBuilder(
              animation: _fabExpandAnim,
              builder: (_, child) {
                final delay = (fabItems.length - 1 - i) * 0.08;
                final progress = (_fabExpandAnim.value - delay).clamp(0.0, 1.0);
                return Opacity(
                  opacity: progress,
                  child: Transform.translate(
                    offset: Offset(0, (1 - progress) * 24),
                    child: child,
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Label
                  AnimatedBuilder(
                    animation: _fabExpandAnim,
                    builder: (_, __) => Opacity(
                      opacity: _fabExpandAnim.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                            color:
                                isDark ? const Color(0xFF1A1A2A) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3))
                            ]),
                        child: Text(item.label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0D1117))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Mini FAB button
                  GestureDetector(
                    onTap: item.onTap,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          color: item.color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: item.color.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ]),
                      child: Icon(item.icon, color: Colors.white, size: 20),
                    ),
                  ),
                ]),
              ),
            );
          }).toList(),

          // Main FAB
          ScaleTransition(
            scale: _fabScaleAnim,
            child: GestureDetector(
              onTap: _toggleFab,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    gradient: _isFabExpanded
                        ? const LinearGradient(
                            colors: [Color(0xFF666680), Color(0xFF444460)])
                        : LinearGradient(
                            colors: [
                                ColorConstants.primaryColor,
                                const Color(0xFF2196F3)
                              ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: (_isFabExpanded
                                  ? Colors.grey
                                  : ColorConstants.primaryColor)
                              .withOpacity(0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 7))
                    ]),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                      _isFabExpanded ? Icons.close_rounded : Icons.add_rounded,
                      key: ValueKey(_isFabExpanded),
                      color: Colors.white,
                      size: 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Menu button ────────────────────────────────────────────────────────────

  Widget _buildMenuButton(bool isDark) {
    return PopupMenuButton<MenuSetting>(
      onSelected: _onMenuSelected,
      offset: const Offset(0, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
      elevation: 14,
      shadowColor: Colors.black.withOpacity(0.18),
      itemBuilder: (_) => _menus.map((m) {
        final isLogout = m.title == 'Log out';
        return PopupMenuItem<MenuSetting>(
            value: m,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: _MenuItemRow(menu: m, isLogout: isLogout, isDark: isDark));
      }).toList(),
      child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color:
                  isDark ? const Color(0xFF1A1A2A) : const Color(0xFFEEF0F7)),
          child: Icon(Icons.more_vert_rounded,
              color: isDark ? Colors.white70 : ColorConstants.primaryColor,
              size: 21)),
    );
  }

  // ── Empty / skeleton states ────────────────────────────────────────────────

  Widget _buildSearchEmpty(bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1A1A2A)
                      : const Color(0xFFEEF0F7),
                  shape: BoxShape.circle),
              child: Icon(Icons.search_off_rounded,
                  size: 34, color: Colors.grey.withOpacity(0.4))),
          const SizedBox(height: 16),
          Text('No results for "$_textSearch"',
              style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Try a different name or phone number',
              style: TextStyle(
                  color: isDark ? Colors.white30 : Colors.grey.shade400,
                  fontSize: 13)),
        ]),
      );

  Widget _buildEmptyState(bool isDark) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
        child: Column(children: [
          Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    ColorConstants.primaryColor,
                    const Color(0xFF2196F3)
                  ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: ColorConstants.primaryColor.withOpacity(0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 10))
                  ]),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  size: 40, color: Colors.white)),
          const SizedBox(height: 24),
          Text('No conversations yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : const Color(0xFF0D1117))),
          const SizedBox(height: 10),
          Text("Scan a friend's QR code to start\nyour first conversation",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                  fontSize: 14,
                  height: 1.6)),
          const SizedBox(height: 28),
          GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _scanQRCode();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      ColorConstants.primaryColor,
                      const Color(0xFF2196F3)
                    ], begin: Alignment.centerLeft, end: Alignment.centerRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: ColorConstants.primaryColor.withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6))
                    ]),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Scan QR Code',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ]),
              )),
        ]),
      );

  Widget _buildSkeleton(bool isDark) => ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 7,
      itemBuilder: (_, __) => _SkeletonTile(isDark: isDark));
}

// ════════════════════════════════════════════════════════════════════════════
// BUBBLE DOCK — VisionOS / Dynamic Island style
// ════════════════════════════════════════════════════════════════════════════

class _BubbleDock extends StatelessWidget {
  final String currentUserId;
  final bool isDark;
  final void Function(BubbleData) onBubbleTap;
  final void Function(BubbleData) onBubbleLongPress;
  final VoidCallback onSettingsTap;

  const _BubbleDock({
    required this.currentUserId,
    required this.isDark,
    required this.onBubbleTap,
    required this.onBubbleLongPress,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<UnifiedBubbleService>(
      builder: (_, svc, __) {
        return StreamBuilder<Map<String, BubbleData>>(
          stream: svc.activeBubblesStream,
          builder: (ctx, snap) {
            final bubbles = snap.data?.values.toList() ?? [];
            return AnimatedPositioned(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              left: 0,
              right: 0,
              bottom: bubbles.isEmpty ? -80 : 88,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: bubbles.isEmpty ? 0 : 1,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutBack,
                    height: 58,
                    constraints: BoxConstraints(
                        maxWidth: math.min(64.0 * bubbles.length + 96, 340)),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.07)
                          : Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.white.withOpacity(0.9),
                          width: 1.5),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 30,
                            offset: const Offset(0, 10)),
                        BoxShadow(
                            color: ColorConstants.primaryColor.withOpacity(0.1),
                            blurRadius: 16,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(width: 12),
                            // Bubble count indicator
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    ColorConstants.primaryColor,
                                    const Color(0xFF2196F3)
                                  ]),
                                  shape: BoxShape.circle),
                              child: Center(
                                  child: Text('${bubbles.length}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900))),
                            ),
                            const SizedBox(width: 8),
                            // Avatar list
                            ...bubbles.map((b) => GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    onBubbleTap(b);
                                  },
                                  onLongPress: () {
                                    HapticFeedback.mediumImpact();
                                    onBubbleLongPress(b);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          CircleAvatar(
                                              radius: 19,
                                              backgroundImage: b
                                                      .avatarUrl.isNotEmpty
                                                  ? NetworkImage(b.avatarUrl)
                                                  : null,
                                              backgroundColor: ColorConstants
                                                  .primaryColor
                                                  .withOpacity(0.2),
                                              child: b.avatarUrl.isEmpty
                                                  ? Text(
                                                      b.userName.isNotEmpty
                                                          ? b.userName[0]
                                                              .toUpperCase()
                                                          : '?',
                                                      style: TextStyle(
                                                          color: ColorConstants
                                                              .primaryColor,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 13))
                                                  : null),
                                          if (b.unreadCount > 0)
                                            Positioned(
                                                top: -4,
                                                right: -4,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(2),
                                                  constraints:
                                                      const BoxConstraints(
                                                          minWidth: 15,
                                                          minHeight: 15),
                                                  decoration:
                                                      const BoxDecoration(
                                                          color: Colors.red,
                                                          shape:
                                                              BoxShape.circle),
                                                  child: Text(
                                                      b.unreadCount > 9
                                                          ? '9+'
                                                          : '${b.unreadCount}',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 8,
                                                          fontWeight:
                                                              FontWeight.w900)),
                                                )),
                                          Positioned(
                                              bottom: -1,
                                              right: -1,
                                              child: Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    color: b.isOnline
                                                        ? const Color(
                                                            0xFF4CAF50)
                                                        : Colors.grey.shade400,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                        color: isDark
                                                            ? const Color(
                                                                0xFF080810)
                                                            : Colors.white,
                                                        width: 1.5),
                                                  ))),
                                        ]),
                                  ),
                                )),
                            // Settings button
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                onSettingsTap();
                              },
                              child: Container(
                                  width: 32,
                                  height: 32,
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withOpacity(0.08)
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Icon(Icons.settings_rounded,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.grey.shade500,
                                      size: 15)),
                            ),
                            const SizedBox(width: 4),
                          ]),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SEGMENTED CONTROL
// ════════════════════════════════════════════════════════════════════════════

class _SegmentedControl extends StatefulWidget {
  final List<String> labels;
  final int activeIndex;
  final bool isDark;
  final ValueChanged<int> onChanged;

  const _SegmentedControl({
    required this.labels,
    required this.activeIndex,
    required this.isDark,
    required this.onChanged,
  });

  @override
  State<_SegmentedControl> createState() => _SegmentedControlState();
}

class _SegmentedControlState extends State<_SegmentedControl>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slideAnim;
  late double _indicatorWidth;
  late int _prevIndex;

  @override
  void initState() {
    super.initState();
    _prevIndex = widget.activeIndex;
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240));
    _slideAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(_SegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      _prevIndex = oldWidget.activeIndex;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final n = widget.labels.length;
    final bgColor = isDark ? const Color(0xFF1A1A2A) : const Color(0xFFE8EAF2);

    return Container(
      height: 38,
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final totalW = constraints.maxWidth;
        _indicatorWidth = totalW / n;

        return Stack(children: [
          // Sliding indicator
          AnimatedBuilder(
            animation: _slideAnim,
            builder: (_, __) {
              final fromX = _prevIndex * _indicatorWidth;
              final toX = widget.activeIndex * _indicatorWidth;
              final x = _lerpDouble(fromX, toX, _slideAnim.value);
              return Positioned(
                left: x + 3,
                top: 3,
                child: Container(
                  width: _indicatorWidth - 6,
                  height: 32,
                  decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A3A) : Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ]),
                ),
              );
            },
          ),
          // Labels
          Row(
              children: List.generate(n, (i) {
            final isActive = widget.activeIndex == i;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onChanged(i),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? (isDark ? Colors.white : const Color(0xFF0D1117))
                            : (isDark ? Colors.white38 : Colors.grey.shade500)),
                    child: Text(widget.labels[i]),
                  ),
                ),
              ),
            );
          })),
        ]);
      }),
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

// ════════════════════════════════════════════════════════════════════════════
// QUICK ACTION PILL
// ════════════════════════════════════════════════════════════════════════════

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
}

class _QuickActionPill extends StatefulWidget {
  final _QuickAction action;
  final bool isDark;
  final int index;
  const _QuickActionPill(
      {required this.action, required this.isDark, required this.index});

  @override
  State<_QuickActionPill> createState() => _QuickActionPillState();
}

class _QuickActionPillState extends State<_QuickActionPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _pressAnim = Tween<double>(begin: 1.0, end: 0.92)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.action.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _pressAnim,
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.action.color.withOpacity(widget.isDark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: widget.action.color.withOpacity(0.3), width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: widget.action.color.withOpacity(0.15),
                  shape: BoxShape.circle),
              child: Icon(widget.action.icon,
                  color: widget.action.color, size: 14),
            ),
            const SizedBox(width: 8),
            Text(widget.action.label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.action.color)),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MESH BACKGROUND
// ════════════════════════════════════════════════════════════════════════════

class _MeshBackground extends StatelessWidget {
  final bool isDark;
  const _MeshBackground({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MeshPainter(isDark: isDark));
  }
}

class _MeshPainter extends CustomPainter {
  final bool isDark;
  const _MeshPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final orb1 = Paint()
      ..shader = RadialGradient(
        colors: [
          ColorConstants.primaryColor.withOpacity(isDark ? 0.08 : 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.85, size.height * 0.08), radius: 220));
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.08), 220, orb1);

    final orb2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2196F3).withOpacity(isDark ? 0.06 : 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.1, size.height * 0.4), radius: 180));
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.4), 180, orb2);
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.isDark != isDark;
}

// ════════════════════════════════════════════════════════════════════════════
// FAB ITEM
// ════════════════════════════════════════════════════════════════════════════

class _FabItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _FabItem(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
}

// ════════════════════════════════════════════════════════════════════════════
// PRIVATE SUB-WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _UnreadBadge extends StatefulWidget {
  final String userId;
  final bool isDark;
  const _UnreadBadge({required this.userId, required this.isDark});

  @override
  State<_UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<_UnreadBadge> {
  late final Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathConversationCollection)
        .where(FirestoreConstants.participants, arrayContains: widget.userId)
        .where('unreadCount', isGreaterThan: 0)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (_, snap) {
        final count = snap.hasData ? snap.data!.docs.length : 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  ColorConstants.primaryColor,
                  const Color(0xFF2196F3)
                ]),
                borderRadius: BorderRadius.circular(10)),
            child: Text(count > 99 ? '99+' : '$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)));
      });
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final String? tooltip;

  const _IconBtn(
      {required this.icon,
      required this.isDark,
      required this.onTap,
      this.tooltip});

  @override
  Widget build(BuildContext context) => Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
          onTap: onTap,
          child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1A1A2A)
                      : const Color(0xFFEEF0F7),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(icon,
                  color: isDark ? Colors.white70 : ColorConstants.primaryColor,
                  size: 20))));
}

class _AnimatedBadge extends StatefulWidget {
  final int count;
  final bool isDark;
  const _AnimatedBadge({required this.count, required this.isDark});

  @override
  State<_AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<_AnimatedBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450))
      ..forward();
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
      scale: _scale,
      child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
              color: Colors.red.shade600,
              shape: BoxShape.circle,
              border: Border.all(
                  color: widget.isDark ? const Color(0xFF0E0E18) : Colors.white,
                  width: 2)),
          child: Center(
              child: Text(widget.count > 9 ? '9+' : '${widget.count}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900)))));
}

class _MenuItemRow extends StatelessWidget {
  final MenuSetting menu;
  final bool isLogout, isDark;
  const _MenuItemRow(
      {required this.menu, required this.isLogout, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isBubble = menu.title == 'Bubble Chat';
    final color = isLogout
        ? Colors.redAccent
        : isBubble
            ? const Color(0xFF4CAF50)
            : ColorConstants.primaryColor;
    return Row(children: [
      Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(menu.icon, color: color, size: 17)),
      const SizedBox(width: 12),
      Text(menu.title,
          style: TextStyle(
              color: isLogout
                  ? Colors.redAccent
                  : (isDark
                      ? const Color(0xFFF0F2F8)
                      : const Color(0xFF0D1117)),
              fontSize: 14,
              fontWeight: FontWeight.w500)),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CONVERSATION TILE
// ════════════════════════════════════════════════════════════════════════════

class _ConversationTile extends StatelessWidget {
  final String id, name, photoUrl, lastMessage, timeLabel;
  final bool isPinned, isMuted, isGroup, isDark, isAi;
  final String? onlineUserId;
  final int unreadCount;
  final VoidCallback onTap, onLongPress;

  const _ConversationTile(
      {required this.id,
      required this.name,
      required this.photoUrl,
      required this.lastMessage,
      required this.timeLabel,
      required this.isPinned,
      required this.isMuted,
      required this.isGroup,
      required this.isDark,
      required this.onTap,
      required this.onLongPress,
      this.onlineUserId,
      this.unreadCount = 0,
      this.isAi = false});

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0 && !isMuted;

    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            splashColor: ColorConstants.primaryColor.withOpacity(0.06),
            highlightColor: ColorConstants.primaryColor.withOpacity(0.02),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: isPinned
                      ? ColorConstants.primaryColor
                          .withOpacity(isDark ? 0.06 : 0.03)
                      : Colors.transparent),
              child: Row(children: [
                // Avatar with status overlays
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(clipBehavior: Clip.none, children: [
                    _Avatar(
                        photoUrl: photoUrl,
                        name: name,
                        size: 52,
                        isDark: isDark,
                        isGroup: isGroup,
                        isAi: isAi),
                    if (onlineUserId != null)
                      Positioned(
                          right: 1,
                          bottom: 1,
                          child: _OnlineDot(userId: onlineUserId!)),
                    if (isMuted)
                      Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                              width: 17,
                              height: 17,
                              decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF0E0E18)
                                      : Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF0E0E18)
                                          : Colors.white,
                                      width: 1.5)),
                              child: const Icon(Icons.volume_off_rounded,
                                  size: 9, color: Colors.grey))),
                  ]),
                ),
                const SizedBox(width: 12),
                // Text content
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (isPinned) ...[
                              Icon(Icons.push_pin_rounded,
                                  size: 10,
                                  color: ColorConstants.primaryColor
                                      .withOpacity(0.65)),
                              const SizedBox(width: 3),
                            ],
                            if (isAi) ...[
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [
                                        Color(0xFF7B61FF),
                                        Color(0xFF4285F4)
                                      ]),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: const Text('AI',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900))),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                                child: Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0D1117),
                                        fontWeight: hasUnread
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        fontSize: 15,
                                        letterSpacing: -0.3))),
                            const SizedBox(width: 8),
                            Text(timeLabel,
                                style: TextStyle(
                                    color: hasUnread
                                        ? ColorConstants.primaryColor
                                        : (isDark
                                            ? Colors.white30
                                            : Colors.grey.shade400),
                                    fontSize: 11.5,
                                    fontWeight: hasUnread
                                        ? FontWeight.w700
                                        : FontWeight.w400)),
                          ]),
                      const SizedBox(height: 3),
                      Row(children: [
                        Expanded(
                            child: Text(lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: hasUnread
                                        ? (isDark
                                            ? Colors.white60
                                            : const Color(0xFF374151))
                                        : (isDark
                                            ? Colors.white30
                                            : Colors.grey.shade400),
                                    fontSize: 13,
                                    fontWeight: hasUnread
                                        ? FontWeight.w500
                                        : FontWeight.w400))),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _UnreadChip(count: unreadCount),
                        ],
                        if (isMuted && !hasUnread)
                          Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(Icons.volume_off_rounded,
                                  size: 13,
                                  color: Colors.grey.withOpacity(0.5))),
                      ]),
                    ])),
              ]),
            )));
  }
}

class _UnreadChip extends StatelessWidget {
  final int count;
  const _UnreadChip({required this.count});

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [ColorConstants.primaryColor, const Color(0xFF2196F3)]),
          borderRadius: BorderRadius.circular(10)),
      child: Text(count > 99 ? '99+' : '$count',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800)));
}

// ════════════════════════════════════════════════════════════════════════════
// AVATAR
// ════════════════════════════════════════════════════════════════════════════

class _Avatar extends StatelessWidget {
  final String photoUrl, name;
  final double size;
  final bool isDark, isGroup, isAi;

  const _Avatar(
      {required this.photoUrl,
      required this.name,
      required this.size,
      required this.isDark,
      this.isGroup = false,
      this.isAi = false});

  @override
  Widget build(BuildContext context) {
    if (isAi) {
      return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [Color(0xFF7B61FF), Color(0xFF4285F4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 24));
    }
    final colorIdx = name.isEmpty
        ? 0
        : name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIdx];
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatarColor.withOpacity(0.12),
            border:
                Border.all(color: avatarColor.withOpacity(0.18), width: 1.5)),
        child: ClipOval(
            child: photoUrl.isNotEmpty
                ? Image.network(photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _fallback(initials, avatarColor))
                : _fallback(initials, avatarColor)));
  }

  Widget _fallback(String text, Color color) {
    if (isGroup) {
      return Container(
          color: color.withOpacity(0.12),
          child: Icon(Icons.group_rounded, color: color, size: size * 0.42));
    }
    return Container(
        color: color.withOpacity(0.12),
        alignment: Alignment.center,
        child: Text(text,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.36)));
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ONLINE DOT
// ════════════════════════════════════════════════════════════════════════════

class _OnlineDot extends StatelessWidget {
  final String userId;
  const _OnlineDot({required this.userId});

  @override
  Widget build(BuildContext context) {
    final presenceProvider = context.read<UserPresenceProvider>();
    return StreamBuilder<UserPresence>(
        stream: presenceProvider.getUserPresenceStream(userId),
        builder: (_, snap) {
          if (snap.data?.isOnline != true) return const SizedBox.shrink();
          return Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: const Color(0xFF34C759),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2)));
        });
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SEARCH RESULT TILE
// ════════════════════════════════════════════════════════════════════════════

class _SearchResultTile extends StatelessWidget {
  final UserChat userChat;
  final bool isDark;
  final VoidCallback onTap;

  const _SearchResultTile(
      {required this.userChat, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap,
          splashColor: ColorConstants.primaryColor.withOpacity(0.06),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                _Avatar(
                    photoUrl: userChat.photoUrl,
                    name: userChat.nickname,
                    size: 48,
                    isDark: isDark),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(userChat.nickname,
                          style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0D1117),
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5)),
                      if (userChat.phoneNumber.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('📱 ${userChat.phoneNumber}',
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12))),
                      if (userChat.aboutMe.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(userChat.aboutMe,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.grey.withOpacity(0.6),
                                    fontSize: 12))),
                    ])),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          ColorConstants.primaryColor,
                          const Color(0xFF2196F3)
                        ]),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('View',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))),
              ]))));
}

// ════════════════════════════════════════════════════════════════════════════
// SCROLL TO TOP BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _ScrollToTopButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScrollToTopButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                ColorConstants.primaryColor,
                const Color(0xFF2196F3)
              ]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: ColorConstants.primaryColor.withOpacity(0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4))
              ]),
          child: const Icon(Icons.keyboard_arrow_up_rounded,
              color: Colors.white, size: 22)));
}

// ════════════════════════════════════════════════════════════════════════════
// SKELETON TILE
// ════════════════════════════════════════════════════════════════════════════

class _SkeletonTile extends StatefulWidget {
  final bool isDark;
  const _SkeletonTile({required this.isDark});

  @override
  State<_SkeletonTile> createState() => _SkeletonTileState();
}

class _SkeletonTileState extends State<_SkeletonTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final base = widget.isDark
            ? Color.lerp(
                const Color(0xFF1A1A2A), const Color(0xFF252535), _anim.value)!
            : Color.lerp(
                const Color(0xFFEEEEEE), const Color(0xFFE4E4E4), _anim.value)!;
        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Container(
                  width: 52,
                  height: 52,
                  decoration:
                      BoxDecoration(color: base, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                        height: 13,
                        width: 110 + (_anim.value * 28),
                        decoration: BoxDecoration(
                            color: base,
                            borderRadius: BorderRadius.circular(7))),
                    const SizedBox(height: 8),
                    Container(
                        height: 11,
                        width: 160 + (_anim.value * 20),
                        decoration: BoxDecoration(
                            color: base,
                            borderRadius: BorderRadius.circular(6))),
                  ])),
              const SizedBox(width: 12),
              Container(
                  height: 10,
                  width: 28,
                  decoration: BoxDecoration(
                      color: base, borderRadius: BorderRadius.circular(5))),
            ]));
      });
}

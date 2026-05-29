import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/e2ee_service.dart';
import 'package:flutter_chat_demo/utils/utils.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';



@pragma('vm:entry-point')
void _onNotificationResponse(NotificationResponse response) {
  debugPrint('🔔 Notification tapped: id=${response.id}, payload=${response.payload}');
}



class HomePage extends StatefulWidget {
  final bool isWebSidebar;
  final Function(Map<String, dynamic>)? onChatSelected;

  const HomePage({
    super.key,
    this.isWebSidebar = false,
    this.onChatSelected,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  
  final _firebaseMessaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _btnClearController = StreamController<bool>.broadcast();
  final _searchDebouncer = Debouncer(milliseconds: 280);

  
  late final AuthProvider _authProvider;
  late final HomeProvider _homeProvider;
  late final FriendProvider _friendProvider;
  late final ConversationProvider _conversationProvider;
  late final String _currentUserId;

  
  String _textSearch = '';
  bool _isSearchFocused = false;
  bool _isLoading = false;
  int _limit = 20;
  static const int _limitIncrement = 20;

  
  int _activeFilterIndex = 0; 
  static const List<String> _filterLabels = ['All', 'Unread', 'Groups'];

  
  List<String> _myFriendIds = [];
  StreamSubscription<QuerySnapshot>? _friendIdsSub;

  
  late AnimationController _fabAnimCtrl;
  late Animation<double> _fabScaleAnim;
  late AnimationController _filterAnimCtrl;
  late Animation<double> _filterAnim;
  late AnimationController _headerAnimCtrl;
  late Animation<double> _headerFadeAnim;
  late Animation<Offset> _headerSlideAnim;

  
  late final List<MenuSetting> _menus;

  
  bool _showScrollToTop = false;

  
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

    _friendProvider = FriendProvider(firebaseFirestore: _homeProvider.firebaseFirestore);
    _conversationProvider =
        ConversationProvider(firebaseFirestore: _homeProvider.firebaseFirestore);

    _menus = [
      const MenuSetting(title: 'Friends', icon: Icons.people_outline_rounded),
      const MenuSetting(title: 'My Status', icon: Icons.auto_stories_rounded),
      const MenuSetting(title: 'Call History', icon: Icons.call_outlined),
      const MenuSetting(title: 'My QR Code', icon: Icons.qr_code_2_rounded),
      const MenuSetting(title: 'Create Group', icon: Icons.group_add_outlined),
      const MenuSetting(title: 'Theme', icon: Icons.palette_outlined),
      const MenuSetting(title: 'Settings', icon: Icons.settings_outlined),
      const MenuSetting(title: 'Log out', icon: Icons.logout_rounded),
    ];

    _initAnimations();
    _registerNotification();
    _configLocalNotification();
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _listenToFriendIds();
    _initE2EE();
  }

  

  void _initAnimations() {
    
    _fabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fabScaleAnim = CurvedAnimation(
      parent: _fabAnimCtrl,
      curve: Curves.elasticOut,
    );

    
    _filterAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _filterAnim = CurvedAnimation(parent: _filterAnimCtrl, curve: Curves.easeOut);

    
    _headerAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _headerFadeAnim = CurvedAnimation(parent: _headerAnimCtrl, curve: Curves.easeOut);
    _headerSlideAnim = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _headerAnimCtrl,
      curve: Curves.easeOutCubic,
    ));

    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _headerAnimCtrl.forward();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _fabAnimCtrl.forward();
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _filterAnimCtrl.forward();
        });
      }
    });
  }

  

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      
      _homeProvider.updateDataFirestore(
        FirestoreConstants.pathUserCollection,
        _currentUserId,
        {'isOnline': 'true'},
      );
    }
  }

  

  Future<void> _initE2EE() async {
    await E2EEService().generateAndStoreUserKeys(_currentUserId);
  }

  

  void _registerNotification() {
    _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null) {
        _showLocalNotification(message.notification!);
      }
    });

    _firebaseMessaging.getToken().then((token) {
      if (token != null) {
        _homeProvider.updateDataFirestore(
          FirestoreConstants.pathUserCollection,
          _currentUserId,
          {'pushToken': token},
        );
      }
    }).catchError((err) {
      Fluttertoast.showToast(msg: err.message.toString());
    });
  }

  void _configLocalNotification() {
    const androidSettings = AndroidInitializationSettings('app_icon');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open notification');

    _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onNotificationResponse,
    );
  }

  Future<void> _showLocalNotification(RemoteNotification remoteNotification) async {
    final androidDetails = AndroidNotificationDetails(
      Platform.isAndroid ? 'com.dfa.flutterchatdemo' : 'com.duytq.flutterchatdemo',
      'Flutter chat demo',
      channelDescription: 'Chat message notifications',
      playSound: true,
      enableVibration: true,
      importance: Importance.max,
      priority: Priority.high,
      ticker: remoteNotification.title,
      icon: 'app_icon',
      largeIcon: const DrawableResourceAndroidBitmap('app_icon'),
      styleInformation: BigTextStyleInformation(
        remoteNotification.body ?? '',
        contentTitle: remoteNotification.title,
      ),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 & 0x7FFFFFFF,
      remoteNotification.title,
      remoteNotification.body,
      NotificationDetails(android: androidDetails, iOS: darwinDetails, macOS: darwinDetails),
      payload: remoteNotification.title,
    );
  }

  

  void _listenToFriendIds() {
    final fs =
        _homeProvider.firebaseFirestore.collection(FirestoreConstants.pathFriendshipCollection);

    _friendIdsSub = fs
        .where(FirestoreConstants.userId1, isEqualTo: _currentUserId)
        .snapshots()
        .listen((snap1) async {
      final ids = <String>{};
      for (final d in snap1.docs) {
        ids.add(d[FirestoreConstants.userId2] as String);
      }
      final snap2 = await fs.where(FirestoreConstants.userId2, isEqualTo: _currentUserId).get();
      for (final d in snap2.docs) {
        ids.add(d[FirestoreConstants.userId1] as String);
      }
      if (mounted) setState(() => _myFriendIds = ids.take(9).toList());
    });
  }

  

  void _onScroll() {
    if (_scrollController.offset >= _scrollController.position.maxScrollExtent - 200 &&
        !_scrollController.position.outOfRange) {
      setState(() => _limit += _limitIncrement);
    }
    final shouldShow = _scrollController.offset > 300;
    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  void _scrollToTop() {
    HapticFeedback.lightImpact();
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  

  void _onSearchFocusChanged() {
    if (mounted) setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
  }

  

  void _redirectToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage()),
      (_) => false,
    );
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
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage()),
      (_) => false,
    );
  }

  void _scanQRCode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerPage()),
    );
    if (result != null && result is String) {
      setState(() => _isLoading = true);
      final userDoc = await _homeProvider.searchByQRCode(result);
      setState(() => _isLoading = false);
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
        onPin: () =>
            _conversationProvider.togglePinConversation(conversation.id, conversation.isPinned),
        onMute: () =>
            _conversationProvider.toggleMuteConversation(conversation.id, conversation.isMuted),
        onClearHistory: () => _conversationProvider.clearConversationHistory(conversation.id),
        onMarkAsRead: () => _conversationProvider.markAsRead(conversation.id, _currentUserId),
        onArchive: () => _conversationProvider.toggleArchiveConversation(
          conversation.id,
          _currentUserId,
          !conversation.archivedBy.contains(_currentUserId),
        ),
      ),
    );
  }

  

  String _lastMessagePreview(String msg, int? type) {
    if (type == TypeMessage.image) return '📷 Photo';
    if (type == TypeMessage.sticker) return '😊 Sticker';
    if (type == TypeMessage.video) return '🎥 Video';
    if (type == TypeMessage.voice) return '🎵 Audio';
    if (type == TypeMessage.document) return '📄 Document';
    if (msg.isEmpty) return 'Start a conversation';
    return msg.length > 42 ? '${msg.substring(0, 42)}…' : msg;
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

  PageRoute _slideRoute(Widget page) => PageRouteBuilder(
        pageBuilder: (_, a, __) => page,
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 280),
      );

  

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fabAnimCtrl.dispose();
    _filterAnimCtrl.dispose();
    _headerAnimCtrl.dispose();
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

  
  
  

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final storyProvider = context.read<StoryProvider>();

    final bgColor = isDark ? ColorConstants.backgroundDark : const Color(0xFFF6F7FB);
    final surfaceColor = isDark ? ColorConstants.surfaceDark : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          
          Positioned(
            top: -80,
            right: -60,
            child: _GradientOrb(isDark: isDark),
          ),

          SafeArea(
            child: Column(
              children: [
                
                SlideTransition(
                  position: _headerSlideAnim,
                  child: FadeTransition(
                    opacity: _headerFadeAnim,
                    child: _buildHeader(isDark, surfaceColor),
                  ),
                ),

                
                if (_textSearch.isEmpty)
                  FadeTransition(
                    opacity: _filterAnim,
                    child: _buildFilterTabs(isDark),
                  ),

                
                Expanded(
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      
                      if (_textSearch.isEmpty) ...[
                        SliverToBoxAdapter(
                          child: _buildStoriesSection(storyProvider, isDark),
                        ),
                        SliverToBoxAdapter(
                          child: _buildOnlineFriendsSection(isDark),
                        ),
                      ],

                      
                      if (_textSearch.isEmpty)
                        SliverToBoxAdapter(
                          child: _buildSectionLabel(isDark),
                        ),

                      
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                        sliver: SliverToBoxAdapter(
                          child: _buildListCard(isDark, surfaceColor, storyProvider),
                        ),
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          
          if (_isLoading) LoadingView(),

          
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            bottom: _showScrollToTop ? 90 : -60,
            right: 20,
            child: _ScrollToTopButton(onTap: _scrollToTop),
          ),
        ],
      ),

      
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnim,
        child: _PremiumFAB(onTap: () {
          HapticFeedback.lightImpact();
          _scanQRCode();
        }),
      ),
    );
  }

  

  Widget _buildHeader(bool isDark, Color surfaceColor) {
    return Container(
      color: surfaceColor,
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Messages',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: isDark ? Colors.white : const Color(0xFF0D1117),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _UnreadBadge(
                          userId: _currentUserId,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Stay connected',
                      style: TextStyle(
                        fontSize: 12,
                        color: ColorConstants.greyColor,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              
              _buildNotificationBadge(isDark),
              const SizedBox(width: 6),
              _HeaderIconButton(
                icon: Icons.archive_outlined,
                isDark: isDark,
                tooltip: 'Archived',
                onTap: () => _push(const ArchivedChatsPage()),
              ),
              const SizedBox(width: 6),
              _buildMenuButton(isDark),
            ],
          ),

          const SizedBox(height: 12),

          
          _buildSearchBar(isDark),
        ],
      ),
    );
  }

  

  Widget _buildSearchBar(bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 46,
      decoration: BoxDecoration(
        color: isDark ? ColorConstants.surfaceDark2 : const Color(0xFFF0F2F8),
        borderRadius: BorderRadius.circular(14),
        border: _isSearchFocused
            ? Border.all(color: ColorConstants.primaryColor.withValues(alpha: 0.6), width: 1.5)
            : Border.all(color: Colors.transparent),
        boxShadow: _isSearchFocused
            ? [
                BoxShadow(
                  color: ColorConstants.primaryColor.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 3),
                )
              ]
            : [],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _isSearchFocused ? Icons.search_rounded : Icons.search_rounded,
              key: ValueKey(_isSearchFocused),
              color: _isSearchFocused ? ColorConstants.primaryColor : ColorConstants.greyColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: TextStyle(
                fontSize: 14.5,
                color: isDark ? Colors.white : const Color(0xFF0D1117),
                fontWeight: FontWeight.w400,
              ),
              decoration: const InputDecoration(
                hintText: 'Search friends, messages...',
                hintStyle: TextStyle(
                  color: ColorConstants.greyColor,
                  fontSize: 14.5,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) {
                _searchDebouncer.run(() {
                  if (!mounted) return;
                  final hasText = value.isNotEmpty;
                  _btnClearController.add(hasText);
                  setState(() => _textSearch = value);
                });
              },
            ),
          ),
          StreamBuilder<bool>(
            stream: _btnClearController.stream,
            builder: (_, snap) {
              if (snap.data != true) return const SizedBox(width: 12);
              return GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _btnClearController.add(false);
                  setState(() => _textSearch = '');
                  _searchFocusNode.unfocus();
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: ColorConstants.greyColor.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  

  Widget _buildFilterTabs(bool isDark) {
    return Container(
      color: isDark ? ColorConstants.surfaceDark : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: List.generate(_filterLabels.length, (i) {
          final isActive = _activeFilterIndex == i;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _activeFilterIndex = i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: isActive
                    ? ColorConstants.primaryColor
                    : (isDark ? ColorConstants.surfaceDark2 : const Color(0xFFF0F2F8)),
                borderRadius: BorderRadius.circular(20),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: ColorConstants.primaryColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [],
              ),
              child: Text(
                _filterLabels[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? Colors.white
                      : (isDark ? Colors.white60 : ColorConstants.greyColor),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  

  Widget _buildSectionLabel(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _filterLabels[_activeFilterIndex] == 'All'
                ? 'Recent Chats'
                : '${_filterLabels[_activeFilterIndex]} Chats',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF6B7280),
              letterSpacing: 0.2,
            ),
          ),
          GestureDetector(
            onTap: () => _push(const ArchivedChatsPage()),
            child: Text(
              'Archived',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ColorConstants.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  

  Widget _buildListCard(bool isDark, Color surfaceColor, StoryProvider storyProvider) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: _textSearch.isEmpty ? _buildConversationList(isDark) : _buildSearchResults(isDark),
      ),
    );
  }

  

  Widget _buildStoriesSection(StoryProvider provider, bool isDark) {
    return Container(
      color: isDark ? ColorConstants.surfaceDark : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, thickness: 0.5),
          StreamBuilder<List<UserStories>>(
            stream: provider.getStoriesStream(
              currentUserId: _currentUserId,
              friendIds: _myFriendIds,
            ),
            builder: (ctx, snap) {
              final stories = snap.data ?? [];
              return StoriesBar(
                storiesList: stories,
                currentUserId: _currentUserId,
                onAddStory: _openStoryCreator,
                onViewStories: (userStories) {
                  final others = stories.where((s) => s.userId != _currentUserId).toList();
                  final idx = others.indexWhere((s) => s.userId == userStories.userId);
                  _push(StoryViewerPage(
                    allUserStories: others.isNotEmpty ? others : stories,
                    initialUserIndex: idx < 0 ? 0 : idx,
                    currentUserId: _currentUserId,
                    currentUserName:
                        _authProvider.prefs.getString(FirestoreConstants.nickname) ?? '',
                    currentUserPhotoUrl:
                        _authProvider.prefs.getString(FirestoreConstants.photoUrl) ?? '',
                  ));
                },
              );
            },
          ),
        ],
      ),
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

  

  Widget _buildOnlineFriendsSection(bool isDark) {
    return Container(
      color: isDark ? ColorConstants.surfaceDark : Colors.white,
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34C759),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Online now',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF6B7280),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          OnlineFriendsBar(currentUserId: _currentUserId),
          const SizedBox(height: 4),
          Divider(
            height: 1,
            thickness: 0.5,
            color: isDark ? Colors.white10 : const Color(0xFFEEEEF2),
          ),
        ],
      ),
    );
  }

  

  Widget _buildNotificationBadge(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .where(FirestoreConstants.receiverId, isEqualTo: _currentUserId)
          .where(FirestoreConstants.status, isEqualTo: 'pending')
          .snapshots(),
      builder: (_, snap) {
        final count = snap.hasData ? snap.data!.docs.length : 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _HeaderIconButton(
              icon: Icons.notifications_outlined,
              isDark: isDark,
              tooltip: 'Notifications',
              onTap: () => _push(const NotificationsPage()),
            ),
            if (count > 0)
              Positioned(
                right: 5,
                top: 5,
                child: _AnimatedBadge(count: count, isDark: isDark),
              ),
          ],
        );
      },
    );
  }

  

  Widget _buildMenuButton(bool isDark) {
    return PopupMenuButton<MenuSetting>(
      onSelected: _onMenuSelected,
      offset: const Offset(0, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? ColorConstants.surfaceDark2 : Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      itemBuilder: (_) => _menus.map((m) {
        final isLogout = m.title == 'Log out';
        return PopupMenuItem<MenuSetting>(
          value: m,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: _MenuItemRow(menu: m, isLogout: isLogout, isDark: isDark),
        );
      }).toList(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? ColorConstants.surfaceDark2 : const Color(0xFFF0F2F8),
        ),
        child: Icon(
          Icons.more_vert_rounded,
          color: isDark ? Colors.white70 : ColorConstants.primaryColor,
          size: 21,
        ),
      ),
    );
  }

  

  Widget _buildConversationList(bool isDark) {
    Stream<List<QueryDocumentSnapshot>> stream;

    switch (_activeFilterIndex) {
      case 1: 
        stream = _conversationProvider.getUnreadConversations(_currentUserId);
      case 2: 
        stream = _conversationProvider.getConversationsWithPinned(_currentUserId).map((docs) =>
            docs.where((d) => (d.data() as Map<String, dynamic>)['isGroup'] == true).toList());
      default: 
        stream = _conversationProvider.getConversationsWithPinned(_currentUserId);
    }

    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: stream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildSkeleton(isDark);
        }

        final allDocs = snap.data ?? [];
        final activeDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final archivedBy = List<String>.from(data['archivedBy'] as List? ?? []);
          return !archivedBy.contains(_currentUserId);
        }).toList();

        if (activeDocs.isEmpty) {
          return Column(
            children: [
              _buildAiAssistantTile(isDark),
              _buildEmptyState(isDark),
            ],
          );
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
                  indent: 82,
                  endIndent: 16,
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF0F2F8),
                ),
          itemBuilder: (_, i) {
            if (i == 0) return _buildAiAssistantTile(isDark);
            return _buildConversationItem(activeDocs[i - 1], isDark);
          },
        );
      },
    );
  }

  

  Widget _buildAiAssistantTile(bool isDark) {
    return _ConversationTile(
      id: AppConstants.aiAssistantId,
      name: AppConstants.aiAssistantName,
      photoUrl: AppConstants.aiAssistantAvatar,
      lastMessage: 'Smart AI assistant powered by Gemini',
      timeLabel: '',
      isPinned: true,
      isMuted: false,
      isGroup: false,
      isDark: isDark,
      unreadCount: 0,
      isAi: true,
      onTap: () {
        HapticFeedback.lightImpact();
        final args = {
          'peerId': AppConstants.aiAssistantId,
          'peerAvatar': AppConstants.aiAssistantAvatar,
          'peerNickname': AppConstants.aiAssistantName,
        };
        if (widget.isWebSidebar && widget.onChatSelected != null) {
          widget.onChatSelected!(args);
        } else {
          _push(ChatPage(
            arguments: ChatPageArguments(
              peerId: AppConstants.aiAssistantId,
              peerAvatar: AppConstants.aiAssistantAvatar,
              peerNickname: AppConstants.aiAssistantName,
            ),
          ));
        }
      },
      onLongPress: () {
        HapticFeedback.lightImpact();
        Fluttertoast.showToast(msg: 'Gemini AI Assistant');
      },
    );
  }

  

  Widget _buildConversationItem(DocumentSnapshot doc, bool isDark) {
    final conversation = Conversation.fromDocument(doc);

    if (conversation.isGroup) {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection(FirestoreConstants.pathGroupCollection)
            .doc(conversation.id)
            .get(),
        builder: (_, snap) {
          if (!snap.hasData) return _SkeletonTile(isDark: isDark);
          final group = Group.fromDocument(snap.data!);
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
                  'isGroup': true,
                });
              } else {
                _push(GroupChatPage(group: group));
              }
            },
            onLongPress: () => _showConversationOptions(conversation),
          );
        },
      );
    }

    final otherId =
        conversation.participants.firstWhere((id) => id != _currentUserId, orElse: () => '');
    if (otherId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection(FirestoreConstants.pathUserCollection)
          .doc(otherId)
          .get(),
      builder: (_, snap) {
        if (!snap.hasData) return _SkeletonTile(isDark: isDark);
        final userChat = UserChat.fromDocument(snap.data!);
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
                'peerNickname': userChat.nickname,
              });
            } else {
              _push(ChatPage(
                arguments: ChatPageArguments(
                  peerId: userChat.id,
                  peerAvatar: userChat.photoUrl,
                  peerNickname: userChat.nickname,
                ),
              ));
            }
          },
          onLongPress: () => _showConversationOptions(conversation),
        );
      },
    );
  }

  

  Widget _buildSearchResults(bool isDark) {
    final query = _textSearch.trim();
    final isPhone = RegExp(r'^[+\d][\d\s-]*$').hasMatch(query);

    final stream = isPhone
        ? _homeProvider.firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .where(FirestoreConstants.phoneNumber, isEqualTo: query)
            .limit(_limit)
            .snapshots()
        : _homeProvider.firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .where(FirestoreConstants.nickname, isGreaterThanOrEqualTo: query)
            .where(FirestoreConstants.nickname, isLessThanOrEqualTo: '$query\uf8ff')
            .limit(_limit)
            .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (_, snap) {
        if (!snap.hasData) return _buildSkeleton(isDark);

        final docs = snap.data!.docs.where((d) => d.id != _currentUserId).toList();

        if (docs.isEmpty) return _buildSearchEmpty(isDark);

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 76,
            endIndent: 16,
            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF0F2F8),
          ),
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
                    'peerNickname': user.nickname,
                  });
                } else {
                  _push(UserProfilePage(userChat: user));
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSearchEmpty(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded,
              size: 60, color: ColorConstants.greyColor.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            'No results for "$_textSearch"',
            style: TextStyle(
              color: ColorConstants.greyColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try searching by phone number or name',
            style: TextStyle(
              color: ColorConstants.greyColor.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  

  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ColorConstants.primaryColor.withValues(alpha: 0.15),
                  ColorConstants.primaryColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: ColorConstants.primaryColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No conversations yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0D1117),
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'Scan a friend\'s QR code to start\nyour first conversation',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ColorConstants.greyColor,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              _scanQRCode();
            },
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text('Scan QR Code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ColorConstants.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  

  Widget _buildSkeleton(bool isDark) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 7,
      itemBuilder: (_, __) => _SkeletonTile(isDark: isDark),
    );
  }
}







class _GradientOrb extends StatelessWidget {
  final bool isDark;
  const _GradientOrb({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            ColorConstants.primaryColor.withValues(alpha: isDark ? 0.08 : 0.06),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}



class _UnreadBadge extends StatelessWidget {
  final String userId;
  final bool isDark;
  const _UnreadBadge({required this.userId, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .where(FirestoreConstants.participants, arrayContains: userId)
          .where('unreadCount', isGreaterThan: 0)
          .snapshots(),
      builder: (_, snap) {
        final count = snap.hasData ? snap.data!.docs.length : 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: ColorConstants.accentRed,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}



class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final String? tooltip;

  const _HeaderIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDark ? ColorConstants.surfaceDark2 : const Color(0xFFF0F2F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: isDark ? Colors.white70 : ColorConstants.primaryColor, size: 20),
        ),
      ),
    );
  }
}



class _AnimatedBadge extends StatefulWidget {
  final int count;
  final bool isDark;
  const _AnimatedBadge({required this.count, required this.isDark});

  @override
  State<_AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<_AnimatedBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: ColorConstants.accentRed,
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.isDark ? ColorConstants.surfaceDark : Colors.white,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            widget.count > 9 ? '9+' : '${widget.count}',
            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}



class _MenuItemRow extends StatelessWidget {
  final MenuSetting menu;
  final bool isLogout;
  final bool isDark;
  const _MenuItemRow({required this.menu, required this.isLogout, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = isLogout ? ColorConstants.accentRed : ColorConstants.primaryColor;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(menu.icon, color: color, size: 17),
        ),
        const SizedBox(width: 12),
        Text(
          menu.title,
          style: TextStyle(
            color: isLogout
                ? ColorConstants.accentRed
                : (isDark ? const Color(0xFFF0F2F8) : const Color(0xFF0D1117)),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}



class _ConversationTile extends StatelessWidget {
  final String id;
  final String name;
  final String photoUrl;
  final String lastMessage;
  final String timeLabel;
  final bool isPinned;
  final bool isMuted;
  final bool isGroup;
  final bool isDark;
  final bool isAi;
  final String? onlineUserId;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ConversationTile({
    required this.id,
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
    this.isAi = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0 && !isMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: ColorConstants.primaryColor.withValues(alpha: 0.06),
        highlightColor: ColorConstants.primaryColor.withValues(alpha: 0.03),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: isPinned
                ? ColorConstants.primaryColor.withValues(alpha: isDark ? 0.07 : 0.04)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _Avatar(
                    photoUrl: photoUrl,
                    name: name,
                    size: 52,
                    isDark: isDark,
                    isGroup: isGroup,
                    isAi: isAi,
                  ),
                  if (onlineUserId != null)
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: _OnlineDot(userId: onlineUserId!),
                    ),
                  if (isMuted)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: isDark ? ColorConstants.surfaceDark : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isDark ? ColorConstants.surfaceDark : Colors.white,
                              width: 1.5),
                        ),
                        child: const Icon(Icons.volume_off_rounded,
                            size: 10, color: ColorConstants.greyColor),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),

              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isPinned) ...[
                          Icon(Icons.push_pin_rounded,
                              size: 12, color: ColorConstants.primaryColor.withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                        ],
                        if (isAi) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                const Color(0xFF4285F4),
                                const Color(0xFF7B61FF),
                              ]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('AI',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF0D1117),
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 15.5,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            color:
                                hasUnread ? ColorConstants.primaryColor : ColorConstants.greyColor,
                            fontSize: 12,
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread
                                  ? (isDark ? Colors.white70 : const Color(0xFF444950))
                                  : (isDark ? Colors.white38 : const Color(0xFF9CA3AF)),
                              fontSize: 13.5,
                              fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _UnreadCountChip(count: unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



class _UnreadCountChip extends StatelessWidget {
  final int count;
  const _UnreadCountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: ColorConstants.primaryColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}



class _Avatar extends StatelessWidget {
  final String photoUrl;
  final String name;
  final double size;
  final bool isDark;
  final bool isGroup;
  final bool isAi;

  const _Avatar({
    required this.photoUrl,
    required this.name,
    required this.size,
    required this.isDark,
    this.isGroup = false,
    this.isAi = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isAi) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF4285F4), Color(0xFF7B61FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
      );
    }

    final colorIdx = name.isEmpty ? 0 : name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIdx];
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColor.withValues(alpha: 0.12),
        border: Border.all(color: avatarColor.withValues(alpha: 0.2), width: 1.5),
      ),
      child: ClipOval(
        child: photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initials(initials, avatarColor),
              )
            : _initials(initials, avatarColor),
      ),
    );
  }

  Widget _initials(String text, Color color) {
    if (isGroup) {
      return Container(
        color: color.withValues(alpha: 0.12),
        child: Icon(Icons.group_rounded, color: color, size: size * 0.44),
      );
    }
    return Container(
      color: color.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}



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
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFF34C759),
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
          ),
        );
      },
    );
  }
}



class _SearchResultTile extends StatelessWidget {
  final UserChat userChat;
  final bool isDark;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.userChat,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: ColorConstants.primaryColor.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _Avatar(
                photoUrl: userChat.photoUrl,
                name: userChat.nickname,
                size: 48,
                isDark: isDark,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userChat.nickname,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0D1117),
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    if (userChat.phoneNumber.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('📱 ${userChat.phoneNumber}',
                            style: const TextStyle(color: ColorConstants.greyColor, fontSize: 12)),
                      ),
                    if (userChat.aboutMe.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          userChat.aboutMe,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ColorConstants.greyColor.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: ColorConstants.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'View',
                  style: TextStyle(
                    color: ColorConstants.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



class _ScrollToTopButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScrollToTopButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: ColorConstants.primaryColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: ColorConstants.primaryColor.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
      ),
    );
  }
}



class _PremiumFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _PremiumFAB({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              ColorConstants.primaryColor,
              ColorConstants.primaryColor.withBlue(255),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: ColorConstants.primaryColor.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}



class _SkeletonTile extends StatefulWidget {
  final bool isDark;
  const _SkeletonTile({required this.isDark});

  @override
  State<_SkeletonTile> createState() => _SkeletonTileState();
}

class _SkeletonTileState extends State<_SkeletonTile> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final base = widget.isDark
            ? Color.lerp(const Color(0xFF1E2235), const Color(0xFF252A40), _anim.value)!
            : Color.lerp(const Color(0xFFF0F2F8), const Color(0xFFE4E8F2), _anim.value)!;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: base, shape: BoxShape.circle)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 13,
                      width: 110 + (_anim.value * 30),
                      decoration:
                          BoxDecoration(color: base, borderRadius: BorderRadius.circular(7)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 11,
                      width: 160 + (_anim.value * 20),
                      decoration:
                          BoxDecoration(color: base, borderRadius: BorderRadius.circular(6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 10,
                width: 28,
                decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(5)),
              ),
            ],
          ),
        );
      },
    );
  }
}

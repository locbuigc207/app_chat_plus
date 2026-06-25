// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // [+] listEquals
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/utils/utils.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

// ════════════════════════════════════════════════════════════════════════════
// DESIGN TOKENS
// OLED-first palette. Accent: iOS blue. Clean, minimal, no heavy gradients.
// ════════════════════════════════════════════════════════════════════════════

Color _bg(bool d) => d ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
Color _surface(bool d) => d ? const Color(0xFF111116) : const Color(0xFFFFFFFF);
Color _surface2(bool d) =>
    d ? const Color(0xFF1C1C22) : const Color(0xFFEEEEF4);
Color _sep(bool d) => d ? const Color(0xFF2C2C34) : const Color(0xFFE5E5EA);
Color _primary(bool d) => d ? Colors.white : const Color(0xFF000000);
Color _secondary(bool d) =>
    d ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);
const _kAccent = Color(0xFF0A84FF);
const _kGreen = Color(0xFF30D158);
const _kRed = Color(0xFFFF3B30);
const _kOrange = Color(0xFFFF9500);
const _kAiGradient = [Color(0xFF7B61FF), Color(0xFF4285F4)];

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
  static const int _limitIncrement = 20;
  static const List<String> _filterLabels = ['Tất cả', 'Chưa đọc', 'Nhóm'];

  // ── Friends / stories ──────────────────────────────────────────────────────
  List<String> _myFriendIds = [];
  StreamSubscription<List<String>>? _friendIdsSub;

  // ── Stable streams ─────────────────────────────────────────────────────────
  Stream<List<QueryDocumentSnapshot>>? _conversationsStream;
  late final Stream<QuerySnapshot> _friendRequestsStream;

  // ── Unread count stream (dùng chung cho badge + filter chip) ──────────────
  late final Stream<QuerySnapshot> _unreadCountStream;

  // ── Profile cache ──────────────────────────────────────────────────────────
  final Map<String, UserChat> _userProfileCache = {};
  final Map<String, Group> _groupCache = {};
  bool _isPrefetching = false;
  Timer? _prefetchDebouncer;

  // [+] Prefetch de-dupe: only schedule when doc list actually changes
  List<String>? _lastPrefetchDocIds;

  // [+] Time-string cache: safe to cache day-and-older formats; keeps fresh for recent
  final Map<String, String> _timeAgoCache = {};

  // [+] Search stream cache: prevents creating a new Firestore listener on every rebuild
  Stream<QuerySnapshot>? _activeSearchStream;
  String _activeSearchKey = '';

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _fabAnimCtrl;
  late Animation<double> _fabScaleAnim;
  late AnimationController _filterAnimCtrl;
  late Animation<double> _filterAnim;
  late AnimationController _headerAnimCtrl;
  late Animation<double> _headerFadeAnim;
  late Animation<Offset> _headerSlideAnim;

  // ── Menu ───────────────────────────────────────────────────────────────────
  late final List<MenuSetting> _menus;

  // ════════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
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

    _friendProvider = context.read<FriendProvider>();
    _conversationProvider = context.read<ConversationProvider>();

    _menus = [
      const MenuSetting(title: 'New Chat', icon: Icons.edit_square),
      const MenuSetting(title: 'Friends', icon: Icons.people_outline_rounded),
      const MenuSetting(title: 'My Status', icon: Icons.auto_stories_rounded),
      const MenuSetting(title: 'Call History', icon: Icons.call_outlined),
      const MenuSetting(title: 'My QR Code', icon: Icons.qr_code_2_rounded),
      const MenuSetting(title: 'Create Group', icon: Icons.group_add_outlined),
      const MenuSetting(title: 'Archive', icon: Icons.archive_outlined),
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

    // [FIX P0] Xóa where('unreadCount', isGreaterThan: 0) để tương thích với Map
    _unreadCountStream = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathConversationCollection)
        .where(FirestoreConstants.participants, arrayContains: _currentUserId)
        .snapshots();

    _initAnimations();
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _listenToFriendIds();
    _initE2EE();

    BubbleLifecycleObserver.instance.attach();
  }

  // ── Stream ─────────────────────────────────────────────────────────────────

  void _updateConversationsStream() {
    switch (_activeFilterIndex) {
      case 1:
        _conversationsStream = _conversationProvider.getUnreadConversations(
          _currentUserId,
        );
      case 2:
        _conversationsStream = _conversationProvider
            .getConversationsWithPinned(_currentUserId)
            .map(
              (docs) => docs
                  .where(
                    (d) =>
                        (d.data() as Map<String, dynamic>)['isGroup'] == true,
                  )
                  .toList(),
            );
      default:
        _conversationsStream = _conversationProvider.getConversationsWithPinned(
          _currentUserId,
        );
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
    List<QueryDocumentSnapshot> docs,
  ) async {
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
          final participants = List<String>.from(
            data['participants'] as List? ?? [],
          );
          final otherId = participants.firstWhere(
            (id) => id != _currentUserId,
            orElse: () => '',
          );
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
      // [+] Skip setState when nothing actually changed to avoid unnecessary rebuild
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
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fabScaleAnim = CurvedAnimation(
      parent: _fabAnimCtrl,
      curve: Curves.elasticOut,
    );

    _filterAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _filterAnim = CurvedAnimation(
      parent: _filterAnimCtrl,
      curve: Curves.easeOut,
    );

    _headerAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _headerFadeAnim = CurvedAnimation(
      parent: _headerAnimCtrl,
      curve: Curves.easeOut,
    );
    _headerSlideAnim =
        Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero).animate(
          CurvedAnimation(parent: _headerAnimCtrl, curve: Curves.easeOutCubic),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _headerAnimCtrl.forward();
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) _filterAnimCtrl.forward();
      });
      Future.delayed(const Duration(milliseconds: 320), () {
        if (mounted) _fabAnimCtrl.forward();
      });
    });
  }

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

  // ── Friends stream ─────────────────────────────────────────────────────────

  void _listenToFriendIds() {
    final fs = _homeProvider.firebaseFirestore.collection(
      FirestoreConstants.pathFriendshipCollection,
    );

    _friendIdsSub =
        Rx.combineLatest2(
          fs
              .where(FirestoreConstants.userId1, isEqualTo: _currentUserId)
              .snapshots(),
          fs
              .where(FirestoreConstants.userId2, isEqualTo: _currentUserId)
              .snapshots(),
          (snap1, snap2) {
            final ids = <String>{};
            for (final d in snap1.docs) {
              ids.add(d[FirestoreConstants.userId2] as String);
            }
            for (final d in snap2.docs) {
              ids.add(d[FirestoreConstants.userId1] as String);
            }
            return ids.take(9).toList();
          },
        ).listen((ids) {
          if (mounted) setState(() => _myFriendIds = ids);
        });
  }

  // ── Scroll ─────────────────────────────────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;

    // [+] Debounce _isLoadingMore reset with a flag check to avoid race
    if (_textSearch.isNotEmpty &&
        !_isLoadingMore &&
        pos.pixels >= pos.maxScrollExtent - 300) {
      _isLoadingMore = true;
      setState(() => _searchLimit += _limitIncrement);
      // [+] Invalidate cached search stream so new limit is applied
      _activeSearchKey = '';
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _isLoadingMore = false;
      });
    }

    final show = pos.pixels > 280;
    if (show != _showScrollToTop) setState(() => _showScrollToTop = show);
  }

  void _scrollToTop() {
    HapticFeedback.lightImpact();
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
  }

  void _closeFab() {}

  // ── Search stream helper ───────────────────────────────────────────────────
  // [+] Returns a cached Firestore stream so no new listener is created on rebuild
  Stream<QuerySnapshot> _getSearchStream(String query, int limit) {
    final key = '$query::$limit';
    if (key == _activeSearchKey && _activeSearchStream != null) {
      return _activeSearchStream!;
    }
    _activeSearchKey = key;
    final isPhone = RegExp(r'^[+\d][\d\s-]*$').hasMatch(query);
    _activeSearchStream = isPhone
        ? _homeProvider.firebaseFirestore
              .collection(FirestoreConstants.pathUserCollection)
              .where(FirestoreConstants.phoneNumber, isEqualTo: query)
              .limit(limit)
              .snapshots()
        : _homeProvider.firebaseFirestore
              .collection(FirestoreConstants.pathUserCollection)
              .where(FirestoreConstants.nickname, isGreaterThanOrEqualTo: query)
              .where(
                FirestoreConstants.nickname,
                isLessThanOrEqualTo: '$query\uf8ff',
              )
              .limit(limit)
              .snapshots();
    return _activeSearchStream!;
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

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
      case 'New Chat':
        _push(FriendsPage());
      case 'Friends':
        _push(FriendsPage());
      case 'Call History':
        _push(CallHistoryPage(currentUserId: _currentUserId));
      case 'My QR Code':
        _push(const MyQRCodePage());
      case 'Create Group':
        _push(CreateGroupPage());
      case 'Archive':
        _push(const ArchivedChatsPage());
      case 'Bubble Chat':
        _push(const BubbleSettingsPage());
      case 'Theme':
        _push(const ThemeSettingsPage());
      case 'My Status':
        _push(
          MyStoriesPage(
            userId: _currentUserId,
            userName: prefs.getString(FirestoreConstants.nickname) ?? '',
            userPhotoUrl: prefs.getString(FirestoreConstants.photoUrl) ?? '',
          ),
        );
      default:
        _push(const SettingsPage());
    }
  }

  Future<void> _handleSignOut() async {
    SyncManager().stopListening();
    await _authProvider.handleSignOut();
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage()),
      (_) => false,
    );
  }

  void _scanQRCode() async {
    _closeFab();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerPage()),
    );
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

  // [TÍCH HỢP BATCH 4]: Xử lý hiển thị Onboarding Dialog khi người dùng ấn vào Banner
  Future<void> _handleBannerTap() async {
    try {
      final method = const MethodChannel('chat_bubbles_v2');
      final oemName =
          await method.invokeMethod<String>('getOemName') ?? 'Android';
      final rawSteps = await method.invokeListMethod<String>(
        'getBubbleSetupSteps',
      );
      final steps =
          rawSteps?.cast<String>() ??
          ['Cài đặt → Thông báo → Cho phép bong bóng'];

      if (!mounted) return;

      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BubbleOnboardingDialog(
          status: BubblePermissionService.instance.currentStatus,
          oemName: oemName,
          setupSteps: steps,
        ),
      );

      BubblePermissionService.instance.refresh();
    } catch (e) {
      debugPrint('Lỗi hiển thị Onboarding: $e');
    }
  }

  // ── Conversation swipe actions ─────────────────────────────────────────────

  Widget _wrapWithSwipe({
    required Widget child,
    required Conversation conversation,
  }) {
    return Dismissible(
      key: ValueKey('swipe_${conversation.id}'),
      background: Container(
        // [+] Gradient background gives a more modern feel than flat color
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kAccent, Color(0xFF0060D0)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all_rounded, color: Colors.white, size: 22),
            SizedBox(height: 4),
            Text(
              'Đã đọc',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFDD7700), _kOrange],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.archive_rounded, color: Colors.white, size: 22),
            SizedBox(height: 4),
            Text(
              'Lưu trữ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          try {
            await _conversationProvider.markAsRead(
              conversation.id,
              _currentUserId,
            );
            HapticFeedback.lightImpact();
            return false;
          } catch (e) {
            Fluttertoast.showToast(msg: '❌ Lỗi đánh dấu đã đọc');
            return false;
          }
        } else {
          try {
            await _conversationProvider.toggleArchiveConversation(
              conversation.id,
              _currentUserId,
              true,
            );
            HapticFeedback.mediumImpact();
            return true;
          } catch (e) {
            Fluttertoast.showToast(msg: '❌ Lỗi kết nối mạng, vui lòng thử lại');
            return false;
          }
        }
      },
      child: child,
    );
  }

  // ── Conversation options (long-press) ─────────────────────────────────────

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
          conversation.id,
          conversation.isPinned,
        ),
        onMute: () => _conversationProvider.toggleMuteConversation(
          conversation.id,
          conversation.isMuted,
        ),
        onClearHistory: () =>
            _conversationProvider.clearConversationHistory(conversation.id),
        onMarkAsRead: () =>
            _conversationProvider.markAsRead(conversation.id, _currentUserId),
        onArchive: () => _conversationProvider.toggleArchiveConversation(
          conversation.id,
          _currentUserId,
          !conversation.archivedBy.contains(_currentUserId),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// [FIX P0] Đọc unreadCount an toàn — hỗ trợ cả định dạng int (cũ) và Map (mới)
  int _extractUnreadForUser(Map<String, dynamic> data) {
    final raw = data['unreadCount'];
    if (raw is int) return raw;
    if (raw is Map) {
      final v = raw[_currentUserId];
      return v is int ? v : 0;
    }
    return 0;
  }

  // [SỬA LỖI P1]: Bổ sung đầy đủ các định dạng tin nhắn game/địa điểm để không lọt JSON thô
  String _lastMessagePreview(String msg, int? type) {
    if (type == TypeMessage.image) return '📷 Ảnh';
    if (type == TypeMessage.sticker) return '😊 Sticker';
    if (type == TypeMessage.video) return '🎥 Video';
    if (type == TypeMessage.voice) return '🎵 Tin nhắn thoại';
    if (type == TypeMessage.document) return '📄 Tài liệu';
    if (type == TypeMessage.poll) return '📊 Bình chọn';
    if (type == TypeMessage.geoLocked) return '📍 Tin nhắn địa điểm';
    if (type == TypeMessage.gameInvite) return '🎮 Lời mời chơi game';
    if (type == TypeMessage.gameResult) return '🏆 Kết quả game';
    if (type == TypeMessage.gameLive) return '🎮 Đang chơi game';

    if (msg.isEmpty) return 'Bắt đầu cuộc trò chuyện';

    // Guard cuối cùng bảo vệ UI: Nếu phát hiện chuỗi có cấu trúc JSON hoặc mã hóa Base64 lọt lưới
    if (msg.startsWith('{') || (msg.startsWith('eyJ') && msg.length > 20)) {
      return '💬 Tin nhắn';
    }
    return msg;
  }

  // [+] Cache only stable (day+) formats; recent relative times computed fresh
  String _timeAgo(String timestamp) {
    if (timestamp.isEmpty || timestamp == '0') return '';
    try {
      final t = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
      final diff = DateTime.now().difference(t);

      if (diff.inDays > 6) {
        // Stable — cache indefinitely
        return _timeAgoCache.putIfAbsent(
          timestamp,
          () => DateFormat('d MMM').format(t),
        );
      }
      if (diff.inDays > 0) {
        // Stable within the same day — cache
        return _timeAgoCache.putIfAbsent(
          timestamp,
          () => DateFormat('EEE').format(t),
        );
      }
      // Recent — compute fresh (changes every minute/hour)
      if (diff.inHours > 0) return '${diff.inHours}g';
      if (diff.inMinutes > 0) return '${diff.inMinutes}ph';
      return 'vừa xong';
    } catch (_) {
      return '';
    }
  }

  String _userName() =>
      _authProvider.prefs.getString(FirestoreConstants.nickname) ?? 'there';

  String _userPhotoUrl() =>
      _authProvider.prefs.getString(FirestoreConstants.photoUrl) ?? '';

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

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    BubbleLifecycleObserver.instance.detach();
    WidgetsBinding.instance.removeObserver(this);
    _prefetchDebouncer?.cancel();
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

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storyProvider = context.read<StoryProvider>();
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _bg(isDark),
      body: Stack(
        children: [
          // ── Main layout ──────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // App bar — slide in from top
                SlideTransition(
                  position: _headerSlideAnim,
                  child: FadeTransition(
                    opacity: _headerFadeAnim,
                    child: _buildAppBar(isDark),
                  ),
                ),

                // Search bar — always pinned
                _buildSearchBar(isDark),

                // Scrollable body
                Expanded(
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      if (_textSearch.isEmpty) ...[
                        // [TÍCH HỢP BATCH 4]: Cảnh báo Quyền Bong bóng Chat (Banner)
                        SliverToBoxAdapter(
                          child: FadeTransition(
                            opacity: _filterAnim,
                            child: StreamBuilder<BubblePermissionStatus>(
                              stream:
                                  BubblePermissionService.instance.statusStream,
                              builder: (ctx, snap) {
                                final s =
                                    snap.data ??
                                    BubblePermissionService
                                        .instance
                                        .currentStatus;

                                // Nếu permission ok, hoặc bị block cứng bởi phần cứng -> không hiện Banner
                                if (s.isReady ||
                                    s.isHardBlocked ||
                                    s == BubblePermissionStatus.unknown) {
                                  return const SizedBox.shrink();
                                }

                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    12,
                                  ),
                                  child: BubblePermissionBanner(
                                    status: s,
                                    onTap: _handleBannerTap,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: FadeTransition(
                            opacity: _filterAnim,
                            child: _buildStoriesRow(storyProvider, isDark),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: FadeTransition(
                            opacity: _filterAnim,
                            child: _buildFilterChips(isDark),
                          ),
                        ),
                      ],
                      SliverToBoxAdapter(
                        child: _textSearch.isEmpty
                            ? _buildChatList(isDark)
                            : ColoredBox(
                                color: _surface(isDark),
                                child: _buildSearchResults(isDark),
                              ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(height: bottomPad + 130),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Loading overlay ──────────────────────────────────────────────
          if (_isLoading) const LoadingView(),

          // ── Bubble Dock ──────────────────────────────────────────────────
          _BubbleDock(
            currentUserId: _currentUserId,
            isDark: isDark,
            onBubbleTap: (bubble) {
              final ctrl = BubbleManager.of(context);
              ctrl?.showMiniChat(
                userId: bubble.userId,
                userName: bubble.userName,
                avatarUrl: bubble.avatarUrl,
              );
            },
            onBubbleLongPress: (bubble) async {
              final ctrl = BubbleManager.of(context);
              await ctrl?.hideBubble(bubble.userId);
              if (mounted) {
                Fluttertoast.showToast(
                  msg: '💬 Bubble off — ${bubble.userName}',
                  backgroundColor: Colors.grey.shade700,
                  textColor: Colors.white,
                );
              }
            },
            onSettingsTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BubbleSettingsPage()),
            ),
          ),

          // ── Compose FAB ──────────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: bottomPad + 80,
            child: ScaleTransition(
              scale: _fabScaleAnim,
              child: _ComposeButton(onTap: () => _push(FriendsPage())),
            ),
          ),

          // ── Scroll-to-top ────────────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            bottom: _showScrollToTop ? (bottomPad + 148) : -60,
            right: 20,
            child: _ScrollToTopButton(onTap: _scrollToTop),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // APP BAR
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildAppBar(bool isDark) {
    final photoUrl = _userPhotoUrl();
    final name = _userName();

    return Container(
      color: _surface(isDark),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _push(const SettingsPage()),
            child: _AvatarRing(photoUrl: photoUrl, name: name, isDark: isDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Tin nhắn',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: _primary(isDark),
                  ),
                ),
                const SizedBox(width: 8),
                StreamBuilder<QuerySnapshot>(
                  stream: _unreadCountStream,
                  builder: (_, snap) {
                    final count = snap.hasData
                        ? snap.data!.docs
                              .where(
                                (d) =>
                                    _extractUnreadForUser(
                                      d.data() as Map<String, dynamic>,
                                    ) >
                                    0,
                              )
                              .length
                        : 0;
                    if (count == 0) return const SizedBox.shrink();
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        key: ValueKey(count),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kAccent,
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
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Notification bell
          StreamBuilder<QuerySnapshot>(
            stream: _friendRequestsStream,
            builder: (_, snap) {
              final count = snap.hasData ? snap.data!.docs.length : 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  _NavBtn(
                    icon: Icons.notifications_outlined,
                    isDark: isDark,
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
          ),
          const SizedBox(width: 4),
          _NavBtn(
            icon: Icons.qr_code_scanner_rounded,
            isDark: isDark,
            tooltip: 'Quét QR',
            onTap: _scanQRCode,
          ),
          const SizedBox(width: 4),
          _buildMenuButton(isDark),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SEARCH BAR
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSearchBar(bool isDark) {
    return Container(
      color: _surface(isDark),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 42,
              decoration: BoxDecoration(
                color: _surface2(isDark),
                borderRadius: BorderRadius.circular(11),
                border: _isSearchFocused
                    ? Border.all(
                        color: _kAccent.withValues(alpha: 0.55),
                        width: 1.5,
                      )
                    : Border.all(color: Colors.transparent),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 11),
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: _isSearchFocused ? _kAccent : _secondary(isDark),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: _primary(isDark),
                        fontWeight: FontWeight.w400,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Tìm người, nhóm chat…',
                        hintStyle: TextStyle(
                          color: _secondary(isDark),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) {
                        _searchDebouncer.run(() {
                          if (!mounted) return;
                          _btnClearController.add(v.isNotEmpty);
                          if (v.isEmpty) {
                            // [+] Reset search stream cache on clear
                            setState(() {
                              _textSearch = '';
                              _searchLimit = 20;
                              _activeSearchStream = null;
                              _activeSearchKey = '';
                            });
                          } else {
                            setState(() {
                              _textSearch = v;
                              _searchLimit = 20;
                              // [+] Invalidate stale key so new stream is created
                              _activeSearchKey = '';
                            });
                          }
                        });
                      },
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: _btnClearController.stream,
                    builder: (_, snap) {
                      if (snap.data != true) {
                        return const SizedBox(width: 12);
                      }
                      return GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _btnClearController.add(false);
                          // [+] Also reset cached search stream
                          setState(() {
                            _textSearch = '';
                            _searchLimit = 20;
                            _activeSearchStream = null;
                            _activeSearchKey = '';
                          });
                          _searchFocusNode.unfocus();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Container(
                            width: 17,
                            height: 17,
                            decoration: BoxDecoration(
                              color: _secondary(isDark).withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 10,
                              color: isDark ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: _sep(isDark)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FILTER CHIPS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildFilterChips(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: _unreadCountStream,
      builder: (_, snap) {
        final unreadCount = snap.hasData
            ? snap.data!.docs
                  .where(
                    (d) =>
                        _extractUnreadForUser(
                          d.data() as Map<String, dynamic>,
                        ) >
                        0,
                  )
                  .length
            : 0;

        return Container(
          color: _bg(isDark),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: List.generate(_filterLabels.length, (i) {
              final active = _activeFilterIndex == i;
              final label = (i == 1 && unreadCount > 0)
                  ? '${_filterLabels[i]} $unreadCount'
                  : _filterLabels[i];

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    if (_activeFilterIndex == i) return;
                    HapticFeedback.selectionClick();
                    setState(() {
                      _activeFilterIndex = i;
                      _updateConversationsStream();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: active ? _kAccent : _surface2(isDark),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: active ? Colors.white : _secondary(isDark),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // STORIES ROW
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildStoriesRow(StoryProvider provider, bool isDark) {
    return Container(
      color: _surface(isDark),
      child: Column(
        children: [
          StreamBuilder<List<UserStories>>(
            stream: provider.getStoriesStream(
              currentUserId: _currentUserId,
              friendIds: _myFriendIds,
            ),
            builder: (ctx, snap) {
              final stories = snap.data ?? [];
              final hasStories = stories.isNotEmpty;

              if (!hasStories) {
                return _buildStoriesEmptyCompact(isDark);
              }

              return StoriesBar(
                storiesList: stories,
                currentUserId: _currentUserId,
                onAddStory: _openStoryCreator,
                onViewStories: (userStories) {
                  final others = stories
                      .where((s) => s.userId != _currentUserId)
                      .toList();
                  final idx = others.indexWhere(
                    (s) => s.userId == userStories.userId,
                  );
                  _push(
                    StoryViewerPage(
                      allUserStories: others.isNotEmpty ? others : stories,
                      initialUserIndex: idx < 0 ? 0 : idx,
                      currentUserId: _currentUserId,
                      currentUserName:
                          _authProvider.prefs.getString(
                            FirestoreConstants.nickname,
                          ) ??
                          '',
                      currentUserPhotoUrl:
                          _authProvider.prefs.getString(
                            FirestoreConstants.photoUrl,
                          ) ??
                          '',
                    ),
                  );
                },
              );
            },
          ),
          Divider(height: 1, thickness: 0.5, color: _sep(isDark)),
        ],
      ),
    );
  }

  Widget _buildStoriesEmptyCompact(bool isDark) {
    return GestureDetector(
      onTap: _openStoryCreator,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _kAccent.withValues(alpha: 0.4),
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
                color: _kAccent.withValues(alpha: 0.08),
              ),
              child: const Icon(Icons.add_rounded, color: _kAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Thêm story của bạn',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _primary(isDark),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Chia sẻ khoảnh khắc với bạn bè',
                    style: TextStyle(
                      fontSize: 12,
                      color: _secondary(isDark),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: _secondary(isDark).withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  void _openStoryCreator() {
    final prefs = _authProvider.prefs;
    _push(
      StoryCreatorPage(
        userId: _currentUserId,
        userName: prefs.getString(FirestoreConstants.nickname) ?? '',
        userPhotoUrl: prefs.getString(FirestoreConstants.photoUrl) ?? '',
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CHAT LIST
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildChatList(bool isDark) {
    if (_conversationsStream == null) {
      return ColoredBox(color: _surface(isDark), child: _buildSkeleton(isDark));
    }
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _conversationsStream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return ColoredBox(
            color: _surface(isDark),
            child: _buildSkeleton(isDark),
          );
        }
        final allDocs = snap.data ?? [];

        final activeDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final participants = List<String>.from(
            data['participants'] as List? ?? [],
          );
          return !participants.contains(AppConstants.aiAssistantId);
        }).toList();

        // [+] Only reschedule prefetch when the doc ID list actually changes
        final currentIds = activeDocs.map((d) => d.id).toList();
        if (!listEquals(currentIds, _lastPrefetchDocIds)) {
          _lastPrefetchDocIds = currentIds;
          _schedulePrefetch(activeDocs);
        }

        return ColoredBox(
          color: _surface(isDark),
          child: Column(
            children: [
              _buildAiItem(isDark),
              Divider(height: 0.5, indent: 72, color: _sep(isDark)),
              if (activeDocs.isEmpty)
                _buildEmptyState(isDark)
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // [+] We add our own RepaintBoundary; Flutter's defaults are redundant
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false,
                  itemCount: activeDocs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 0.5, indent: 72, color: _sep(isDark)),
                  itemBuilder: (_, i) =>
                      _buildConversationItem(activeDocs[i], isDark),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── AI Item ────────────────────────────────────────────────────────────────

  Widget _buildAiItem(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
            _push(
              ChatPage(
                arguments: ChatPageArguments(
                  peerId: AppConstants.aiAssistantId,
                  peerAvatar: AppConstants.aiAssistantAvatar,
                  peerNickname: AppConstants.aiAssistantName,
                ),
              ),
            );
          }
        },
        splashColor: const Color(0xFF7B61FF).withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _kAiGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          AppConstants.aiAssistantName,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: _primary(isDark),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: _kAiGradient,
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Được hỗ trợ bởi Gemini · Hỏi tôi bất cứ điều gì',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: _secondary(isDark),
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  // ── Conversation Item ──────────────────────────────────────────────────────

  Widget _buildConversationItem(DocumentSnapshot doc, bool isDark) {
    // [FIX P0] Đọc unreadCount an toàn TRƯỚC khi parse Conversation model
    final rawData = doc.data() as Map<String, dynamic>;
    final userUnread = _extractUnreadForUser(rawData);

    final conversation = Conversation.fromDocument(doc);

    if (conversation.isGroup) {
      final group = _groupCache[conversation.id];
      if (group == null && _isPrefetching) return _SkeletonTile(isDark: isDark);
      if (group == null) return const SizedBox.shrink();

      final tile = _ConversationTile(
        id: conversation.id,
        name: group.groupName,
        photoUrl: group.groupPhotoUrl,
        lastMessage: _lastMessagePreview(
          conversation.lastMessage ?? '',
          conversation.lastMessageType ?? 0,
        ),
        timeLabel: _timeAgo(conversation.lastMessageTime ?? ''),
        isPinned: conversation.isPinned,
        isMuted: conversation.isMuted,
        isGroup: true,
        isDark: isDark,
        unreadCount: userUnread,
        participants: conversation.participants,
        currentUserId: _currentUserId,
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

      // [+] RepaintBoundary isolates each tile's repaint layer
      return RepaintBoundary(
        child: _wrapWithSwipe(child: tile, conversation: conversation),
      );
    }

    final otherId = conversation.participants.firstWhere(
      (id) => id != _currentUserId,
      orElse: () => '',
    );
    if (otherId.isEmpty) return const SizedBox.shrink();

    final userChat = _userProfileCache[otherId];
    if (userChat == null && _isPrefetching)
      return _SkeletonTile(isDark: isDark);
    if (userChat == null) return const SizedBox.shrink();

    final tile = _ConversationTile(
      id: conversation.id,
      name: userChat.nickname,
      photoUrl: userChat.photoUrl,
      lastMessage: _lastMessagePreview(
        conversation.lastMessage ?? '',
        conversation.lastMessageType ?? 0,
      ),
      timeLabel: _timeAgo(conversation.lastMessageTime ?? ''),
      isPinned: conversation.isPinned,
      isMuted: conversation.isMuted,
      isGroup: false,
      isDark: isDark,
      onlineUserId: otherId,
      unreadCount: userUnread,
      isSentByMe: conversation.isSentByMe ?? false,
      isRead: conversation.isRead ?? false,
      participants: conversation.participants,
      currentUserId: _currentUserId,
      onTap: () {
        HapticFeedback.lightImpact();
        if (widget.isWebSidebar && widget.onChatSelected != null) {
          widget.onChatSelected!({
            'peerId': userChat.id,
            'peerAvatar': userChat.photoUrl,
            'peerNickname': userChat.nickname,
          });
        } else {
          _push(
            ChatPage(
              arguments: ChatPageArguments(
                peerId: userChat.id,
                peerAvatar: userChat.photoUrl,
                peerNickname: userChat.nickname,
              ),
            ),
          );
        }
      },
      onLongPress: () => _showConversationOptions(conversation),
    );

    // [+] RepaintBoundary isolates each tile's repaint layer
    return RepaintBoundary(
      child: _wrapWithSwipe(child: tile, conversation: conversation),
    );
  }

  // ── Search Results ─────────────────────────────────────────────────────────

  Widget _buildSearchResults(bool isDark) {
    final query = _textSearch.trim();

    return StreamBuilder<QuerySnapshot>(
      // [+] Use cached stream to avoid creating a new Firestore listener on every rebuild
      stream: _getSearchStream(query, _searchLimit),
      builder: (_, snap) {
        if (!snap.hasData) return _buildSkeleton(isDark);
        final docs = snap.data!.docs
            .where((d) => d.id != _currentUserId)
            .toList();
        if (docs.isEmpty) return _buildSearchEmpty(isDark);
        return Column(
          children: [
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              addAutomaticKeepAlives: false, // [+]
              addRepaintBoundaries: false, // [+]
              itemCount: docs.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 0.5, indent: 72, color: _sep(isDark)),
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
            ),
            if (_isLoadingMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kAccent,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Menu button ────────────────────────────────────────────────────────────

  Widget _buildMenuButton(bool isDark) {
    return PopupMenuButton<MenuSetting>(
      onSelected: _onMenuSelected,
      offset: const Offset(0, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1C1C22) : Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      itemBuilder: (_) => _menus.map((m) {
        final isLogout = m.title == 'Log out';
        return PopupMenuItem<MenuSetting>(
          value: m,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: _MenuItemRow(menu: m, isLogout: isLogout, isDark: isDark),
        );
      }).toList(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _surface2(isDark),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.more_vert_rounded,
          color: isDark
              ? Colors.white.withValues(alpha: 0.75)
              : const Color(0xFF3C3C43),
          size: 19,
        ),
      ),
    );
  }

  // ── Empty / skeleton states ────────────────────────────────────────────────

  Widget _buildSearchEmpty(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _surface2(isDark),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.search_off_rounded,
            size: 28,
            color: _secondary(isDark).withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Không tìm thấy "$_textSearch"',
          style: TextStyle(
            color: _primary(isDark),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Thử tìm kiếm bằng tên hoặc số điện thoại khác',
          style: TextStyle(color: _secondary(isDark), fontSize: 13.5),
        ),
      ],
    ),
  );

  Widget _buildEmptyState(bool isDark) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 44, 32, 48),
    child: Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kAccent, _kGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _kAccent.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.chat_bubble_outline_rounded,
            size: 36,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Chưa có cuộc trò chuyện nào',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: _primary(isDark),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Quét QR hoặc tìm kiếm theo tên\nđể bắt đầu trò chuyện',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _secondary(isDark),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _scanQRCode();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            decoration: BoxDecoration(
              color: _kAccent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 17,
                ),
                SizedBox(width: 8),
                Text(
                  'Quét mã QR',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildSkeleton(bool isDark) => ListView.separated(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    addAutomaticKeepAlives: false, // [+]
    itemCount: 8,
    separatorBuilder: (_, __) =>
        Divider(height: 0.5, indent: 72, color: _sep(isDark)),
    itemBuilder: (_, __) => _SkeletonTile(isDark: isDark),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// DECRYPTED TEXT WIDGET
// [+] NEW: StatefulWidget with a shared static cache to prevent repeated
//     decryption calls when the parent widget rebuilds. Previously, an inline
//     FutureBuilder would restart decryption on every parent rebuild, causing
//     flicker ("🔒 Đang giải mã...") and wasted async work.
// ════════════════════════════════════════════════════════════════════════════

class _DecryptedText extends StatefulWidget {
  final String cipherText;
  final String conversationId;
  final List<String> participants;
  final String currentUserId;
  final TextStyle style;
  final int maxChars;

  const _DecryptedText({
    required this.cipherText,
    required this.conversationId,
    required this.participants,
    required this.currentUserId,
    required this.style,
    this.maxChars = 44,
  });

  @override
  State<_DecryptedText> createState() => _DecryptedTextState();
}

class _DecryptedTextState extends State<_DecryptedText> {
  // Static cache shared across all list tiles; survives widget rebuilds
  static final Map<String, String> _cache = {};
  static const int _kMaxSize = 400;

  String? _result; // null → pending

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_DecryptedText old) {
    super.didUpdateWidget(old);
    // Re-decrypt if the message itself changed (e.g., conversation updated)
    if (old.cipherText != widget.cipherText ||
        old.conversationId != widget.conversationId) {
      _result = null;
      _resolve();
    }
  }

  // Short but unique key: conversationId + cipher hash
  String _cacheKey() =>
      '${widget.conversationId}_${widget.cipherText.hashCode}';

  void _resolve() {
    final k = _cacheKey();
    final cached = _cache[k];
    if (cached != null) {
      _result = cached; // Already done — no setState needed in initState
      return;
    }
    _decrypt(k);
  }

  // [SỬA LỖI P1]: Khắc phục việc cache chuỗi báo lỗi E2EE khiến app không retry lại khi kết nối / key ổn định
  Future<void> _decrypt(String k) async {
    try {
      final raw = await EncryptionService().decryptPayload(
        widget.cipherText,
        widget.conversationId,
        widget.participants,
        widget.currentUserId,
      );
      var display = raw;
      if (display.startsWith('{"iv":')) display = '🔒 Tin nhắn bảo mật';

      // Chuẩn hóa các chuỗi lỗi từ E2EEService về dạng thân thiện
      if (display.startsWith('🔒 [') || display.startsWith('⚠️ [')) {
        display = '🔒 Tin nhắn bảo mật';
      }

      // Chỉ cache khi giải mã thực sự thành công — không cache lỗi
      // để cho phép retry tự nhiên khi session key khả dụng sau này
      if (display != '🔒 Tin nhắn bảo mật') {
        // Evict oldest entries when cache grows too large
        if (_cache.length >= _kMaxSize) {
          final toRemove = _cache.keys.take(80).toList();
          for (final key in toRemove) _cache.remove(key);
        }
        _cache[k] = display;
      }

      if (mounted) setState(() => _result = display);
    } catch (_) {
      if (mounted) setState(() => _result = '🔒 Tin nhắn bảo mật');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _result ?? '🔒 Đang giải mã...';
    final display = text.length > widget.maxChars
        ? '${text.substring(0, widget.maxChars)}…'
        : text;
    return Text(
      display,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BUBBLE DOCK
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
    final unifiedBubbleService = context.read<UnifiedBubbleService>();

    return StreamBuilder<Map<String, BubbleData>>(
      stream: unifiedBubbleService.activeBubblesStream,
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
                  maxWidth: math.min(64.0 * bubbles.length + 96, 340),
                ),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.9),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: _kAccent.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 12),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: _kAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${bubbles.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...bubbles.map(
                        (b) => _BubbleAvatar(
                          bubble: b,
                          isDark: isDark,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            onBubbleTap(b);
                          },
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            onBubbleLongPress(b);
                          },
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onSettingsTap();
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.settings_rounded,
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade500,
                            size: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Bubble avatar ──────────────────────────────────────────────────────────

class _BubbleAvatar extends StatefulWidget {
  final BubbleData bubble;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BubbleAvatar({
    required this.bubble,
    required this.isDark,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_BubbleAvatar> createState() => _BubbleAvatarState();
}

class _BubbleAvatarState extends State<_BubbleAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bubble;
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundImage: b.avatarUrl.isNotEmpty
                    ? NetworkImage(b.avatarUrl)
                    : null,
                backgroundColor: _kAccent.withValues(alpha: 0.2),
                child: b.avatarUrl.isEmpty
                    ? Text(
                        b.userName.isNotEmpty
                            ? b.userName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: _kAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      )
                    : null,
              ),
              if (b.unreadCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(
                      minWidth: 15,
                      minHeight: 15,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      b.unreadCount > 9 ? '9+' : '${b.unreadCount}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: -1,
                right: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: b.isOnline ? _kGreen : Colors.grey.shade400,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.isDark
                          ? const Color(0xFF000000)
                          : Colors.white,
                      width: 1.5,
                    ),
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

// ════════════════════════════════════════════════════════════════════════════
// COMPOSE BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _ComposeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ComposeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _kAccent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _kAccent.withValues(alpha: 0.38),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PRIVATE SUB-WIDGETS
// ════════════════════════════════════════════════════════════════════════════

// ── Avatar ring ────────────────────────────────────────────────────────────

class _AvatarRing extends StatelessWidget {
  final String photoUrl, name;
  final bool isDark;
  const _AvatarRing({
    required this.photoUrl,
    required this.name,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ColorConstants.primaryColor.withValues(alpha: 0.12),
        border: Border.all(
          color: ColorConstants.primaryColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low, // [+] Faster decode
                errorBuilder: (_, __, ___) => _initials(),
              )
            : _initials(),
      ),
    );
  }

  Widget _initials() => Center(
    child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(
        color: ColorConstants.primaryColor,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    ),
  );
}

// ── Nav button ─────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback? onTap;
  final String? tooltip;

  const _NavBtn({
    required this.icon,
    required this.isDark,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: _surface2(isDark),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: isDark
            ? Colors.white.withValues(alpha: 0.75)
            : const Color(0xFF3C3C43),
        size: 19,
      ),
    );
    if (onTap == null) {
      return tooltip != null ? Tooltip(message: tooltip!, child: child) : child;
    }
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}

// ── Animated notification badge ────────────────────────────────────────────

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
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
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
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        shape: BoxShape.circle,
        border: Border.all(color: _surface(widget.isDark), width: 2),
      ),
      child: Center(
        child: Text(
          widget.count > 9 ? '9+' : '${widget.count}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

// ── Menu item row ──────────────────────────────────────────────────────────

class _MenuItemRow extends StatelessWidget {
  final MenuSetting menu;
  final bool isLogout, isDark;
  const _MenuItemRow({
    required this.menu,
    required this.isLogout,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isBubble = menu.title == 'Bubble Chat';
    final isArchive = menu.title == 'Archive';
    final color = isLogout
        ? Colors.red.shade500
        : isBubble
        ? _kGreen
        : isArchive
        ? _kOrange
        : _kAccent;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(menu.icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Text(
          menu.title,
          style: TextStyle(
            color: isLogout ? Colors.red.shade500 : _primary(isDark),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CONVERSATION TILE
// ════════════════════════════════════════════════════════════════════════════

class _ConversationTile extends StatelessWidget {
  final String id, name, photoUrl, lastMessage, timeLabel;
  final bool isPinned, isMuted, isGroup, isDark;
  final bool isAi;
  final String? onlineUserId;
  final int unreadCount;
  final bool isSentByMe;
  final bool isRead;
  final VoidCallback onTap, onLongPress;
  final List<String> participants;
  final String currentUserId;

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
    required this.participants,
    required this.currentUserId,
    this.onlineUserId,
    this.unreadCount = 0,
    this.isAi = false,
    this.isSentByMe = false,
    this.isRead = false,
  });

  // [SỬA LỖI P1]: Bổ sung prefix cho game, địa điểm để không phải render qua bộ giải mã hoặc Regex
  Widget _buildLastMessage(bool hasUnread) {
    final style = TextStyle(
      color: hasUnread
          ? _primary(isDark).withValues(alpha: 0.75)
          : _secondary(isDark),
      fontSize: 13.5,
      fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
    );

    // Media shorthand — emoji prefix detection
    if (lastMessage.startsWith('📷') ||
        lastMessage.startsWith('😊') ||
        lastMessage.startsWith('🎥') ||
        lastMessage.startsWith('🎵') ||
        lastMessage.startsWith('📄') ||
        lastMessage.startsWith('📊') ||
        lastMessage.startsWith('🎮') ||
        lastMessage.startsWith('🏆') ||
        lastMessage.startsWith('📍') ||
        lastMessage.startsWith('🔒') ||
        lastMessage.startsWith('💬')) {
      return Text(lastMessage, style: style);
    }

    // [+] Use _DecryptedText (StatefulWidget with static cache) instead of
    //     an inline FutureBuilder, preventing restart on every parent rebuild
    if (EncryptionService().isEncrypted(lastMessage)) {
      return _DecryptedText(
        cipherText: lastMessage,
        conversationId: id,
        participants: participants,
        currentUserId: currentUserId,
        style: style,
      );
    }

    // Plain-text pattern matching
    String displayText = lastMessage;
    if (displayText.startsWith('{"iv":') || displayText.startsWith('eyJ')) {
      displayText = '🔒 Tin nhắn bảo mật';
    } else if (displayText.startsWith('{"type":"group_call_') ||
        displayText.startsWith('{"type":"call_')) {
      if (displayText.contains('ended'))
        displayText = '📞 Cuộc gọi đã kết thúc';
      else if (displayText.contains('missed'))
        displayText = '📞 Cuộc gọi nhỡ';
      else
        displayText = '📞 Cuộc gọi';
    } else if (displayText.startsWith('{"board":')) {
      displayText = '🎮 Lời mời game Caro';
    } else if (displayText.startsWith('{"question":')) {
      displayText = '📊 Bình chọn';
    }

    return Text(
      displayText.length > 44
          ? '${displayText.substring(0, 44)}…'
          : displayText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0 && !isMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: _kAccent.withValues(alpha: 0.05),
        highlightColor: _kAccent.withValues(alpha: 0.02),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          color: isPinned
              ? _kAccent.withValues(alpha: isDark ? 0.05 : 0.04)
              : null,
          child: Row(
            children: [
              // Avatar
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
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
                        // [+] RepaintBoundary so online-dot stream rebuilds
                        //     don't dirty the rest of the tile
                        child: RepaintBoundary(
                          child: _OnlineDot(userId: onlineUserId!),
                        ),
                      ),
                    if (isMuted)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _surface(isDark),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _surface(isDark),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.volume_off_rounded,
                            size: 9,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Text block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (isPinned) ...[
                          Icon(
                            Icons.push_pin_rounded,
                            size: 10,
                            color: _kAccent.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _primary(isDark),
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 15.5,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            color: hasUnread ? _kAccent : _secondary(isDark),
                            fontSize: 11.5,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (!isGroup && isSentByMe && !hasUnread) ...[
                          Icon(
                            isRead
                                ? Icons.done_all_rounded
                                : Icons.done_rounded,
                            size: 14,
                            color: isRead
                                ? _kAccent
                                : _secondary(isDark).withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(child: _buildLastMessage(hasUnread)),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _UnreadChip(count: unreadCount),
                        ],
                        if (isMuted && !hasUnread)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.volume_off_rounded,
                              size: 13,
                              color: _secondary(isDark).withValues(alpha: 0.5),
                            ),
                          ),
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

// ── Unread chip ────────────────────────────────────────────────────────────

class _UnreadChip extends StatelessWidget {
  final int count;
  const _UnreadChip({required this.count});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: _kAccent,
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

// ════════════════════════════════════════════════════════════════════════════
// AVATAR
// ════════════════════════════════════════════════════════════════════════════

class _Avatar extends StatelessWidget {
  final String photoUrl, name;
  final double size;
  final bool isDark, isGroup, isAi;

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
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _kAiGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: Colors.white,
          size: 24,
        ),
      );
    }

    final colorIdx = name.isEmpty
        ? 0
        : name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIdx];
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    // [+] cacheWidth/cacheHeight reduce decoded image memory proportionally
    final cacheSize = (size * 2).toInt(); // 2× for high-DPI

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColor.withValues(alpha: 0.12),
        border: Border.all(
          color: avatarColor.withValues(alpha: 0.18),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low, // [+] Faster GPU path
                cacheWidth: cacheSize, // [+] Reduced memory footprint
                cacheHeight: cacheSize,
                errorBuilder: (_, __, ___) => _fallback(initials, avatarColor),
              )
            : _fallback(initials, avatarColor),
      ),
    );
  }

  Widget _fallback(String text, Color color) {
    if (isGroup) {
      return Container(
        color: color.withValues(alpha: 0.1),
        child: Icon(Icons.group_rounded, color: color, size: size * 0.42),
      );
    }
    return Container(
      color: color.withValues(alpha: 0.1),
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
            color: _kGreen,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).scaffoldBackgroundColor,
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SEARCH RESULT TILE
// ════════════════════════════════════════════════════════════════════════════

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
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      splashColor: _kAccent.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      color: _primary(isDark),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (userChat.phoneNumber.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '📱 ${userChat.phoneNumber}',
                        style: TextStyle(
                          color: _secondary(isDark),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  if (userChat.aboutMe.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        userChat.aboutMe,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _secondary(isDark).withValues(alpha: 0.7),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _kAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Xem',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: _kAccent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _kAccent.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.keyboard_arrow_up_rounded,
        color: Colors.white,
        size: 22,
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// SKELETON TILE
// Shimmer animation per-tile with bounded AnimationController.
// Each tile independently animates so the list never stalls.
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) {
      final base = widget.isDark
          ? Color.lerp(
              const Color(0xFF1C1C22),
              const Color(0xFF2C2C34),
              _anim.value,
            )!
          : Color.lerp(
              const Color(0xFFF2F2F7),
              const Color(0xFFE5E5EA),
              _anim.value,
            )!;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: base, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 13,
                    width: 110 + (_anim.value * 30),
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 11,
                    width: 160 + (_anim.value * 20),
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              height: 10,
              width: 26,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ],
        ),
      );
    },
  );
}

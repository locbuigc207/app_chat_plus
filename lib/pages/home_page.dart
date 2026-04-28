import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/utils/utils.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State createState() => HomePageState();
}

class HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _firebaseMessaging = FirebaseMessaging.instance;
  final _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  final _listScrollController = ScrollController();

  bool _isLoading = false;
  String _textSearch = '';
  int _limit = 20;
  final _limitIncrement = 20;

  late final _authProvider = context.read<AuthProvider>();
  late final _homeProvider = context.read<HomeProvider>();
  late final String _currentUserId;
  late final FriendProvider _friendProvider;
  late final ConversationProvider _conversationProvider;

  List<String> _myFriendIds = [];
  StreamSubscription<QuerySnapshot>? _friendIdsSubscription;

  final _searchDebouncer = Debouncer(milliseconds: 300);
  final _btnClearController = StreamController<bool>();
  final _searchBarController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;

  late final List<MenuSetting> _menus;
  StreamSubscription<QuerySnapshot>? _conversationsSubscription;

  late AnimationController _fabAnimController;
  late Animation<double> _fabScaleAnim;

  @override
  void initState() {
    super.initState();

    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabScaleAnim = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.elasticOut,
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _fabAnimController.forward();
    });

    _searchFocusNode.addListener(() {
      if (mounted) {
        setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
      }
    });

    if (_authProvider.userFirebaseId?.isNotEmpty == true) {
      _currentUserId = _authProvider.userFirebaseId!;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginPage()),
          (_) => false,
        );
      });
      return;
    }

    _friendProvider = FriendProvider(
      firebaseFirestore: _homeProvider.firebaseFirestore,
    );
    _conversationProvider = ConversationProvider(
      firebaseFirestore: _homeProvider.firebaseFirestore,
    );

    _menus = [
      const MenuSetting(title: 'Friends', icon: Icons.people_outline_rounded),
      const MenuSetting(title: 'My Status', icon: Icons.auto_stories_rounded),
      const MenuSetting(title: 'Call History', icon: Icons.call_outlined),
      const MenuSetting(title: 'Settings', icon: Icons.settings_outlined),
      const MenuSetting(title: 'Theme', icon: Icons.palette_outlined),
      const MenuSetting(title: 'My QR Code', icon: Icons.qr_code_2_rounded),
      const MenuSetting(title: 'Create Group', icon: Icons.group_add_outlined),
      const MenuSetting(title: 'Log out', icon: Icons.logout_rounded),
    ];

    _registerNotification();
    _configLocalNotification();
    _listScrollController.addListener(_scrollListener);
    _listenToFriendIds();
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    _searchFocusNode.dispose();
    _btnClearController.close();
    _searchBarController.dispose();
    _listScrollController
      ..removeListener(_scrollListener)
      ..dispose();
    _friendIdsSubscription?.cancel();
    _conversationsSubscription?.cancel();
    super.dispose();
  }

  void _listenToFriendIds() {
    final fs = _homeProvider.firebaseFirestore
        .collection(FirestoreConstants.pathFriendshipCollection);

    _friendIdsSubscription = fs
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

      if (mounted) {
        setState(() {
          // Giới hạn tối đa 9 id để query whereIn không bị lỗi
          _myFriendIds = ids.take(9).toList();
        });
      }
    });
  }

  void _registerNotification() {
    _firebaseMessaging.requestPermission();
    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null) {
        _showNotification(message.notification!);
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
    const initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    const initializationSettingsIOS = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _scrollListener() {
    if (_listScrollController.offset >=
            _listScrollController.position.maxScrollExtent &&
        !_listScrollController.position.outOfRange) {
      setState(() => _limit += _limitIncrement);
    }
  }

  void _onItemMenuPress(MenuSetting choice) {
    final prefs = _authProvider.prefs;
    switch (choice.title) {
      case 'Log out':
        _handleSignOut();
        break;
      case 'Friends':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => FriendsPage()));
        break;
      case 'Call History':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    CallHistoryPage(currentUserId: _currentUserId)));
        break;
      case 'My QR Code':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const MyQRCodePage()));
        break;
      case 'Create Group':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => CreateGroupPage()));
        break;
      case 'Theme':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ThemeSettingsPage()));
        break;
      case 'My Status':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MyStoriesPage(
              userId: _currentUserId,
              userName: prefs.getString(FirestoreConstants.nickname) ?? '',
              userPhotoUrl: prefs.getString(FirestoreConstants.photoUrl) ?? '',
            ),
          ),
        );
        break;
      default:
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SettingsPage()));
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
      if (userDoc != null) {
        final userChat = UserChat.fromDocument(userDoc);
        if (userChat.id == _currentUserId) {
          Fluttertoast.showToast(msg: "This is your QR code!");
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserProfilePage(userChat: userChat),
            ),
          );
        }
      } else {
        Fluttertoast.showToast(msg: "User not found");
      }
    }
  }

  String _getLastMessagePreview(String message, int type) {
    if (type == TypeMessage.image) return '📷 Photo';
    if (type == TypeMessage.sticker) return '😊 Sticker';
    if (message.isEmpty) return 'Start a conversation';
    return message.length > 40 ? '${message.substring(0, 40)}…' : message;
  }

  String _getTimeAgo(String timestamp) {
    try {
      final messageTime =
          DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
      final now = DateTime.now();
      final diff = now.difference(messageTime);
      if (diff.inDays > 6) return DateFormat('MMM dd').format(messageTime);
      if (diff.inDays > 0) return DateFormat('EEE').format(messageTime);
      if (diff.inHours > 0) return '${diff.inHours}h';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m';
      return 'now';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.read<StoryProvider>();

    return Scaffold(
      backgroundColor: isDark
          ? ColorConstants.backgroundDark
          : ColorConstants.backgroundLight,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(isDark),
                _buildSearchBar(isDark),
                if (_textSearch.isEmpty) ...[
                  _buildStoriesSection(provider, isDark),
                  _buildOnlineFriendsSection(isDark),
                ],
                Expanded(
                  child: _textSearch.isEmpty
                      ? _buildConversationList(isDark)
                      : _buildSearchResults(isDark),
                ),
              ],
            ),
            if (_isLoading) LoadingView(),
          ],
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnim,
        child: FloatingActionButton(
          onPressed: _scanQRCode,
          backgroundColor: ColorConstants.primaryColor,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.qr_code_scanner_rounded,
              color: Colors.white, size: 26),
        ),
      ),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return Container(
      color: isDark ? ColorConstants.surfaceDark : Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Messages',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: isDark
                            ? const Color(0xFFF0F2F8)
                            : const Color(0xFF1A1D2E),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Stay connected',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ColorConstants.greyColor,
                      ),
                ),
              ],
            ),
          ),
          _buildNotificationBadge(isDark),
          const SizedBox(width: 4),
          _buildMenuButton(isDark),
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
      builder: (_, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _HeaderIconButton(
              icon: Icons.notifications_outlined,
              isDark: isDark,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NotificationsPage())),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: ColorConstants.accentRed,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? ColorConstants.surfaceDark : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMenuButton(bool isDark) {
    return PopupMenuButton<MenuSetting>(
      onSelected: _onItemMenuPress,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      color: isDark ? ColorConstants.surfaceDark2 : Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.12),
      itemBuilder: (_) {
        return _menus.map((choice) {
          final isLogout = choice.title == 'Log out';
          return PopupMenuItem<MenuSetting>(
            value: choice,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isLogout
                        ? ColorConstants.accentRed.withOpacity(0.1)
                        : ColorConstants.primaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    choice.icon,
                    color: isLogout
                        ? ColorConstants.accentRed
                        : ColorConstants.primaryColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  choice.title,
                  style: TextStyle(
                    color: isLogout
                        ? ColorConstants.accentRed
                        : (isDark
                            ? const Color(0xFFF0F2F8)
                            : const Color(0xFF1A1D2E)),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color:
              isDark ? ColorConstants.surfaceDark2 : ColorConstants.greyColor2,
        ),
        child: Icon(
          Icons.more_vert_rounded,
          color: isDark ? Colors.white70 : ColorConstants.primaryColor,
          size: 20,
        ),
      ),
    );
  }

  // ── SEARCH BAR ─────────────────────────────────────────────
  Widget _buildSearchBar(bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: isDark ? ColorConstants.surfaceDark : Colors.white,
      padding: EdgeInsets.fromLTRB(16, 0, 16, _isSearchFocused ? 12 : 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color:
              isDark ? ColorConstants.surfaceDark2 : ColorConstants.greyColor2,
          borderRadius: BorderRadius.circular(14),
          border: _isSearchFocused
              ? Border.all(
                  color: ColorConstants.primaryColor.withOpacity(0.5),
                  width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(
              Icons.search_rounded,
              color: _isSearchFocused
                  ? ColorConstants.primaryColor
                  : ColorConstants.greyColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _searchBarController,
                focusNode: _searchFocusNode,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                  fontWeight: FontWeight.w400,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone...',
                  hintStyle: const TextStyle(
                    color: ColorConstants.greyColor,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (value) {
                  _searchDebouncer.run(() {
                    if (value.isNotEmpty) {
                      _btnClearController.add(true);
                      setState(() => _textSearch = value);
                    } else {
                      _btnClearController.add(false);
                      setState(() => _textSearch = '');
                    }
                  });
                },
              ),
            ),
            StreamBuilder<bool>(
              stream: _btnClearController.stream,
              builder: (_, snapshot) {
                if (snapshot.data != true) return const SizedBox(width: 12);
                return GestureDetector(
                  onTap: () {
                    _searchBarController.clear();
                    _btnClearController.add(false);
                    setState(() => _textSearch = '');
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: ColorConstants.greyColor.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── STORIES SECTION ────────────────────────────────────────
  Widget _buildStoriesSection(StoryProvider provider, bool isDark) {
    return Container(
      color: isDark ? ColorConstants.surfaceDark : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          StreamBuilder<List<UserStories>>(
            stream: provider.getStoriesStream(
              currentUserId: _currentUserId,
              friendIds: _myFriendIds,
            ),
            builder: (context, snapshot) {
              final stories = snapshot.data ?? [];
              return StoriesBar(
                storiesList: stories,
                currentUserId: _currentUserId,
                onAddStory: _openStoryCreator,
                onViewStories: (userStories) {
                  final allOthers =
                      stories.where((s) => s.userId != _currentUserId).toList();
                  final userIndex = allOthers
                      .indexWhere((s) => s.userId == userStories.userId);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoryViewerPage(
                        allUserStories:
                            allOthers.isNotEmpty ? allOthers : stories,
                        initialUserIndex: userIndex < 0 ? 0 : userIndex,
                        currentUserId: _currentUserId,
                        currentUserName: _authProvider.prefs
                                .getString(FirestoreConstants.nickname) ??
                            '',
                        currentUserPhotoUrl: _authProvider.prefs
                                .getString(FirestoreConstants.photoUrl) ??
                            '',
                      ),
                    ),
                  );
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryCreatorPage(
          userId: _currentUserId,
          userName: prefs.getString(FirestoreConstants.nickname) ?? '',
          userPhotoUrl: prefs.getString(FirestoreConstants.photoUrl) ?? '',
        ),
      ),
    );
  }

  // ── ONLINE FRIENDS SECTION ──────────────────────────────────
  Widget _buildOnlineFriendsSection(bool isDark) {
    return Container(
      color: isDark ? ColorConstants.surfaceDark : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.people,
                    size: 20, color: ColorConstants.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Online Friends',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: ColorConstants.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          OnlineFriendsBar(currentUserId: _currentUserId),
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }

  // ── CONVERSATION LIST ──────────────────────────────────────
  Widget _buildConversationList(bool isDark) {
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _conversationProvider.getConversationsWithPinned(_currentUserId),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildListSkeleton(isDark);
        }
        final conversations = snapshot.data ?? [];
        if (conversations.isEmpty) {
          return _buildEmptyState(isDark);
        }
        return ListView.builder(
          controller: _listScrollController,
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          itemCount: conversations.length,
          itemBuilder: (_, i) =>
              _buildConversationItem(conversations[i], isDark),
        );
      },
    );
  }

  Widget _buildListSkeleton(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: 8,
      itemBuilder: (_, i) => _SkeletonConversationItem(isDark: isDark),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: ColorConstants.primaryColor.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 46,
                color: ColorConstants.primaryColor.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No conversations yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: isDark ? Colors.white70 : const Color(0xFF1A1D2E),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a QR code to connect with friends\nand start chatting',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ColorConstants.greyColor,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _scanQRCode,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text('Scan QR Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ColorConstants.primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationItem(DocumentSnapshot? doc, bool isDark) {
    if (doc == null) return const SizedBox.shrink();
    final conversation = Conversation.fromDocument(doc);

    if (conversation.isGroup) {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection(FirestoreConstants.pathGroupCollection)
            .doc(conversation.id)
            .get(),
        builder: (_, snapshot) {
          if (!snapshot.hasData) {
            return _SkeletonConversationItem(isDark: isDark);
          }
          final group = Group.fromDocument(snapshot.data!);
          return _ConversationTile(
            id: conversation.id,
            name: group.groupName,
            photoUrl: group.groupPhotoUrl,
            lastMessage: _getLastMessagePreview(
              conversation.lastMessage,
              conversation.lastMessageType,
            ),
            timeLabel: _getTimeAgo(conversation.lastMessageTime),
            isPinned: conversation.isPinned,
            isMuted: conversation.isMuted,
            isGroup: true,
            isDark: isDark,
            onTap: () => Navigator.push(
              context,
              _slideRoute(GroupChatPage(group: group)),
            ),
            onLongPress: () => _showConversationOptions(conversation),
          );
        },
      );
    }

    final otherUserId = conversation.participants
        .firstWhere((id) => id != _currentUserId, orElse: () => '');
    if (otherUserId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection(FirestoreConstants.pathUserCollection)
          .doc(otherUserId)
          .get(),
      builder: (_, snapshot) {
        if (!snapshot.hasData) {
          return _SkeletonConversationItem(isDark: isDark);
        }
        final userChat = UserChat.fromDocument(snapshot.data!);
        return _ConversationTile(
          id: conversation.id,
          name: userChat.nickname,
          photoUrl: userChat.photoUrl,
          lastMessage: _getLastMessagePreview(
            conversation.lastMessage,
            conversation.lastMessageType,
          ),
          timeLabel: _getTimeAgo(conversation.lastMessageTime),
          isPinned: conversation.isPinned,
          isMuted: conversation.isMuted,
          isGroup: false,
          isDark: isDark,
          onlineUserId: otherUserId,
          onTap: () => Navigator.push(
            context,
            _slideRoute(ChatPage(
              arguments: ChatPageArguments(
                peerId: userChat.id,
                peerAvatar: userChat.photoUrl,
                peerNickname: userChat.nickname,
              ),
            )),
          ),
          onLongPress: () => _showConversationOptions(conversation),
        );
      },
    );
  }

  // ── SEARCH RESULTS ─────────────────────────────────────────
  Widget _buildSearchResults(bool isDark) {
    final query = _textSearch.trim();
    final isPhoneNumber = RegExp(r'^[+\d][\d\s-]*$').hasMatch(query);

    Stream<QuerySnapshot> stream;

    if (isPhoneNumber) {
      stream = _homeProvider.firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.phoneNumber, isEqualTo: query)
          .limit(_limit)
          .snapshots();
    } else {
      stream = _homeProvider.firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.nickname, isGreaterThanOrEqualTo: query)
          .where(FirestoreConstants.nickname,
              isLessThanOrEqualTo: '$query\uf8ff')
          .limit(_limit)
          .snapshots();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (_, snapshot) {
        if (!snapshot.hasData) return _buildListSkeleton(isDark);
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off_rounded,
                    size: 56, color: ColorConstants.greyColor.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text('No results for "$_textSearch"',
                    style: TextStyle(
                        color: ColorConstants.greyColor, fontSize: 15)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final userChat = UserChat.fromDocument(docs[i]);
            if (userChat.id == _currentUserId) return const SizedBox.shrink();
            return _buildSearchResultTile(userChat, isDark);
          },
        );
      },
    );
  }

  Widget _buildSearchResultTile(UserChat userChat, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          _slideRoute(UserProfilePage(userChat: userChat)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _UserAvatar(
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
                        color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (userChat.phoneNumber.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '📱 ${userChat.phoneNumber}',
                        style: const TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (userChat.aboutMe.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        userChat.aboutMe,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ColorConstants.primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'View',
                  style: TextStyle(
                    color: ColorConstants.primaryColor,
                    fontSize: 12,
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

  void _showConversationOptions(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ConversationOptionsDialog(
        isPinned: conversation.isPinned,
        isMuted: conversation.isMuted,
        onPin: () => _conversationProvider.togglePinConversation(
            conversation.id, conversation.isPinned),
        onMute: () => _conversationProvider.toggleMuteConversation(
            conversation.id, conversation.isMuted),
        onClearHistory: () =>
            _conversationProvider.clearConversationHistory(conversation.id),
        onMarkAsRead: () {},
      ),
    );
  }

  PageRoute _slideRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, __) => page,
      transitionsBuilder: (_, animation, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 280),
    );
  }

  void _showNotification(RemoteNotification remoteNotification) async {
    final androidDetails = AndroidNotificationDetails(
      Platform.isAndroid
          ? 'com.dfa.flutterchatdemo'
          : 'com.duytq.flutterchatdemo',
      'Flutter chat demo',
      playSound: true,
      enableVibration: true,
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    final details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _flutterLocalNotificationsPlugin.show(
      0,
      remoteNotification.title,
      remoteNotification.body,
      details,
    );
  }
}

// ── SUPPORTING WIDGETS ─────────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color:
              isDark ? ColorConstants.surfaceDark2 : ColorConstants.greyColor2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isDark ? Colors.white70 : ColorConstants.primaryColor,
          size: 20,
        ),
      ),
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
  final String? onlineUserId;
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
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isPinned
                ? ColorConstants.primaryColor.withOpacity(isDark ? 0.06 : 0.04)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              // Avatar
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _UserAvatar(
                    photoUrl: photoUrl,
                    name: name,
                    size: 52,
                    isDark: isDark,
                    isGroup: isGroup,
                  ),
                  if (onlineUserId != null)
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: _OnlineDot(userId: onlineUserId!),
                    ),
                  if (isMuted)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: isDark
                              ? ColorConstants.surfaceDark
                              : Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.volume_off_rounded,
                            size: 11, color: ColorConstants.greyColor),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isPinned) ...[
                          const Icon(Icons.push_pin_rounded,
                              size: 13, color: ColorConstants.primaryColor),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1D2E),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            color: ColorConstants.greyColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            isDark ? Colors.white38 : ColorConstants.greyColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
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

class _UserAvatar extends StatelessWidget {
  final String photoUrl;
  final String name;
  final double size;
  final bool isDark;
  final bool isGroup;

  const _UserAvatar({
    required this.photoUrl,
    required this.name,
    required this.size,
    required this.isDark,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorIndex = name.isEmpty
        ? 0
        : name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIndex];
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColor.withOpacity(0.15),
        border: Border.all(
          color: avatarColor.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _buildInitials(initials, avatarColor, isGroup, size),
              )
            : _buildInitials(initials, avatarColor, isGroup, size),
      ),
    );
  }

  Widget _buildInitials(
      String initials, Color color, bool isGroup, double size) {
    if (isGroup) {
      return Container(
        color: color.withOpacity(0.15),
        child: Icon(
          Icons.group_rounded,
          color: color,
          size: size * 0.45,
        ),
      );
    }
    return Container(
      color: color.withOpacity(0.15),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.36,
          ),
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
    return StreamBuilder<Map<String, dynamic>>(
      stream: presenceProvider.getUserOnlineStatus(userId),
      builder: (_, snap) {
        final isOnline = snap.data?['isOnline'] as bool? ?? false;
        if (!isOnline) return const SizedBox.shrink();
        return Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: ColorConstants.accentGreen,
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

class _SkeletonConversationItem extends StatefulWidget {
  final bool isDark;
  const _SkeletonConversationItem({required this.isDark});

  @override
  State<_SkeletonConversationItem> createState() =>
      _SkeletonConversationItemState();
}

class _SkeletonConversationItemState extends State<_SkeletonConversationItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) {
        final base = widget.isDark
            ? Color.lerp(ColorConstants.surfaceDark2, const Color(0xFF2E3448),
                _animation.value)!
            : Color.lerp(ColorConstants.greyColor2, const Color(0xFFE0E4F0),
                _animation.value)!;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: base,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: 120,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 11,
                      width: 180,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 10,
                width: 32,
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
}

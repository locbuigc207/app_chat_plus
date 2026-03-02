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

class HomePageState extends State<HomePage> {
  final _firebaseMessaging = FirebaseMessaging.instance;
  final _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  final _listScrollController = ScrollController();

  bool _isLoading = false;
  bool _isSearching = false;
  String _textSearch = "";
  int _limit = 20;
  final _limitIncrement = 20;

  late final _authProvider = context.read<AuthProvider>();
  late final _homeProvider = context.read<HomeProvider>();
  late final String _currentUserId;
  late final FriendProvider _friendProvider;
  late final ConversationProvider _conversationProvider;

  final _searchDebouncer = Debouncer(milliseconds: 300);
  final _btnClearController = StreamController<bool>();
  final _searchBarController = TextEditingController();

  late final List<MenuSetting> _menus;

  StreamSubscription<QuerySnapshot>? _conversationsSubscription;
  StreamSubscription<QuerySnapshot>? _friendRequestsSubscription;

  @override
  void initState() {
    super.initState();

    if (_authProvider.userFirebaseId?.isNotEmpty == true) {
      _currentUserId = _authProvider.userFirebaseId!;
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginPage()),
        (_) => false,
      );
    }

    _friendProvider =
        FriendProvider(firebaseFirestore: _homeProvider.firebaseFirestore);
    _conversationProvider = ConversationProvider(
        firebaseFirestore: _homeProvider.firebaseFirestore);

    _menus = [
      const MenuSetting(title: 'Friends', icon: Icons.people),
      const MenuSetting(title: 'Settings', icon: Icons.settings),
      const MenuSetting(title: 'Theme', icon: Icons.palette),
      const MenuSetting(title: 'My QR Code', icon: Icons.qr_code),
      const MenuSetting(title: 'Create Group', icon: Icons.group_add),
      const MenuSetting(title: 'Log out', icon: Icons.exit_to_app),
    ];

    _registerNotification();
    _configLocalNotification();
    _listScrollController.addListener(_scrollListener);
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
      setState(() {
        _limit += _limitIncrement;
      });
    }
  }

  Widget _buildPopupMenu() {
    return PopupMenuButton<MenuSetting>(
      onSelected: _onItemMenuPress,
      itemBuilder: (_) {
        return _menus.map((choice) {
          return PopupMenuItem<MenuSetting>(
            value: choice,
            child: Row(
              children: [
                Icon(choice.icon, color: ColorConstants.primaryColor),
                const SizedBox(width: 10),
                Text(choice.title,
                    style: const TextStyle(color: ColorConstants.primaryColor)),
              ],
            ),
          );
        }).toList();
      },
    );
  }

  void _onItemMenuPress(MenuSetting choice) {
    switch (choice.title) {
      case 'Log out':
        _handleSignOut();
        break;
      case 'Friends':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FriendsPage()),
        );
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

  // 🎯 NEW: Smart Search Bar with auto-detection
  Widget _buildSmartSearchBar() {
    return Container(
      height: 40,
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: ColorConstants.greyColor2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 10),
          const Icon(Icons.search, color: ColorConstants.greyColor, size: 20),
          const SizedBox(width: 5),
          Expanded(
            child: TextFormField(
              controller: _searchBarController,
              onChanged: (value) {
                _searchDebouncer.run(() {
                  if (value.isNotEmpty) {
                    _btnClearController.add(true);
                    setState(() => _textSearch = value);
                  } else {
                    _btnClearController.add(false);
                    setState(() => _textSearch = "");
                  }
                });
              },
              decoration: const InputDecoration.collapsed(
                hintText: 'Search by name or phone...',
                hintStyle:
                    TextStyle(fontSize: 13, color: ColorConstants.greyColor),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          StreamBuilder<bool>(
            stream: _btnClearController.stream,
            builder: (_, snapshot) {
              return snapshot.data == true
                  ? GestureDetector(
                      onTap: () {
                        _searchBarController.clear();
                        _btnClearController.add(false);
                        setState(() => _textSearch = "");
                      },
                      child: const Icon(Icons.clear,
                          color: ColorConstants.greyColor, size: 20),
                    )
                  : const SizedBox.shrink();
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _buildOnlineFriendsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.people,
                size: 20,
                color: ColorConstants.primaryColor,
              ),
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
        Divider(height: 1, thickness: 1),
      ],
    );
  }

  String _getLastMessagePreview(String message, int type) {
    if (type == TypeMessage.image) return '📷 Image';
    if (type == TypeMessage.sticker) return '😊 Sticker';
    return message.length > 30 ? '${message.substring(0, 30)}...' : message;
  }

  String _getTimeAgo(String timestamp) {
    try {
      final messageTime =
          DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
      final now = DateTime.now();
      final diff = now.difference(messageTime);

      if (diff.inDays > 0) {
        return DateFormat('MMM dd').format(messageTime);
      } else if (diff.inHours > 0) {
        return '${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (_) {
      return '';
    }
  }

  void _showConversationOptions(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ConversationOptionsDialog(
        isPinned: conversation.isPinned,
        isMuted: conversation.isMuted,
        onPin: () => _togglePinConversation(conversation),
        onMute: () => _toggleMuteConversation(conversation),
        onClearHistory: () => _clearConversationHistory(conversation.id),
        onMarkAsRead: () {
          Fluttertoast.showToast(msg: 'Mark as read');
        },
      ),
    );
  }

  Future<void> _togglePinConversation(Conversation conversation) async {
    final success = await _conversationProvider.togglePinConversation(
      conversation.id,
      conversation.isPinned,
    );
    if (success) {
      Fluttertoast.showToast(
        msg: conversation.isPinned
            ? 'Conversation unpinned'
            : 'Conversation pinned',
      );
    }
  }

  Future<void> _toggleMuteConversation(Conversation conversation) async {
    final success = await _conversationProvider.toggleMuteConversation(
      conversation.id,
      conversation.isMuted,
    );
    if (success) {
      Fluttertoast.showToast(
        msg: conversation.isMuted
            ? 'Conversation unmuted'
            : 'Conversation muted',
      );
    }
  }

  Future<void> _clearConversationHistory(String conversationId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear History'),
        content: Text(
          'Are you sure you want to clear all messages in this conversation?\n\nThis will not affect your friendship status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
            child: Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      final success =
          await _conversationProvider.clearConversationHistory(conversationId);

      setState(() => _isLoading = false);

      if (success) {
        Fluttertoast.showToast(
          msg: 'Conversation history cleared',
          backgroundColor: Colors.orange,
        );
      } else {
        Fluttertoast.showToast(
          msg: 'Failed to clear history',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Widget _buildConversationItem(DocumentSnapshot? doc) {
    if (doc == null) return const SizedBox.shrink();
    final conversation = Conversation.fromDocument(doc);

    if (conversation.isGroup) {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection(FirestoreConstants.pathGroupCollection)
            .doc(conversation.id)
            .get(),
        builder: (_, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final group = Group.fromDocument(snapshot.data!);

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
            decoration: BoxDecoration(
              color: conversation.isPinned
                  ? ColorConstants.primaryColor.withOpacity(0.05)
                  : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupChatPage(group: group),
                    ),
                  );
                },
                onLongPress: () => _showConversationOptions(conversation),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          ClipOval(
                            child: group.groupPhotoUrl.isNotEmpty
                                ? Image.network(
                                    group.groupPhotoUrl,
                                    fit: BoxFit.cover,
                                    width: 50,
                                    height: 50,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.group,
                                      size: 50,
                                      color: ColorConstants.primaryColor,
                                    ),
                                  )
                                : const Icon(
                                    Icons.group,
                                    size: 50,
                                    color: ColorConstants.primaryColor,
                                  ),
                          ),
                          if (conversation.isMuted)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.volume_off,
                                  size: 14,
                                  color: ColorConstants.greyColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (conversation.isPinned)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.push_pin,
                                      size: 14,
                                      color: ColorConstants.primaryColor,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    group.groupName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ColorConstants.primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getLastMessagePreview(
                                conversation.lastMessage,
                                conversation.lastMessageType,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: conversation.isMuted
                                    ? ColorConstants.greyColor
                                    : ColorConstants.greyColor,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getTimeAgo(conversation.lastMessageTime),
                        style: const TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
        if (!snapshot.hasData) return const SizedBox.shrink();
        final userChat = UserChat.fromDocument(snapshot.data!);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          decoration: BoxDecoration(
            color: conversation.isPinned
                ? ColorConstants.primaryColor.withOpacity(0.05)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      arguments: ChatPageArguments(
                        peerId: userChat.id,
                        peerAvatar: userChat.photoUrl,
                        peerNickname: userChat.nickname,
                      ),
                    ),
                  ),
                );
              },
              onLongPress: () => _showConversationOptions(conversation),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        ClipOval(
                          child: userChat.photoUrl.isNotEmpty
                              ? Image.network(
                                  userChat.photoUrl,
                                  fit: BoxFit.cover,
                                  width: 50,
                                  height: 50,
                                  loadingBuilder: (_, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const SizedBox(
                                      width: 50,
                                      height: 50,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: ColorConstants.themeColor,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (_, __, ___) {
                                    return const Icon(
                                      Icons.account_circle,
                                      size: 50,
                                      color: ColorConstants.greyColor,
                                    );
                                  },
                                )
                              : const Icon(
                                  Icons.account_circle,
                                  size: 50,
                                  color: ColorConstants.greyColor,
                                ),
                        ),
                        if (conversation.isMuted)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.volume_off,
                                size: 14,
                                color: ColorConstants.greyColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (conversation.isPinned)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 14,
                                    color: ColorConstants.primaryColor,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  userChat.nickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: ColorConstants.primaryColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getLastMessagePreview(
                              conversation.lastMessage,
                              conversation.lastMessageType,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: conversation.isMuted
                                  ? ColorConstants.greyColor
                                  : ColorConstants.greyColor,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getTimeAgo(conversation.lastMessageTime),
                      style: const TextStyle(
                        color: ColorConstants.greyColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 🎯 NEW: Smart search with auto-detection (nickname or phone)
  Widget _buildSmartSearchResults() {
    return StreamBuilder<QuerySnapshot>(
      stream: _performSmartSearch(),
      builder: (_, snapshot) {
        if (snapshot.hasData) {
          if (snapshot.data!.docs.isNotEmpty) {
            return ListView.builder(
              controller: _listScrollController,
              padding: const EdgeInsets.all(10),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (_, i) =>
                  _buildSearchResultItem(snapshot.data?.docs[i]),
            );
          } else {
            return const Center(child: Text("No users found"));
          }
        } else {
          return const Center(
            child: CircularProgressIndicator(color: ColorConstants.themeColor),
          );
        }
      },
    );
  }

  // 🎯 NEW: Perform smart search
  Stream<QuerySnapshot> _performSmartSearch() {
    final query = _textSearch.trim();

    // Check if it's a phone number pattern
    final isPhoneNumber = RegExp(r'^[+\d][\d\s-]*$').hasMatch(query);

    if (isPhoneNumber) {
      // Search by phone number (exact match)
      return _homeProvider.firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.phoneNumber, isEqualTo: query)
          .limit(_limit)
          .snapshots();
    } else {
      // Search by nickname (starts with match for auto-suggest)
      return _homeProvider.firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.nickname, isGreaterThanOrEqualTo: query)
          .where(FirestoreConstants.nickname,
              isLessThanOrEqualTo: '$query\uf8ff')
          .limit(_limit)
          .snapshots();
    }
  }

  Widget _buildSearchResultItem(DocumentSnapshot? document) {
    if (document == null) return const SizedBox.shrink();
    final userChat = UserChat.fromDocument(document);
    if (userChat.id == _currentUserId) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: TextButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserProfilePage(userChat: userChat),
            ),
          );
        },
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(ColorConstants.greyColor2),
          shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
        child: Row(
          children: [
            ClipOval(
              child: userChat.photoUrl.isNotEmpty
                  ? Image.network(userChat.photoUrl,
                      fit: BoxFit.cover,
                      width: 50,
                      height: 50,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.account_circle, size: 50))
                  : const Icon(Icons.account_circle, size: 50),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(userChat.nickname,
                      style: const TextStyle(
                          color: ColorConstants.primaryColor,
                          fontWeight: FontWeight.bold)),
                  if (userChat.phoneNumber.isNotEmpty)
                    Text('📱 ${userChat.phoneNumber}',
                        style: const TextStyle(
                            color: ColorConstants.greyColor, fontSize: 12)),
                  if (userChat.aboutMe.isNotEmpty)
                    Text(userChat.aboutMe,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: ColorConstants.greyColor, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          AppConstants.homeTitle,
          style: TextStyle(color: ColorConstants.primaryColor),
        ),
        centerTitle: true,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(FirestoreConstants.pathFriendRequestCollection)
                .where(FirestoreConstants.receiverId, isEqualTo: _currentUserId)
                .where(FirestoreConstants.status, isEqualTo: 'pending')
                .snapshots(),
            builder: (_, snapshot) {
              final pendingCount =
                  snapshot.hasData ? snapshot.data!.docs.length : 0;

              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NotificationsPage()),
                      );
                    },
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          pendingCount > 9 ? '9+' : '$pendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          _buildPopupMenu(),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildSmartSearchBar(),
                if (_textSearch.isEmpty) _buildOnlineFriendsSection(),
                Expanded(
                  child: _textSearch.isEmpty
                      ? StreamBuilder<List<QueryDocumentSnapshot>>(
                          stream: _conversationProvider
                              .getConversationsWithPinned(_currentUserId),
                          builder: (_, snapshot) {
                            if (snapshot.hasData) {
                              final conversations = snapshot.data!;
                              if (conversations.isNotEmpty) {
                                return ListView.builder(
                                  controller: _listScrollController,
                                  padding: const EdgeInsets.all(10),
                                  itemCount: conversations.length,
                                  itemBuilder: (_, i) =>
                                      _buildConversationItem(conversations[i]),
                                );
                              } else {
                                return const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.chat_bubble_outline,
                                          size: 80,
                                          color: ColorConstants.greyColor),
                                      SizedBox(height: 16),
                                      Text(
                                        "No conversations yet",
                                        style: TextStyle(
                                            color: ColorConstants.greyColor,
                                            fontSize: 16),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        "Scan QR code to add friends",
                                        style: TextStyle(
                                            color: ColorConstants.greyColor,
                                            fontSize: 14),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            } else {
                              return const Center(
                                child: CircularProgressIndicator(
                                    color: ColorConstants.themeColor),
                              );
                            }
                          },
                        )
                      : _buildSmartSearchResults(),
                ),
              ],
            ),
            if (_isLoading) LoadingView(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scanQRCode,
        backgroundColor: ColorConstants.primaryColor,
        child: const Icon(Icons.qr_code_scanner, color: Colors.white),
      ),
    );
  }

  @override
  void dispose() {
    _conversationsSubscription?.cancel();
    _friendRequestsSubscription?.cancel();
    _btnClearController.close();
    _searchBarController.dispose();
    _listScrollController
      ..removeListener(_scrollListener)
      ..dispose();
    super.dispose();
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

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/utils/utils.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.arguments,
    this.isMiniChat = false,
    this.isBubbleMode = false,
    this.isWebMode = false,
  });

  final ChatPageArguments arguments;
  final bool isMiniChat;
  final bool isBubbleMode;
  final bool isWebMode;

  @override
  ChatPageState createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage>
    with WidgetsBindingObserver, ResourceManagerMixin {
  late final String _currentUserId;
  UserPresenceProvider? _presenceProvider;

  UnifiedBubbleService? _unifiedBubbleService;

  static const MethodChannel _miniChatChannel =
      MethodChannel('mini_chat_channel');
  static const MethodChannel _bubbleChannel =
      MethodChannel('bubble_chat_channel');

  bool _isTyping = false;

  List<QueryDocumentSnapshot> _listMessage = [];
  int _limit = 20;
  final _limitIncrement = 20;
  String _groupChatId = "";

  File? _imageFile;
  bool _isLoading = false;
  bool _isShowSticker = false;
  String _imageUrl = "";

  late final TextEditingController _chatInputController;
  late final ScrollController _listScrollController;
  late final FocusNode _focusNode;

  late ChatProvider _chatProvider;
  late AuthProvider _authProvider;
  late MessageProvider _messageProvider;
  late ReactionProvider _reactionProvider;
  late ReminderProvider _reminderProvider;
  late AutoDeleteProvider _autoDeleteProvider;
  late ConversationLockProvider _lockProvider;
  late ViewOnceProvider _viewOnceProvider;
  late SmartReplyProvider _smartReplyProvider;
  late TelemetryProvider _telemetryProvider;
  VoiceMessageProvider? _voiceProvider;
  LocationProvider? _locationProvider;

  List<DocumentSnapshot> _pinnedMessages = [];

  List<SmartReply> _smartReplies = [];
  String _lastReceivedMessage = '';

  MessageChat? _replyingTo;
  bool _conversationLockedChecked = false;

  final Set<String> _processedMessageIds = {};
  bool _isProcessingMessage = false;

  bool _showFeaturesMenu = false;

  bool _isRecording = false;
  String _recordingDuration = "0:00";
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  final Map<String, Timer> _scheduledMessages = {};
  final Map<String, String> _scheduledMessageContents = {};

  final Map<String, String> _scamResults = {};

  @override
  void initState() {
    super.initState();

    _chatInputController = TextEditingController();
    _listScrollController = ScrollController();
    _focusNode = FocusNode();

    WidgetsBinding.instance.addObserver(this);

    _focusNode.addListener(_onFocusChange);
    resourceManager
        .addDisposer(() => _focusNode.removeListener(_onFocusChange));

    _listScrollController.addListener(_scrollListener);
    resourceManager.addDisposer(
        () => _listScrollController.removeListener(_scrollListener));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!resourceManager.isDisposed && mounted) {
        _initializeProviders(context);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (resourceManager.isDisposed) return;
    if (state == AppLifecycleState.paused) {
      _presenceProvider?.setUserOffline(_currentUserId);
    } else if (state == AppLifecycleState.resumed) {
      _presenceProvider?.setUserOnline(_currentUserId);
    }
  }

  @override
  void dispose() {
    _scheduledMessages.forEach((key, timer) {
      try {
        timer.cancel();
      } catch (e) {
        print('⚠️ Error canceling timer: $e');
      }
    });
    _scheduledMessages.clear();
    _scheduledMessageContents.clear();

    _recordingTimer?.cancel();

    try {
      if (_presenceProvider != null && _currentUserId.isNotEmpty) {
        _presenceProvider!.setUserOffline(_currentUserId);
        _presenceProvider!.setTypingStatus(
          conversationId: _groupChatId,
          userId: _currentUserId,
          isTyping: false,
        );
      }
    } catch (e) {
      print('⚠️ Error updating presence: $e');
    }

    try {
      _voiceProvider?.dispose();
    } catch (e) {
      print('⚠️ Error disposing voice provider: $e');
    }

    try {
      _chatInputController.dispose();
      _listScrollController.dispose();
      _focusNode.dispose();
    } catch (e) {
      print('⚠️ Controller disposal error: $e');
    }

    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (e) {
      print('⚠️ Error removing observer: $e');
    }

    super.dispose();
  }

  void _initializeProviders(BuildContext context) {
    if (resourceManager.isDisposed) return;

    _chatProvider = context.read<ChatProvider>();
    _authProvider = context.read<AuthProvider>();
    _messageProvider = context.read<MessageProvider>();
    _reactionProvider = context.read<ReactionProvider>();
    _reminderProvider = context.read<ReminderProvider>();
    _autoDeleteProvider = context.read<AutoDeleteProvider>();
    _lockProvider = context.read<ConversationLockProvider>();
    _viewOnceProvider = context.read<ViewOnceProvider>();
    _smartReplyProvider = context.read<SmartReplyProvider>();
    _presenceProvider = context.read<UserPresenceProvider>();
    _unifiedBubbleService = context.read<UnifiedBubbleService>();
    _telemetryProvider = context.read<TelemetryProvider>();

    final miniChatSub = _unifiedBubbleService?.bubbleClickStream.listen(
      (event) {
        if (event.userId == widget.arguments.peerId) {
          print('💬 Bubble clicked for: ${event.userName}');
          Fluttertoast.showToast(
            msg: '📨 ${widget.arguments.peerNickname}: ${event.message}',
            backgroundColor: Colors.green,
            toastLength: Toast.LENGTH_SHORT,
          );
        }
      },
      onError: (error) {
        print('❌ Mini chat stream error: $error');
      },
    );
    if (miniChatSub != null) {
      resourceManager.addSubscription(miniChatSub);
    }

    try {
      _voiceProvider = VoiceMessageProvider(
        firebaseStorage: _chatProvider.firebaseStorage,
      );
    } catch (e) {
      print('⚠️ Voice provider initialization failed: $e');
      _voiceProvider = null;
    }

    _locationProvider = LocationProvider();

    _readLocal();
    _loadPinnedMessages();
    _checkConversationLock();
    _loadSmartReplies();
    _setupAutoReadMarking();

    if (_presenceProvider != null && _currentUserId.isNotEmpty) {
      _presenceProvider!.setUserOnline(_currentUserId);
      _presenceProvider!.markMessagesAsRead(
        conversationId: _groupChatId,
        userId: _currentUserId,
      );
    }

    ErrorLogger.logScreenView('chat_page');
  }

  void _readLocal() {
    if (_authProvider.userFirebaseId?.isNotEmpty == true) {
      _currentUserId = _authProvider.userFirebaseId!;
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginPage()),
        (_) => false,
      );
      return;
    }

    String peerId = widget.arguments.peerId;
    if (_currentUserId.compareTo(peerId) > 0) {
      _groupChatId = '$_currentUserId-$peerId';
    } else {
      _groupChatId = '$peerId-$_currentUserId';
    }

    _setupIncomingMessageListener();

    _chatProvider.updateDataFirestore(
      FirestoreConstants.pathUserCollection,
      _currentUserId,
      {FirestoreConstants.chattingWith: peerId},
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!resourceManager.isDisposed && mounted) {
        _markMessagesAsRead();
      }
    });
  }

  void _scrollListener() {
    if (resourceManager.isDisposed || !_listScrollController.hasClients) return;
    final pos = _listScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 &&
        !_listScrollController.position.outOfRange &&
        _limit <= _listMessage.length) {
      if (mounted) setState(() => _limit += _limitIncrement);
    }
  }

  void _ensureKeyboardVisibility() {
    if (widget.isMiniChat) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _focusNode.hasFocus && !resourceManager.isDisposed) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  void _onFocusChange() {
    if (resourceManager.isDisposed || !mounted) return;
    if (_focusNode.hasFocus) {
      setState(() {
        _isShowSticker = false;
        _showFeaturesMenu = false;
      });
      if (widget.isMiniChat) _ensureKeyboardVisibility();
    }
  }

  void _loadPinnedMessages() {
    if (resourceManager.isDisposed) return;
    final subscription =
        _messageProvider.getPinnedMessages(_groupChatId).listen(
      (snapshot) {
        if (!mounted || resourceManager.isDisposed) return;
        setState(() => _pinnedMessages = snapshot.docs);
      },
      onError: (err) {
        ErrorLogger.logError(err, null, context: 'Load Pinned Messages');
      },
    );
    resourceManager.addSubscription(subscription);
  }

  void _setupIncomingMessageListener() {
    if (resourceManager.isDisposed ||
        _groupChatId.isEmpty ||
        _currentUserId.isEmpty) {
      print('⚠️ Cannot setup listener: groupChatId or currentUserId is empty');
      return;
    }

    final subscription = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(_groupChatId)
        .collection(_groupChatId)
        .where(FirestoreConstants.idTo, isEqualTo: _currentUserId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen(
      (snapshot) async {
        if (resourceManager.isDisposed) return;

        if (_isProcessingMessage) {
          print('⚠️ Already processing messages, skipping...');
          return;
        }

        _isProcessingMessage = true;

        try {
          for (var change in snapshot.docChanges) {
            if (resourceManager.isDisposed) break;

            if (change.type == DocumentChangeType.added) {
              final docId = change.doc.id;

              if (_processedMessageIds.contains(docId)) {
                print('ℹ️ Message already processed: $docId');
                continue;
              }

              _processedMessageIds.add(docId);
              print('✅ Processing new message: $docId');

              if (_processedMessageIds.length > 100) {
                final toRemove = _processedMessageIds.length - 100;
                final oldIds = _processedMessageIds.take(toRemove).toList();
                _processedMessageIds.removeAll(oldIds);
                print('🗑️ Cleaned ${oldIds.length} old message IDs');
              }

              final data = change.doc.data();
              if (data != null) {
                final content =
                    data[FirestoreConstants.content] as String? ?? '';
                final type = data[FirestoreConstants.type] as int? ?? 0;
                await _updateBubbleWithMessage(content, type,
                    isFromUser: false);
              }

              _showChatBubbleIfNeeded();
            }
          }
        } finally {
          _isProcessingMessage = false;
        }
      },
      onError: (error) {
        _isProcessingMessage = false;
        ErrorLogger.logError(
          error,
          null,
          context: 'Incoming Messages Listener',
        );
      },
    );

    resourceManager.addSubscription(subscription);
    print('✅ Incoming message listener setup with deduplication');
  }

  void _setupAutoReadMarking() {
    if (resourceManager.isDisposed) return;
    final subscription = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(_groupChatId)
        .collection(_groupChatId)
        .where(FirestoreConstants.idTo, isEqualTo: _currentUserId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen(
      (snapshot) {
        if (resourceManager.isDisposed) return;
        if (snapshot.docs.isNotEmpty && mounted) _markMessagesAsRead();
      },
      onError: (error) {
        ErrorLogger.logError(error, null, context: 'Setup Auto Read');
      },
    );
    resourceManager.addSubscription(subscription);
  }

  Future<void> _markMessagesAsRead() async {
    if (resourceManager.isDisposed) return;
    try {
      final unreadMessages = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(_groupChatId)
          .collection(_groupChatId)
          .where(FirestoreConstants.idTo, isEqualTo: _currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      if (unreadMessages.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      ErrorLogger.logMessageRead(conversationId: _groupChatId);
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'Mark Messages Read');
    }
  }

  Future<void> _onSendMessageWithAutoDelete(String content, int type) async {
    if (resourceManager.isDisposed) return;

    if (content.trim().isEmpty) {
      Fluttertoast.showToast(
        msg: 'Nothing to send',
        backgroundColor: ColorConstants.greyColor,
      );
      return;
    }

    HapticFeedback.mediumImpact();

    String finalContent = content;
    if (_replyingTo != null) {
      finalContent = '↪ ${_replyingTo!.content}\n$finalContent';
    }

    if (!resourceManager.isDisposed && _chatInputController.hasListeners) {
      _chatInputController.clear();
    }

    if (mounted && !resourceManager.isDisposed) {
      setState(() {
        _replyingTo = null;
        _smartReplies = [];
      });
    }

    try {
      _chatProvider.sendMessage(
        finalContent,
        type,
        _groupChatId,
        _currentUserId,
        widget.arguments.peerId,
      );

      ErrorLogger.logMessageSent(
        conversationId: _groupChatId,
        messageType: type,
      );

      await _updateBubbleWithMessage(finalContent, type, isFromUser: true);
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'Send Message');
      Fluttertoast.showToast(msg: 'Send failed');
      return;
    }

    try {
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();
      await _autoDeleteProvider.scheduleMessageDeletion(
        groupChatId: _groupChatId,
        messageId: messageId,
        conversationId: _groupChatId,
      );
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'Schedule Auto Delete');
    }

    if (!resourceManager.isDisposed) {
      await _loadSmartReplies();
    }

    if (_listScrollController.hasClients && !resourceManager.isDisposed) {
      _listScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _updateBubbleWithMessage(String content, int type,
      {required bool isFromUser}) async {
    if (_unifiedBubbleService == null || resourceManager.isDisposed) return;

    try {
      if (!_unifiedBubbleService!.isBubbleActive(widget.arguments.peerId)) {
        return;
      }

      String messageType = 'text';
      String displayMessage = content;

      switch (type) {
        case TypeMessage.text:
          messageType = 'text';
          if (content.contains('maps.google.com') ||
              content.contains('Location:')) {
            messageType = 'location';
            displayMessage = '📍 Location';
          }
          break;
        case TypeMessage.image:
          messageType = 'image';
          displayMessage = '📷 Photo';
          break;
        case 3:
          messageType = 'voice';
          displayMessage = '🎤 Voice message';
          break;
        default:
          messageType = 'text';
      }

      await _unifiedBubbleService!.sendMessage(
        userId: widget.arguments.peerId,
        userName: widget.arguments.peerNickname,
        message: displayMessage,
        avatarUrl: widget.arguments.peerAvatar,
        messageType: messageType,
      );

      print(
          '✅ Bubble updated with ${isFromUser ? "sent" : "received"} message');
    } catch (e) {
      print('❌ Error updating bubble: $e');
    }
  }

  Future<void> _showChatBubbleIfNeeded() async {
    if (resourceManager.isDisposed) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      await _unifiedBubbleService?.showChatBubble(
        userId: widget.arguments.peerId,
        userName: widget.arguments.peerNickname,
        avatarUrl: widget.arguments.peerAvatar,
      );
    }
  }

  Future<void> _createChatBubble() async {
    if (_unifiedBubbleService == null || resourceManager.isDisposed) {
      Fluttertoast.showToast(msg: 'Bubble service not available');
      return;
    }

    if (!_unifiedBubbleService!.isSupported) {
      Fluttertoast.showToast(msg: 'Chat bubbles not supported on this device');
      return;
    }

    final hasPermission = await _unifiedBubbleService!.hasOverlayPermission();
    if (!hasPermission) {
      final granted = await _unifiedBubbleService!.requestOverlayPermission();
      if (!granted) {
        Fluttertoast.showToast(msg: 'Overlay permission required');
        return;
      }
    }

    final impl = _unifiedBubbleService!.getImplementationInfo();
    print('🎈 Creating bubble using: $impl');

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Chat Bubble'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose how to open this conversation:'),
            const SizedBox(height: 8),
            Text(
              'Using: $impl',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'bubble'),
            child: const Text('Bubble Only'),
          ),
          if (_unifiedBubbleService!.currentImplementation ==
              BubbleImplementation.windowManager)
            TextButton(
              onPressed: () => Navigator.pop(context, 'minichat'),
              child: const Text('Mini Chat'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice == null) return;

    if (choice == 'bubble') {
      final success = await _unifiedBubbleService!.showChatBubble(
        userId: widget.arguments.peerId,
        userName: widget.arguments.peerNickname,
        avatarUrl: widget.arguments.peerAvatar,
      );
      Fluttertoast.showToast(
        msg: success ? '💬 Chat bubble created' : '❌ Failed to create bubble',
        backgroundColor: success ? Colors.green : Colors.red,
      );
    } else if (choice == 'minichat') {
      final success = await _unifiedBubbleService!.showMiniChat(
        userId: widget.arguments.peerId,
        userName: widget.arguments.peerNickname,
        avatarUrl: widget.arguments.peerAvatar,
      );
      Fluttertoast.showToast(
        msg: success
            ? '💬 Mini chat opened'
            : '⚠️ Mini chat not supported with Bubble API',
        backgroundColor: success ? Colors.green : Colors.orange,
      );
    }
  }

  void _showBubbleInfo() {
    if (_unifiedBubbleService == null) return;

    final impl = _unifiedBubbleService!.getImplementationInfo();
    final canMigrate = _unifiedBubbleService!.currentImplementation ==
        BubbleImplementation.windowManager;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bubble Implementation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current: $impl'),
            const SizedBox(height: 16),
            if (canMigrate)
              Text(
                'Your device supports the new Bubble API! Migrate for better performance and battery life.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
          ],
        ),
        actions: [
          if (canMigrate)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final success =
                    await _unifiedBubbleService!.migrateToModernApi();
                Fluttertoast.showToast(
                  msg: success
                      ? '✅ Migrated to Bubble API'
                      : '❌ Migration failed',
                  backgroundColor: success ? Colors.green : Colors.red,
                );
              },
              child: const Text('Migrate Now'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showBubbleDebugInfo() async {
    if (_unifiedBubbleService == null) return;

    try {
      final count =
          await _unifiedBubbleService!.getMessageCount(widget.arguments.peerId);
      final stats = await _unifiedBubbleService!.getBubbleStats();
      await _unifiedBubbleService!.logBubbleState();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bubble Debug Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Message count: $count'),
              const SizedBox(height: 8),
              Text('Active conversations: ${stats['activeConversations']}'),
              Text('Total messages: ${stats['totalMessages']}'),
              Text('Average messages: ${stats['averageMessages']}'),
              const SizedBox(height: 8),
              const Text(
                'Check Android logs for detailed state',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _unifiedBubbleService!
                    .clearMessageHistory(widget.arguments.peerId);
                Navigator.pop(context);
                Fluttertoast.showToast(msg: 'History cleared');
              },
              child: const Text('Clear History'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ Error showing debug info: $e');
    }
  }

  Future<bool> _pickImage() async {
    HapticFeedback.lightImpact();
    try {
      final imagePicker = ImagePicker();
      final pickedXFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedXFile != null) {
        final imageFile = File(pickedXFile.path);
        if (!mounted || resourceManager.isDisposed) return false;
        setState(() {
          _imageFile = imageFile;
          _isLoading = true;
        });
        return true;
      }
      return false;
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'Pick Image');
      Fluttertoast.showToast(msg: 'Failed to pick image');
      return false;
    }
  }

  Future<void> _uploadFile() async {
    if (_imageFile == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => const SafeSendDialog(
        title: 'Gửi Hình Ảnh',
        content: 'Bạn có chắc chắn muốn gửi bức ảnh này cho người khác không?',
        icon: Icons.image_rounded,
      ),
    );
    if (confirm != true) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final fileName = DateTime.now().millisecondsSinceEpoch.toString();
      final uploadTask = _chatProvider.uploadFile(_imageFile!, fileName);
      final snapshot = await uploadTask;
      _imageUrl = await snapshot.ref.getDownloadURL();

      if (!mounted || resourceManager.isDisposed) return;
      setState(() => _isLoading = false);
      await _onSendMessageWithAutoDelete(_imageUrl, TypeMessage.image);
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'Upload File');
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _isLoading = false);
      }
      Fluttertoast.showToast(msg: 'Upload failed');
    }
  }

  void _getSticker() {
    if (resourceManager.isDisposed) return;
    HapticFeedback.lightImpact();
    _focusNode.unfocus();
    setState(() {
      _isShowSticker = !_isShowSticker;
      _showFeaturesMenu = false;
    });
  }

  void _handleTyping(String text) {
    if (_presenceProvider == null || resourceManager.isDisposed) return;

    _telemetryProvider.recordTextChange(text);

    if (_telemetryProvider.shouldSuggestElderMode) {
      _showAdaptiveUISuggestion();
      _telemetryProvider.markAsHandled();
    }

    if (text.isEmpty) {
      if (_isTyping) {
        _isTyping = false;
        _presenceProvider!.setTypingStatus(
          conversationId: _groupChatId,
          userId: _currentUserId,
          isTyping: false,
        );
      }
      return;
    }

    if (!_isTyping) {
      _isTyping = true;
      _presenceProvider!.setTypingStatus(
        conversationId: _groupChatId,
        userId: _currentUserId,
        isTyping: true,
      );
    }

    resourceManager.addTimer(Timer(const Duration(seconds: 3), () {
      if (!resourceManager.isDisposed) {
        _isTyping = false;
        _presenceProvider?.setTypingStatus(
          conversationId: _groupChatId,
          userId: _currentUserId,
          isTyping: false,
        );
      }
    }));
  }

  void _showAdaptiveUISuggestion() {
    if (resourceManager.isDisposed || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.accessibility_new, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Bạn đang gặp khó khăn khi gõ chữ? Đổi sang giao diện lớn hơn nhé?'),
            ),
          ],
        ),
        duration: const Duration(seconds: 8),
        backgroundColor: Colors.blueGrey,
        action: SnackBarAction(
          label: 'BẬT (Elder Mode)',
          textColor: Colors.amberAccent,
          onPressed: () {
            // Tích hợp Provider để kích hoạt Elder Mode
            try {
              context.read<AppModeProvider>().setMode(AppMode.elder);
              Fluttertoast.showToast(
                  msg: 'Đã chuyển sang giao diện người lớn tuổi!');
            } catch (e) {
              print('Lỗi chuyển giao diện: $e');
            }
          },
        ),
      ),
    );
  }

  void _showAdvancedMessageOptions(MessageChat message, String messageId) {
    if (resourceManager.isDisposed) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => EnhancedMessageOptionsDialog(
        isOwnMessage: message.idFrom == _currentUserId,
        isPinned: message.isPinned,
        isDeleted: message.isDeleted,
        messageContent: message.content,
        onEdit: () => _editMessage(messageId, message.content),
        onDelete: () => _deleteMessage(messageId),
        onPin: () => _togglePinMessage(messageId, message.isPinned),
        onCopy: () => _copyMessage(message.content),
        onReply: () => _setReplyToMessage(message),
        onReminder: () => _setMessageReminder(message, messageId),
        onTranslate: () => _translateMessage(message.content),
      ),
    );
  }

  Future<void> _editMessage(String messageId, String currentContent) async {
    if (resourceManager.isDisposed) return;
    showDialog(
      context: context,
      builder: (context) => EditMessageDialog(
        originalContent: currentContent,
        onSave: (newContent) async {
          final success = await _messageProvider.editMessage(
            _groupChatId,
            messageId,
            newContent,
          );
          if (success) {
            Fluttertoast.showToast(msg: 'Message edited');
          }
        },
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    if (resourceManager.isDisposed) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && !resourceManager.isDisposed) {
      final success = await _messageProvider.deleteMessage(
        _groupChatId,
        messageId,
      );
      if (success) {
        Fluttertoast.showToast(msg: 'Message deleted');
      }
    }
  }

  Future<void> _togglePinMessage(String messageId, bool currentStatus) async {
    if (resourceManager.isDisposed) return;
    final success = await _messageProvider.togglePinMessage(
      _groupChatId,
      messageId,
      currentStatus,
    );
    if (success) {
      Fluttertoast.showToast(
        msg: currentStatus ? 'Message unpinned' : 'Message pinned',
      );
    }
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    Fluttertoast.showToast(msg: 'Copied to clipboard');
  }

  void _setReplyToMessage(MessageChat message) {
    HapticFeedback.selectionClick();
    if (resourceManager.isDisposed || !mounted) return;

    setState(() => _replyingTo = message);
    _focusNode.requestFocus();
  }

  void _showReactionPicker(String messageId) {
    if (resourceManager.isDisposed) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ReactionPicker(
          onEmojiSelected: (emoji) {
            _reactionProvider.toggleReaction(
              _groupChatId,
              messageId,
              _currentUserId,
              emoji,
            );
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Future<DateTime?> _pickTimeWithWheel() async {
    if (resourceManager.isDisposed) return null;

    DateTime selectedTime = DateTime.now().add(const Duration(hours: 1));

    return await showDialog<DateTime>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Set Reminder Time'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Date'),
                    subtitle: Text(
                      DateFormat('MMM dd, yyyy').format(selectedTime),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedTime,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() {
                          selectedTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            selectedTime.hour,
                            selectedTime.minute,
                          );
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('Time'),
                    subtitle: Text(DateFormat('HH:mm').format(selectedTime)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(selectedTime),
                      );
                      if (time != null) {
                        setState(() {
                          selectedTime = DateTime(
                            selectedTime.year,
                            selectedTime.month,
                            selectedTime.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selectedTime),
                  child: const Text('Set'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _setMessageReminder(
    MessageChat message,
    String messageId,
  ) async {
    if (resourceManager.isDisposed) return;

    final reminderTime = await _pickTimeWithWheel();

    if (reminderTime != null && !resourceManager.isDisposed) {
      final success = await _reminderProvider.scheduleReminder(
        userId: _currentUserId,
        messageId: messageId,
        conversationId: _groupChatId,
        reminderTime: reminderTime,
        message: message.content,
      );

      Fluttertoast.showToast(
        msg: success ? '⏰ Reminder set successfully' : 'Failed to set reminder',
      );
    }
  }

  void _showReminders() {
    if (resourceManager.isDisposed) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Reminders')),
          body: StreamBuilder<QuerySnapshot>(
            stream: _reminderProvider.getUserReminders(_currentUserId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final reminders = snapshot.data!.docs;
              if (reminders.isEmpty) {
                return const Center(child: Text('No reminders'));
              }
              return ListView.builder(
                itemCount: reminders.length,
                itemBuilder: (context, index) {
                  final reminder =
                      MessageReminder.fromDocument(reminders[index]);
                  return ListTile(
                    title: Text(reminder.message),
                    subtitle: Text(
                      DateFormat('MMM dd, HH:mm').format(
                        DateTime.fromMillisecondsSinceEpoch(
                          int.parse(reminder.reminderTime),
                        ),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        _reminderProvider.deleteReminder(reminder.id);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _translateMessage(String content) async {
    if (resourceManager.isDisposed) return;
    showDialog(
      context: context,
      builder: (context) => TranslationDialog(
        originalMessage: content,
      ),
    );
  }

  Future<void> _checkConversationLock() async {
    if (resourceManager.isDisposed) return;

    final lockStatus = await _lockProvider.getConversationLockStatus(
      _groupChatId,
    );

    if (lockStatus != null && lockStatus['isLocked'] == true) {
      if (!mounted || resourceManager.isDisposed) return;

      final verified = await _showPINVerificationDialog();
      if (verified != true && mounted) {
        Navigator.pop(context);
      }
    }

    if (mounted && !resourceManager.isDisposed) {
      setState(() => _conversationLockedChecked = true);
    }
  }

  Future<bool> _showPINVerificationDialog() async {
    if (resourceManager.isDisposed) return false;

    String? errorMessage;
    int remainingAttempts = 5;

    while (remainingAttempts > 0 && !resourceManager.isDisposed) {
      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PINInputDialog(
          title: 'Enter PIN',
          onComplete: (pin) => Navigator.pop(context, pin),
          errorMessage: errorMessage,
          remainingAttempts: remainingAttempts,
        ),
      );

      if (pin == null || resourceManager.isDisposed) return false;

      final result = await _lockProvider.verifyPIN(
        conversationId: _groupChatId,
        enteredPin: pin,
      );

      if (result['success'] == true) return true;

      remainingAttempts = 5 - (result['failedAttempts'] as int);
      errorMessage = result['message'] as String;

      if (remainingAttempts <= 0 || result['locked'] == true) {
        await _lockProvider.autoDeleteMessagesAfterFailedAttempts(
          conversationId: _groupChatId,
        );
        Fluttertoast.showToast(
          msg: 'All messages deleted due to security breach',
          backgroundColor: Colors.red,
        );
        return false;
      }
    }

    return false;
  }

  void _showLockOptions() async {
    if (resourceManager.isDisposed) return;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock Conversation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Set PIN'),
              onTap: () => Navigator.pop(context, 'set_pin'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_open),
              title: const Text('Remove Lock'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );

    if (action == 'set_pin' && !resourceManager.isDisposed) {
      _showSetPINDialog();
    } else if (action == 'remove' && !resourceManager.isDisposed) {
      await _lockProvider.removeConversationLock(_groupChatId);
      Fluttertoast.showToast(msg: 'Lock removed');
    }
  }

  void _showSetPINDialog() async {
    if (resourceManager.isDisposed) return;
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => PINInputDialog(
        title: 'Set New PIN',
        onComplete: (pin) => Navigator.pop(context, pin),
      ),
    );
    if (pin != null && !resourceManager.isDisposed) {
      _showConfirmPINDialog(pin);
    }
  }

  void _showConfirmPINDialog(String originalPin) async {
    if (resourceManager.isDisposed) return;
    final confirmPin = await showDialog<String>(
      context: context,
      builder: (context) => PINInputDialog(
        title: 'Confirm PIN',
        onComplete: (pin) => Navigator.pop(context, pin),
      ),
    );

    if (confirmPin == originalPin && !resourceManager.isDisposed) {
      final success = await _lockProvider.setConversationPIN(
        conversationId: _groupChatId,
        pin: originalPin,
      );
      if (success) {
        Fluttertoast.showToast(msg: 'PIN set successfully');
      }
    } else if (confirmPin != null) {
      Fluttertoast.showToast(msg: 'PINs do not match');
    }
  }

  Future<void> _loadSmartReplies() async {
    if (_listMessage.isEmpty || resourceManager.isDisposed) return;

    final lastMessage = _listMessage.first;
    final messageChat = MessageChat.fromDocument(lastMessage);

    if (messageChat.idFrom != _currentUserId &&
        messageChat.type == TypeMessage.text) {
      final replies = _smartReplyProvider.getRuleBasedReplies(
        messageChat.content,
      );
      if (mounted && !resourceManager.isDisposed) {
        setState(() {
          _smartReplies = replies;
          _lastReceivedMessage = messageChat.content;
        });
      }
    }
  }

  void _toggleFeaturesMenu() {
    HapticFeedback.selectionClick();
    if (resourceManager.isDisposed || !mounted) return;
    setState(() {
      _showFeaturesMenu = !_showFeaturesMenu;
      _isShowSticker = false;
    });
  }

  Future<void> _openLocationInMaps(String mapsUrl) async {
    try {
      final uri = Uri.parse(mapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('✅ Opened Maps: $mapsUrl');
      } else {
        Fluttertoast.showToast(
          msg: '❌ Cannot open Google Maps',
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      print('❌ Error opening Maps: $e');
      Fluttertoast.showToast(
        msg: '❌ Failed to open location',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _shareLocation() async {
    if (_locationProvider == null || resourceManager.isDisposed) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      final hasPermission =
          await _locationProvider!.requestLocationPermission();

      if (!hasPermission) {
        if (mounted && !resourceManager.isDisposed) {
          setState(() => _isLoading = false);
        }
        Fluttertoast.showToast(
          msg: '📍 Location permission required',
          backgroundColor: Colors.red,
        );
        return;
      }

      final locationData =
          await _locationProvider!.getCurrentLocationWithDetails();

      if (mounted && !resourceManager.isDisposed) {
        setState(() => _isLoading = false);
      }

      if (locationData != null && !resourceManager.isDisposed) {
        final message = _locationProvider!.formatLocationMessage(locationData);
        await _onSendMessageWithAutoDelete(message, TypeMessage.text);
        Fluttertoast.showToast(
          msg: '📍 Location shared successfully',
          backgroundColor: Colors.green,
        );
        print('✅ Location sent: ${locationData.mapsUrl}');
      } else {
        Fluttertoast.showToast(
          msg: '❌ Failed to get location. Please try again.',
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      print('❌ Location share error: $e');
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _isLoading = false);
      }
      Fluttertoast.showToast(
        msg: '❌ Failed to get location',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _scheduleMessage() async {
    if (resourceManager.isDisposed) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ScheduleMessageDialog(),
    );

    if (result == null || resourceManager.isDisposed || !mounted) return;

    final messageText = result['message'] as String;
    final scheduledTime = result['time'] as DateTime;
    final delay = scheduledTime.difference(DateTime.now());

    if (delay.isNegative) {
      if (mounted) Fluttertoast.showToast(msg: 'Invalid time');
      return;
    }

    final scheduleKey = scheduledTime.millisecondsSinceEpoch.toString();
    _scheduledMessageContents[scheduleKey] = messageText;

    final timer = Timer(delay, () {
      if (!resourceManager.isDisposed && mounted) {
        final content = _scheduledMessageContents[scheduleKey];
        if (content != null) {
          _onSendMessageWithAutoDelete(content, TypeMessage.text);
        }
        _scheduledMessages.remove(scheduleKey);
        _scheduledMessageContents.remove(scheduleKey);
      }
    });

    _scheduledMessages[scheduleKey] = timer;

    if (mounted) {
      Fluttertoast.showToast(
        msg:
            '📅 Message scheduled for ${DateFormat('HH:mm').format(scheduledTime)}',
        backgroundColor: Colors.green,
      );
    }
  }

  Future<void> _startRecording() async {
    if (_voiceProvider == null || resourceManager.isDisposed) {
      Fluttertoast.showToast(msg: 'Voice recording not available');
      return;
    }

    final initialized = await _voiceProvider!.initRecorder();
    if (!initialized) {
      Fluttertoast.showToast(msg: 'Microphone permission required');
      return;
    }

    final started = await _voiceProvider!.startRecording();
    if (started && mounted && !resourceManager.isDisposed) {
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
        _recordingDuration = "0:00";
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || resourceManager.isDisposed) {
          timer.cancel();
          return;
        }
        setState(() {
          _recordingSeconds++;
          final minutes = _recordingSeconds ~/ 60;
          final seconds = _recordingSeconds % 60;
          _recordingDuration = "$minutes:${seconds.toString().padLeft(2, '0')}";
        });
      });
    }
  }

  Future<void> _stopRecording() async {
    if (_voiceProvider == null || resourceManager.isDisposed) return;

    _recordingTimer?.cancel();

    final filePath = await _voiceProvider!.stopRecording();
    if (filePath == null) {
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _isRecording = false);
      }
      Fluttertoast.showToast(msg: 'Recording failed');
      return;
    }

    if (mounted && !resourceManager.isDisposed) {
      setState(() {
        _isRecording = false;
        _isLoading = true;
      });
    }

    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    final url = await _voiceProvider!.uploadVoiceMessage(filePath, fileName);

    if (mounted && !resourceManager.isDisposed) {
      setState(() => _isLoading = false);
    }

    if (url != null && !resourceManager.isDisposed) {
      await _onSendMessageWithAutoDelete(url, 3);
      Fluttertoast.showToast(msg: '🎤 Voice message sent');
    } else {
      Fluttertoast.showToast(msg: 'Failed to send voice message');
    }
  }

  Future<void> _cancelRecording() async {
    if (_voiceProvider == null || resourceManager.isDisposed) return;
    _recordingTimer?.cancel();
    await _voiceProvider!.cancelRecording();
    if (mounted && !resourceManager.isDisposed) {
      setState(() => _isRecording = false);
    }
  }

  void _onBackPress() {
    if (_isShowSticker || _showFeaturesMenu) {
      if (mounted && !resourceManager.isDisposed) {
        setState(() {
          _isShowSticker = false;
          _showFeaturesMenu = false;
        });
      }
    } else {
      _chatProvider.updateDataFirestore(
        FirestoreConstants.pathUserCollection,
        _currentUserId,
        {FirestoreConstants.chattingWith: null},
      );
      Navigator.pop(context);
    }
  }

  void _minimizeBubble() {
    print('📦 Minimizing bubble');
    _focusNode.unfocus();
    _bubbleChannel.invokeMethod('minimize');
  }

  void _closeBubble() {
    print('❌ Closing bubble');
    _focusNode.unfocus();
    _bubbleChannel.invokeMethod('close');
  }

  void _showAIContextAnalysis() async {
    if (_listMessage.isEmpty) {
      Fluttertoast.showToast(msg: 'Chưa có đủ tin nhắn để phân tích');
      return;
    }

    List<String> recentMessages = _listMessage
        .take(15)
        .map((doc) {
          final rawMsg = MessageChat.fromDocument(doc);

          final decryptedContent =
              EncryptionService().decryptMessage(rawMsg.content, _groupChatId);

          final sender = rawMsg.idFrom == _currentUserId
              ? "Tôi"
              : widget.arguments.peerNickname;
          return "$sender: $decryptedContent";
        })
        .toList()
        .reversed
        .toList();

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('AI Đang Phân Tích...'),
                  ],
                ),
                content: FutureBuilder<String?>(
                  future: AIBackendService().analyzeChatContext(
                      recentMessages, 'work', 'extract_tasks'),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                          height: 100,
                          child: Center(child: CircularProgressIndicator()));
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return const Text('❌ Không thể kết nối với AI lúc này.');
                    }
                    return SingleChildScrollView(
                      child: Text(snapshot.data!,
                          style: const TextStyle(fontSize: 14, height: 1.5)),
                    );
                  },
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Đóng')),
                ]));
  }

  void _showChatOptionsMenu() {
    if (resourceManager.isDisposed) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Colors.purple),
              title: const Text('AI Assistant'),
              subtitle: const Text('Tóm tắt & Việc cần làm'),
              onTap: () {
                Navigator.pop(context);
                _showAIContextAnalysis();
              },
            ),
            ListTile(
              leading: Icon(Icons.search, color: ColorConstants.primaryColor),
              title: const Text('Search Messages'),
              subtitle: const Text('Search in conversation'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SearchMessagesPage(
                      groupChatId: _groupChatId,
                      peerName: widget.arguments.peerNickname,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.notifications, color: ColorConstants.primaryColor),
              title: const Text('Reminders'),
              subtitle: const Text('View all reminders'),
              onTap: () {
                Navigator.pop(context);
                _showReminders();
              },
            ),
            if (_unifiedBubbleService != null)
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.blue),
                title: const Text('Bubble Implementation'),
                subtitle: Text(_unifiedBubbleService!.getImplementationInfo()),
                onTap: () {
                  Navigator.pop(context);
                  _showBubbleInfo();
                },
              ),
            if (kDebugMode)
              ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.orange),
                title: const Text('Bubble Debug'),
                subtitle: const Text('View message history & stats'),
                onTap: () {
                  Navigator.pop(context);
                  _showBubbleDebugInfo();
                },
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      VideoCallIconButton(
        peerId: widget.arguments.peerId,
        peerName: widget.arguments.peerNickname,
        peerAvatar: widget.arguments.peerAvatar,
      ),
      VoiceCallIconButton(
        peerId: widget.arguments.peerId,
        peerName: widget.arguments.peerNickname,
        peerAvatar: widget.arguments.peerAvatar,
      ),
      IconButton(
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: _showChatOptionsMenu,
        tooltip: 'More options',
      ),
    ];
  }

  Widget _buildTypingIndicator() {
    if (_presenceProvider == null) return const SizedBox.shrink();

    return StreamBuilder<Map<String, bool>>(
      stream: _presenceProvider!.getTypingStatus(_groupChatId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final typingUsers = snapshot.data!;
        final peerTyping = typingUsers[widget.arguments.peerId] ?? false;

        if (!peerTyping) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: TypingIndicator(userName: widget.arguments.peerNickname),
        );
      },
    );
  }

  Widget _buildPinnedMessages() {
    if (_pinnedMessages.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            Border(bottom: BorderSide(color: Colors.black.withOpacity(0.05))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _pinnedMessages.length,
        itemBuilder: (context, index) {
          final message = MessageChat.fromDocument(_pinnedMessages[index]);
          return Container(
            width: 200,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.push_pin_rounded,
                    size: 14, color: Color(0xFF007AFF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF111418),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildListMessage() {
    return Flexible(
      child: _groupChatId.isNotEmpty
          ? StreamBuilder<QuerySnapshot>(
              stream: _chatProvider.getChatStream(_groupChatId, _limit),
              builder: (_, snapshot) {
                if (snapshot.hasData) {
                  _listMessage = snapshot.data!.docs;
                  if (_listMessage.isNotEmpty) {
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      itemBuilder: (_, index) =>
                          _buildItemMessage(index, snapshot.data?.docs[index]),
                      itemCount: snapshot.data?.docs.length,
                      reverse: true,
                      controller: _listScrollController,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                    );
                  } else {
                    return const Center(
                      child: Text(
                        "Bắt đầu cuộc trò chuyện...",
                        style: TextStyle(color: Color(0xFF8E8E93)),
                      ),
                    );
                  }
                } else {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: ColorConstants.themeColor,
                    ),
                  );
                }
              },
            )
          : const Center(
              child: CircularProgressIndicator(
                color: ColorConstants.themeColor,
              ),
            ),
    );
  }

  Widget _buildItemMessage(int index, DocumentSnapshot? document) {
    if (document == null) return const SizedBox.shrink();

    final rawMessageChat = MessageChat.fromDocument(document);

    final decryptedContent = EncryptionService()
        .decryptMessage(rawMessageChat.content, _groupChatId);

    final messageChat = rawMessageChat.copyWith(content: decryptedContent);

    final isMyMessage = messageChat.idFrom == _currentUserId;
    final data = document.data() as Map<String, dynamic>?;
    final isViewOnce = data?['isViewOnce'] ?? false;
    final isViewed = data?['isViewed'] ?? false;

    // --- PROACTIVE AI ---
    final bool isScamWarning = data?['scamWarning'] ?? false;
    final String scamReason = data?['scamReason'] ?? '';
    final bool hasReminder = data?['hasReminder'] ?? false;

    bool isLastInGroup = true;
    if (index > 0) {
      final prevMsg = MessageChat.fromDocument(_listMessage[index - 1]);
      isLastInGroup = prevMsg.idFrom != messageChat.idFrom;
    }
    final double tailRadius = isLastInGroup ? 4.0 : 20.0;

    if (isViewOnce) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment:
              isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            ViewOnceMessageWidget(
              groupChatId: _groupChatId,
              messageId: document.id,
              content: messageChat.content,
              type: messageChat.type,
              currentUserId: _currentUserId,
              isViewed: isViewed,
              provider: _viewOnceProvider,
            ),
          ],
        ),
      );
    }

    if (messageChat.type == 3 && _voiceProvider != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment:
              isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            VoiceMessageWidget(
              voiceUrl: messageChat.content,
              isMyMessage: isMyMessage,
              voiceProvider: _voiceProvider!,
            ),
          ],
        ),
      );
    }

    if (messageChat.type == TypeMessage.text) {
      final location =
          _locationProvider?.parseLocationFromMessage(messageChat.content);

      return Container(
        margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
        child: Column(
          crossAxisAlignment:
              isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onLongPress: () {
                    HapticFeedback.heavyImpact();
                    _showAdvancedMessageOptions(messageChat, document.id);
                  },
                  onDoubleTap: () {
                    HapticFeedback.mediumImpact();
                    _showReactionPicker(document.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      gradient: isMyMessage
                          ? const LinearGradient(
                              colors: [Color(0xFF007AFF), Color(0xFF0056D6)])
                          : null,
                      color: isMyMessage ? null : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft:
                            Radius.circular(isMyMessage ? 20 : tailRadius),
                        bottomRight:
                            Radius.circular(isMyMessage ? tailRadius : 20),
                      ),
                      boxShadow: isMyMessage
                          ? [
                              BoxShadow(
                                color:
                                    const Color(0xFF007AFF).withOpacity(0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              )
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. UI CẢNH BÁO LỪA ĐẢO TỰ ĐỘNG (BACKGROUND AI)
                        if (!isMyMessage && isScamWarning)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning,
                                    color: Colors.red, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'CẢNH BÁO AI: $scamReason',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // 2. UI ĐỀ XUẤT NHẮC NHỞ TỰ ĐỘNG (BACKGROUND AI)
                        if (!isMyMessage && hasReminder)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.alarm_add,
                                    color: Colors.blue, size: 16),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'AI: Phát hiện có công việc cần lưu!',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.blue),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _showReminders(),
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(40, 24)),
                                  child: const Text('XEM',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),

                        if (messageChat.isDeleted)
                          Text(
                            messageChat.content,
                            style: TextStyle(
                              color: isMyMessage
                                  ? Colors.white70
                                  : const Color(0xFF8E8E93),
                              fontStyle: FontStyle.italic,
                              fontSize: 15,
                            ),
                          )
                        else if (location != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    color:
                                        isMyMessage ? Colors.white : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Location',
                                    style: TextStyle(
                                      color: isMyMessage
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                location.address,
                                style: TextStyle(
                                  color: isMyMessage
                                      ? Colors.white
                                      : Colors.black87,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () =>
                                    _openLocationInMaps(location.mapsUrl),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMyMessage
                                        ? Colors.white.withOpacity(0.2)
                                        : ColorConstants.primaryColor
                                            .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isMyMessage
                                          ? Colors.white.withOpacity(0.3)
                                          : ColorConstants.primaryColor
                                              .withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.map,
                                        size: 16,
                                        color: isMyMessage
                                            ? Colors.white
                                            : ColorConstants.primaryColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'View on Google Maps',
                                        style: TextStyle(
                                          color: isMyMessage
                                              ? Colors.white
                                              : ColorConstants.primaryColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.open_in_new,
                                        size: 14,
                                        color: isMyMessage
                                            ? Colors.white
                                            : ColorConstants.primaryColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        else if (messageChat.idFrom ==
                            AppConstants.aiAssistantId)
                          MarkdownBody(
                            data: messageChat.content,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                color: Color(0xFF111418),
                                fontSize: 16,
                                height: 1.4,
                              ),
                              code: const TextStyle(
                                backgroundColor: Color(0xFFF2F2F7),
                                color: Color(0xFFE91E63),
                                fontFamily: 'monospace',
                              ),
                              codeblockPadding: const EdgeInsets.all(10),
                              codeblockDecoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                        else
                          Text(
                            messageChat.content,
                            style: TextStyle(
                              color: isMyMessage
                                  ? Colors.white
                                  : const Color(0xFF111418),
                              fontSize: 16,
                              height: 1.3,
                            ),
                          ),

                        if (messageChat.editedAt != null ||
                            (isMyMessage && !messageChat.isDeleted))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (messageChat.editedAt != null)
                                  Text(
                                    '(edited)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isMyMessage
                                          ? Colors.white70
                                          : const Color(0xFF8E8E93),
                                    ),
                                  ),
                                if (messageChat.editedAt != null && isMyMessage)
                                  const SizedBox(width: 4),
                                if (isMyMessage && !messageChat.isDeleted)
                                  Icon(
                                    messageChat.isRead
                                        ? Icons.done_all_rounded
                                        : Icons.check_rounded,
                                    size: 14,
                                    color: messageChat.isRead
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!messageChat.isDeleted) ...[
                  const SizedBox(width: 4),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_reaction, size: 18),
                        onPressed: () => _showReactionPicker(document.id),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      if (!isMyMessage)
                        IconButton(
                          icon: const Icon(Icons.alarm_add, size: 18),
                          onPressed: () =>
                              _setMessageReminder(messageChat, document.id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            if (!isMyMessage && messageChat.type == TypeMessage.text) ...[
              if (_scamResults[document.id] != null &&
                  _scamResults[document.id] != 'SAFE')
                ScamWarningWidget(status: _scamResults[document.id]!),

              // ĐÃ FIX: Chỉ hiện tùy chọn quét rủi ro thủ công nếu hệ thống ngầm chưa bắt được lỗi lừa đảo
              if (_scamResults[document.id] == null && !isScamWarning)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: InkWell(
                    onTap: () async {
                      Fluttertoast.showToast(msg: "AI Đang quét an toàn...");
                      final status = await AIBackendService()
                          .checkScam(messageChat.content);
                      if (mounted) {
                        setState(() {
                          _scamResults[document.id] = status;
                        });
                        if (status == 'SAFE') {
                          Fluttertoast.showToast(msg: "Tin nhắn an toàn!");
                        }
                      }
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          "Quét an toàn (AI)",
                          style: TextStyle(fontSize: 12, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            StreamBuilder<QuerySnapshot>(
              stream: _reactionProvider.getReactions(_groupChatId, document.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                final reactions = <String, int>{};
                final userReactions = <String, bool>{};

                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final emoji = data['emoji'] as String;
                  final userId = data['userId'] as String;

                  reactions[emoji] = (reactions[emoji] ?? 0) + 1;
                  if (userId == _currentUserId) {
                    userReactions[emoji] = true;
                  }
                }

                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: MessageReactionsDisplay(
                    reactions: reactions,
                    currentUserId: _currentUserId,
                    userReactions: userReactions,
                    onReactionTap: (emoji) {
                      _reactionProvider.toggleReaction(
                        _groupChatId,
                        document.id,
                        _currentUserId,
                        emoji,
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      );
    } else if (messageChat.type == TypeMessage.image) {
      return Container(
        margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
        child: Row(
          mainAxisAlignment:
              isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FullPhotoPage(url: messageChat.content),
                  ),
                );
              },
              onLongPress: () {
                HapticFeedback.heavyImpact();
                _showAdvancedMessageOptions(messageChat, document.id);
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.network(
                    messageChat.content,
                    width: MediaQuery.of(context).size.width * 0.65,
                    height: 250,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: MediaQuery.of(context).size.width * 0.65,
                        height: 250,
                        color: const Color(0xFFF2F2F7),
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Container(
                      width: MediaQuery.of(context).size.width * 0.65,
                      height: 250,
                      color: ColorConstants.greyColor2,
                      child: const Icon(Icons.error),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment:
              isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () =>
                  _showAdvancedMessageOptions(messageChat, document.id),
              child: Image.asset(
                'images/${messageChat.content}.gif',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 100,
                  height: 100,
                  color: ColorConstants.greyColor2,
                  child: const Icon(Icons.error),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildStickers() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ColorConstants.greyColor2, width: 0.5),
        ),
        color: Colors.white,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildItemSticker("mimi1"),
              _buildItemSticker("mimi2"),
              _buildItemSticker("mimi3"),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildItemSticker("mimi4"),
              _buildItemSticker("mimi5"),
              _buildItemSticker("mimi6"),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildItemSticker("mimi7"),
              _buildItemSticker("mimi8"),
              _buildItemSticker("mimi9"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemSticker(String stickerName) {
    return TextButton(
      onPressed: () =>
          _onSendMessageWithAutoDelete(stickerName, TypeMessage.sticker),
      child: Image.asset(
        'images/$stickerName.gif',
        width: 50,
        height: 50,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.error),
      ),
    );
  }

  Widget _buildFeaturesMenu() {
    if (!_showFeaturesMenu) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: ColorConstants.greyColor2)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFeatureButton(
              icon: Icons.visibility_off,
              label: 'View Once',
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => SendViewOnceDialog(
                    onSend: (content, type) async {
                      await _viewOnceProvider.sendViewOnceMessage(
                        groupChatId: _groupChatId,
                        currentUserId: _currentUserId,
                        peerId: widget.arguments.peerId,
                        content: content,
                        type: type,
                      );
                      await _loadSmartReplies();
                    },
                  ),
                );
              },
            ),
            _buildFeatureButton(
              icon: Icons.timer,
              label: 'Delete',
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => AutoDeleteSettingsDialog(
                    conversationId: _groupChatId,
                    provider: _autoDeleteProvider,
                  ),
                );
              },
            ),
            _buildFeatureButton(
              icon: Icons.lock,
              label: 'Lock',
              onTap: _showLockOptions,
            ),
            _buildFeatureButton(
              icon: Icons.location_on,
              label: 'Location',
              onTap: _shareLocation,
            ),
            _buildFeatureButton(
              icon: Icons.schedule_send,
              label: 'Schedule',
              onTap: _scheduleMessage,
            ),
            _buildFeatureButton(
              icon: Icons.bubble_chart,
              label: 'Bubble',
              onTap: _createChatBubble,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        if (resourceManager.isDisposed) return;
        setState(() => _showFeaturesMenu = false);
        onTap();
      },
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: ColorConstants.primaryColor, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: ColorConstants.primaryColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    if (!_isRecording) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.red.withOpacity(0.1),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Text(
            'Recording... $_recordingDuration',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            onPressed: _cancelRecording,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            icon: const Icon(Icons.send,
                color: ColorConstants.primaryColor, size: 20),
            onPressed: _stopRecording,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedInput() {
    final showFullFeatures = !widget.isBubbleMode && !widget.isMiniChat;

    if ((widget.isMiniChat || widget.isBubbleMode) && !_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !resourceManager.isDisposed) {
          _focusNode.requestFocus();
        }
      });
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_smartReplies.isNotEmpty && showFullFeatures)
          Container(
            constraints: const BoxConstraints(maxHeight: 60),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SmartReplyWidget(
                replies: _smartReplies,
                onReplySelected: (reply) {
                  if (!resourceManager.isDisposed) {
                    _chatInputController.text = reply;
                    setState(() => _smartReplies = []);
                    _focusNode.requestFocus();
                  }
                },
              ),
            ),
          ),
        _buildRecordingIndicator(),
        Container(
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 12,
            left: 16,
            right: 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingTo != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.reply_rounded,
                          color: Color(0xFF007AFF), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Đang trả lời: ${_replyingTo!.content}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8E8E93),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (mounted) {
                            setState(() => _replyingTo = null);
                            _focusNode.requestFocus();
                          }
                        },
                        child: const Icon(Icons.close_rounded,
                            size: 20, color: Color(0xFF8E8E93)),
                      ),
                    ],
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (showFullFeatures)
                      IconButton(
                        icon: Icon(
                          _showFeaturesMenu
                              ? Icons.close_rounded
                              : Icons.add_circle_rounded,
                        ),
                        color: const Color(0xFF8E8E93),
                        iconSize: 28,
                        onPressed: _toggleFeaturesMenu,
                      ),
                    if (showFullFeatures && !_showFeaturesMenu)
                      IconButton(
                        icon: const Icon(Icons.image_rounded),
                        color: const Color(0xFF8E8E93),
                        iconSize: 26,
                        onPressed: () => _pickImage().then((s) {
                          if (s) _uploadFile();
                        }),
                      ),
                    if (showFullFeatures && !_showFeaturesMenu)
                      IconButton(
                        icon: const Icon(Icons.face_rounded),
                        color: const Color(0xFF8E8E93),
                        iconSize: 26,
                        onPressed: _getSticker,
                      ),
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: 40,
                          maxHeight: 120,
                        ),
                        padding: EdgeInsets.only(
                          left: showFullFeatures ? 0 : 16,
                          right: 8,
                          top: 12,
                          bottom: 12,
                        ),
                        child: TextField(
                          controller: _chatInputController,
                          focusNode: _focusNode,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF111418),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.newline,
                          autofocus: widget.isMiniChat || widget.isBubbleMode,
                          onTapOutside:
                              (widget.isBubbleMode || widget.isMiniChat)
                                  ? null
                                  : (_) {
                                      Utilities.closeKeyboard();
                                    },
                          onSubmitted: (_) {
                            if (!resourceManager.isDisposed) {
                              _onSendMessageWithAutoDelete(
                                _chatInputController.text,
                                TypeMessage.text,
                              );
                              if (widget.isMiniChat || widget.isBubbleMode) {
                                Future.delayed(
                                    const Duration(milliseconds: 100), () {
                                  if (mounted) {
                                    _focusNode.requestFocus();
                                  }
                                });
                              }
                            }
                          },
                          onChanged: (text) {
                            _handleTyping(text);
                            if (text.isNotEmpty &&
                                _smartReplies.isNotEmpty &&
                                mounted &&
                                !resourceManager.isDisposed) {
                              setState(() => _smartReplies = []);
                            }
                          },
                          decoration: InputDecoration.collapsed(
                            hintText: (widget.isBubbleMode || widget.isMiniChat)
                                ? 'Nhắn tin...'
                                : 'Nhắn tin...',
                            hintStyle: const TextStyle(
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: GestureDetector(
                        onTap: () {
                          if (_chatInputController.text.trim().isNotEmpty) {
                            _onSendMessageWithAutoDelete(
                              _chatInputController.text,
                              TypeMessage.text,
                            );
                            if (widget.isMiniChat || widget.isBubbleMode) {
                              Future.delayed(const Duration(milliseconds: 100),
                                  () {
                                if (mounted) _focusNode.requestFocus();
                              });
                            }
                          } else if (showFullFeatures) {
                            _startRecording();
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Color(0xFF007AFF),
                            shape: BoxShape.circle,
                          ),
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _chatInputController,
                            builder: (context, value, child) {
                              final hasText = value.text.trim().isNotEmpty;
                              return Icon(
                                hasText
                                    ? Icons.send_rounded
                                    : Icons.mic_rounded,
                                color: Colors.white,
                                size: 20,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBubbleHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(bottom: BorderSide(color: Color(0xFFF2F2F7), width: 1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundImage: NetworkImage(widget.arguments.peerAvatar),
            radius: 18,
            onBackgroundImageError: (_, __) {},
            child: widget.arguments.peerAvatar.isEmpty
                ? const Icon(Icons.person, size: 18, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.arguments.peerNickname,
                  style: const TextStyle(
                    color: Color(0xFF111418),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                UserStatusIndicator(
                  userId: widget.arguments.peerId,
                  showText: true,
                  size: 8,
                  textColor: const Color(0xFF8E8E93),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_rounded, color: Color(0xFF8E8E93)),
            onPressed: () {
              _focusNode.unfocus();
              _bubbleChannel.invokeMethod('minimize');
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF8E8E93)),
            onPressed: () {
              _focusNode.unfocus();
              _bubbleChannel.invokeMethod('close');
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChatHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(bottom: BorderSide(color: Color(0xFFF2F2F7), width: 1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundImage: NetworkImage(widget.arguments.peerAvatar),
            radius: 18,
            onBackgroundImageError: (_, __) {},
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.arguments.peerNickname,
              style: const TextStyle(
                color: Color(0xFF111418),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_rounded, color: Color(0xFF8E8E93)),
            onPressed: () {
              _focusNode.unfocus();
              _miniChatChannel.invokeMethod('minimize');
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF8E8E93)),
            onPressed: () {
              _focusNode.unfocus();
              _miniChatChannel.invokeMethod('close');
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildChatContent() {
    return Stack(
      children: [
        Column(
          children: [
            const OfflineIndicator(),
            _buildPinnedMessages(),
            _buildListMessage(),
            _buildTypingIndicator(),
            if (_isShowSticker && !widget.isMiniChat && !widget.isBubbleMode)
              _buildStickers(),
            if (_showFeaturesMenu && !widget.isMiniChat && !widget.isBubbleMode)
              _buildFeaturesMenu(),
            _buildAdvancedInput(),
          ],
        ),
        Positioned(
          child: _isLoading ? const LoadingView() : const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isBubbleMode) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        body: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _minimizeBubble();
          },
          child: Column(
            children: [
              _buildBubbleHeader(),
              Expanded(child: _buildChatContent()),
            ],
          ),
        ),
      );
    }

    if (widget.isMiniChat) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        body: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _focusNode.unfocus();
            _miniChatChannel.invokeMethod('minimize');
          },
          child: Column(
            children: [
              _buildMiniChatHeader(),
              Expanded(child: _buildChatContent()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.95),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: widget.isWebMode
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Color(0xFF007AFF)),
                onPressed: _onBackPress,
              ),
        title: InkWell(
          onTap: () async {
            if (resourceManager.isDisposed) return;
            final userDoc = await FirebaseFirestore.instance
                .collection(FirestoreConstants.pathUserCollection)
                .doc(widget.arguments.peerId)
                .get();

            if (userDoc.exists && mounted && !resourceManager.isDisposed) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfilePage(
                    userChat: UserChat.fromDocument(userDoc),
                  ),
                ),
              );
            }
          },
          child: Row(
            children: [
              AvatarWithStatus(
                userId: widget.arguments.peerId,
                photoUrl: widget.arguments.peerAvatar,
                size: 40,
                indicatorSize: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.arguments.peerNickname,
                      style: const TextStyle(
                        color: Color(0xFF111418),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    UserStatusIndicator(
                      userId: widget.arguments.peerId,
                      showText: true,
                      size: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        centerTitle: false,
        actions: _buildAppBarActions(),
        iconTheme: const IconThemeData(color: Color(0xFF007AFF)),
      ),
      body: SafeArea(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _onBackPress();
          },
          child: _buildChatContent(),
        ),
      ),
    );
  }
}

class ChatPageArguments {
  final String peerId;
  final String peerAvatar;
  final String peerNickname;

  ChatPageArguments({
    required this.peerId,
    required this.peerAvatar,
    required this.peerNickname,
  });
}

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
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ✅ GIAI ĐOẠN 5: ADD isBubbleMode PARAMETER & ADAPTATIONS
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.arguments,
    this.isMiniChat = false,
    this.isBubbleMode = false, // ✅ NEW: Bubble mode flag
  });

  final ChatPageArguments arguments;
  final bool isMiniChat;
  final bool isBubbleMode; // ✅ NEW

  @override
  ChatPageState createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage>
    with WidgetsBindingObserver, ResourceManagerMixin {
  late final String _currentUserId;
  UserPresenceProvider? _presenceProvider;

  // ✅ GIAI ĐOẠN 4: Use UnifiedBubbleService instead of ChatBubbleService
  UnifiedBubbleService? _unifiedBubbleService;

  // ✅ ADD: Channel cho giao tiếp Mini Chat và Bubble
  static const MethodChannel _miniChatChannel =
      MethodChannel('mini_chat_channel');
  static const MethodChannel _bubbleChannel =
      MethodChannel('bubble_chat_channel'); // ✅ NEW

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
  VoiceMessageProvider? _voiceProvider;
  LocationProvider? _locationProvider;
  TranslationProvider? _translationProvider;

  List<DocumentSnapshot> _pinnedMessages = [];

  List<SmartReply> _smartReplies = [];
  String _lastReceivedMessage = '';

  MessageChat? _replyingTo;
  bool _conversationLockedChecked = false;

  // ✅ FIX 14: Add deduplication for message listener
  final Set<String> _processedMessageIds = {};
  bool _isProcessingMessage = false;

  bool _showFeaturesMenu = false;

  bool _isRecording = false;
  String _recordingDuration = "0:00";
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  final Map<String, Timer> _scheduledMessages = {};
  final Map<String, String> _scheduledMessageContents = {};

  @override
  void initState() {
    super.initState();

    // ✅ FIX: Initialize controllers in initState
    _chatInputController = TextEditingController();
    _listScrollController = ScrollController();
    _focusNode = FocusNode();

    WidgetsBinding.instance.addObserver(this);

    // ✅ FIX: Add listeners with resource manager
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

    // ✅ GIAI ĐOẠN 4: Use UnifiedBubbleService
    _unifiedBubbleService = context.read<UnifiedBubbleService>();

    // Setup mini chat message listener (bubbleClickStream)
    final miniChatSub = _unifiedBubbleService?.bubbleClickStream.listen(
      (event) {
        if (event.userId == widget.arguments.peerId) {
          print('💬 Bubble clicked for: ${event.userName}');

          // Show notification
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
    _translationProvider = TranslationProvider();

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

  void _scrollListener() {
    if (resourceManager.isDisposed || !_listScrollController.hasClients) return;
    final pos = _listScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 &&
        !_listScrollController.position.outOfRange &&
        _limit <= _listMessage.length) {
      if (mounted) {
        setState(() {
          _limit += _limitIncrement;
        });
      }
    }
  }

  // ✅ ADD: Better keyboard handling for mini chat
  void _ensureKeyboardVisibility() {
    if (widget.isMiniChat) {
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted && _focusNode.hasFocus && !resourceManager.isDisposed) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  // ✅ MODIFY: _onFocusChange to handle mini chat
  void _onFocusChange() {
    if (resourceManager.isDisposed || !mounted) return;

    if (_focusNode.hasFocus) {
      setState(() {
        _isShowSticker = false;
        _showFeaturesMenu = false;
      });

      // ✅ In mini chat, ensure keyboard stays visible
      if (widget.isMiniChat) {
        _ensureKeyboardVisibility();
      }
    }
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

    // ✅ THÊM DÒNG NÀY - Setup listener SAU KHI có _groupChatId
    _setupIncomingMessageListener();

    _chatProvider.updateDataFirestore(
      FirestoreConstants.pathUserCollection,
      _currentUserId,
      {FirestoreConstants.chattingWith: peerId},
    );

    Future.delayed(Duration(milliseconds: 500), () {
      if (!resourceManager.isDisposed && mounted) {
        _markMessagesAsRead();
      }
    });
  }

  void _loadPinnedMessages() {
    if (resourceManager.isDisposed) return;

    final subscription =
        _messageProvider.getPinnedMessages(_groupChatId).listen(
      (snapshot) {
        if (!mounted || resourceManager.isDisposed) return;
        setState(() {
          _pinnedMessages = snapshot.docs;
        });
      },
      onError: (err) {
        ErrorLogger.logError(err, null, context: 'Load Pinned Messages');
      },
    );

    resourceManager.addSubscription(subscription);
  }

  Future<bool> _pickImage() async {
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

  void _getSticker() {
    if (resourceManager.isDisposed) return;
    _focusNode.unfocus();
    setState(() {
      _isShowSticker = !_isShowSticker;
      _showFeaturesMenu = false;
    });
  }

  void _handleTyping(String text) {
    if (_presenceProvider == null || resourceManager.isDisposed) return;

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

  // ========================================
  // STEP 3: Update _setupIncomingMessageListener (with GIAI ĐOẠN 7 + FIX 14)
  // ========================================

  void _setupIncomingMessageListener() {
    if (resourceManager.isDisposed) return;

    if (_groupChatId.isEmpty || _currentUserId.isEmpty) {
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

        // ✅ FIX 14: Prevent concurrent processing
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

              // ✅ FIX 14: Deduplication check
              if (_processedMessageIds.contains(docId)) {
                print('ℹ️ Message already processed: $docId');
                continue;
              }

              _processedMessageIds.add(docId);
              print('✅ Processing new message: $docId');

              // ✅ FIX 14: Cleanup old processed IDs (keep last 100)
              if (_processedMessageIds.length > 100) {
                final toRemove = _processedMessageIds.length - 100;
                final oldIds = _processedMessageIds.take(toRemove).toList();
                _processedMessageIds.removeAll(oldIds);
                print('🗑️ Cleaned ${oldIds.length} old message IDs');
              }

              // Process message
              final data = change.doc.data();
              if (data != null) {
                final content =
                    data[FirestoreConstants.content] as String? ?? '';
                final type = data[FirestoreConstants.type] as int? ?? 0;

                // Update bubble if it exists
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

  /// Open location in Google Maps
  Future<void> _openLocationInMaps(String mapsUrl) async {
    try {
      final uri = Uri.parse(mapsUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('✅ Opened Maps: $mapsUrl');
      } else {
        Fluttertoast.showToast(
          msg: '❌ Cannot open Google Maps',
          backgroundColor: Colors.red,
        );
        print('❌ Cannot launch URL: $mapsUrl');
      }
    } catch (e) {
      print('❌ Error opening Maps: $e');
      Fluttertoast.showToast(
        msg: '❌ Failed to open location',
        backgroundColor: Colors.red,
      );
    }
  }

  // ✅ GIAI ĐOẠN 4: Update _showChatBubbleIfNeeded
  Future<void> _showChatBubbleIfNeeded() async {
    if (resourceManager.isDisposed) return;

    final lifecycleState = WidgetsBinding.instance.lifecycleState;

    if (lifecycleState != AppLifecycleState.resumed) {
      await _unifiedBubbleService?.showChatBubble(
        userId: widget.arguments.peerId,
        userName: widget.arguments.peerNickname,
        avatarUrl: widget.arguments.peerAvatar,
      );
    }
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

        return TypingIndicator(userName: widget.arguments.peerNickname);
      },
    );
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
        if (snapshot.docs.isNotEmpty && mounted) {
          _markMessagesAsRead();
        }
      },
      onError: (error) {
        ErrorLogger.logError(error, null, context: 'Setup Auto Read');
      },
    );

    resourceManager.addSubscription(subscription);
  }

  Future<void> _uploadFile() async {
    if (_imageFile == null) return;

    try {
      final fileName = DateTime.now().millisecondsSinceEpoch.toString();
      final uploadTask = _chatProvider.uploadFile(_imageFile!, fileName);
      final snapshot = await uploadTask;
      _imageUrl = await snapshot.ref.getDownloadURL();

      if (!mounted || resourceManager.isDisposed) return;
      setState(() {
        _isLoading = false;
      });

      await _onSendMessageWithAutoDelete(_imageUrl, TypeMessage.image);
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'Upload File');

      if (mounted && !resourceManager.isDisposed) {
        setState(() {
          _isLoading = false;
        });
      }
      Fluttertoast.showToast(msg: 'Upload failed');
    }
  }

  // ========================================
  // STEP 1: Update _onSendMessageWithAutoDelete (with GIAI ĐOẠN 7)
  // ========================================

  Future<void> _onSendMessageWithAutoDelete(String content, int type) async {
    if (resourceManager.isDisposed) return;

    if (content.trim().isEmpty) {
      Fluttertoast.showToast(
        msg: 'Nothing to send',
        backgroundColor: ColorConstants.greyColor,
      );
      return;
    }

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

      // ✅ GIAI ĐOẠN 7: Update bubble with sent message
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
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ========================================
  // STEP 2: Add NEW METHOD - _updateBubbleWithMessage (GIAI ĐOẠN 7)
  // ========================================

  /// ✅ GIAI ĐOẠN 7: Update bubble notification with message
  Future<void> _updateBubbleWithMessage(String content, int type,
      {required bool isFromUser}) async {
    if (_unifiedBubbleService == null || resourceManager.isDisposed) return;

    try {
      // Check if bubble exists for this conversation
      if (!_unifiedBubbleService!.isBubbleActive(widget.arguments.peerId)) {
        return; // No bubble, skip update
      }

      // Determine message type
      String messageType = 'text';
      String displayMessage = content;

      switch (type) {
        case TypeMessage.text:
          messageType = 'text';
          // Check if it's a location
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
        case 3: // Voice
          messageType = 'voice';
          displayMessage = '🎤 Voice message';
          break;
        default:
          messageType = 'text';
      }

      // Send to bubble
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

  void _showAdvancedMessageOptions(MessageChat message, String messageId) {
    if (resourceManager.isDisposed) return;

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
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
        title: Text('Delete Message'),
        content: Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
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
    if (resourceManager.isDisposed || !mounted) return;
    setState(() {
      _replyingTo = message;
    });
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

    DateTime selectedTime = DateTime.now().add(Duration(hours: 1));

    return await showDialog<DateTime>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Set Reminder Time'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('Date'),
                    subtitle: Text(
                      DateFormat('MMM dd, yyyy').format(selectedTime),
                    ),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedTime,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(Duration(days: 365)),
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
                    title: Text('Time'),
                    subtitle: Text(DateFormat('HH:mm').format(selectedTime)),
                    trailing: Icon(Icons.access_time),
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
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selectedTime),
                  child: Text('Set'),
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

      if (success) {
        Fluttertoast.showToast(msg: '⏰ Reminder set successfully');
      } else {
        Fluttertoast.showToast(msg: 'Failed to set reminder');
      }
    }
  }

  Future<void> _translateMessage(String content) async {
    if (_translationProvider == null || resourceManager.isDisposed) return;

    showDialog(
      context: context,
      builder: (context) => TranslationDialog(
        originalText: content,
        translationProvider: _translationProvider!,
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
      setState(() {
        _conversationLockedChecked = true;
      });
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

      if (result['success'] == true) {
        return true;
      }

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

  void _showReminders() {
    if (resourceManager.isDisposed) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Reminders')),
          body: StreamBuilder<QuerySnapshot>(
            stream: _reminderProvider.getUserReminders(_currentUserId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }

              final reminders = snapshot.data!.docs;

              if (reminders.isEmpty) {
                return Center(child: Text('No reminders'));
              }

              return ListView.builder(
                itemCount: reminders.length,
                itemBuilder: (context, index) {
                  final reminder = MessageReminder.fromDocument(
                    reminders[index],
                  );

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
                      icon: Icon(Icons.delete, color: Colors.red),
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

  // ✅ GIAI ĐOẠN 4: Update _createChatBubble to use UnifiedBubbleService
  Future<void> _createChatBubble() async {
    if (_unifiedBubbleService == null || resourceManager.isDisposed) {
      Fluttertoast.showToast(msg: 'Bubble service not available');
      return;
    }

    // Check if bubbles are supported
    if (!_unifiedBubbleService!.isSupported) {
      Fluttertoast.showToast(msg: 'Chat bubbles not supported on this device');
      return;
    }

    // Check permissions (only needed for WindowManager on Android < 11)
    final hasPermission = await _unifiedBubbleService!.hasOverlayPermission();
    if (!hasPermission) {
      final granted = await _unifiedBubbleService!.requestOverlayPermission();
      if (!granted) {
        Fluttertoast.showToast(msg: 'Overlay permission required');
        return;
      }
    }

    // Show implementation info
    final impl = _unifiedBubbleService!.getImplementationInfo();
    print('🎈 Creating bubble using: $impl');

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create Chat Bubble'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose how to open this conversation:'),
            SizedBox(height: 8),
            Text(
              'Using: $impl',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'bubble'),
            child: Text('Bubble Only'),
          ),
          // ✅ Only show mini chat for WindowManager
          if (_unifiedBubbleService!.currentImplementation ==
              BubbleImplementation.windowManager)
            TextButton(
              onPressed: () => Navigator.pop(context, 'minichat'),
              child: Text('Mini Chat'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice == null) return;

    if (choice == 'bubble') {
      // Create bubble
      final success = await _unifiedBubbleService!.showChatBubble(
        userId: widget.arguments.peerId,
        userName: widget.arguments.peerNickname,
        avatarUrl: widget.arguments.peerAvatar,
      );

      if (success) {
        Fluttertoast.showToast(
          msg: '💬 Chat bubble created',
          backgroundColor: Colors.green,
        );
      } else {
        Fluttertoast.showToast(
          msg: '❌ Failed to create bubble',
          backgroundColor: Colors.red,
        );
      }
    } else if (choice == 'minichat') {
      // Show mini chat (only works with WindowManager)
      final success = await _unifiedBubbleService!.showMiniChat(
        userId: widget.arguments.peerId,
        userName: widget.arguments.peerNickname,
        avatarUrl: widget.arguments.peerAvatar,
      );

      if (success) {
        Fluttertoast.showToast(
          msg: '💬 Mini chat opened',
          backgroundColor: Colors.green,
        );
      } else {
        Fluttertoast.showToast(
          msg: '⚠️ Mini chat not supported with Bubble API',
          backgroundColor: Colors.orange,
        );
      }
    }
  }

  List<Widget> _buildAppBarActions() {
    return [
      // Video Call button
      IconButton(
        icon: Icon(Icons.videocam, color: ColorConstants.primaryColor),
        onPressed: () {
          Fluttertoast.showToast(
            msg: '🎥 Video Call feature coming soon!',
            backgroundColor: ColorConstants.primaryColor,
          );
        },
        tooltip: 'Video Call',
      ),

      // Voice Call button
      IconButton(
        icon: Icon(Icons.phone, color: ColorConstants.primaryColor),
        onPressed: () {
          Fluttertoast.showToast(
            msg: '📞 Voice Call feature coming soon!',
            backgroundColor: ColorConstants.primaryColor,
          );
        },
        tooltip: 'Voice Call',
      ),

      // More options menu
      IconButton(
        icon: Icon(Icons.more_vert),
        onPressed: _showChatOptionsMenu,
        tooltip: 'More options',
      ),
    ];
  }

  // ========================================
  // STEP 5: Update _buildChatOptionsMenu (with GIAI ĐOẠN 7)
  // ========================================

  void _showChatOptionsMenu() {
    if (resourceManager.isDisposed) return;

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
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
            // Search Messages
            ListTile(
              leading: Icon(Icons.search, color: ColorConstants.primaryColor),
              title: Text('Search Messages'),
              subtitle: Text('Search in conversation'),
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

            // Show Reminders
            ListTile(
              leading:
                  Icon(Icons.notifications, color: ColorConstants.primaryColor),
              title: Text('Reminders'),
              subtitle: Text('View all reminders'),
              onTap: () {
                Navigator.pop(context);
                _showReminders();
              },
            ),

            // ✅ GIAI ĐOẠN 4: Show current bubble implementation
            if (_unifiedBubbleService != null)
              ListTile(
                leading: Icon(Icons.info_outline, color: Colors.blue),
                title: Text('Bubble Implementation'),
                subtitle: Text(_unifiedBubbleService!.getImplementationInfo()),
                onTap: () {
                  Navigator.pop(context);
                  _showBubbleInfo();
                },
              ),

            // ✅ GIAI ĐOẠN 7: Add debug option
            if (kDebugMode) // Only in debug mode
              ListTile(
                leading: Icon(Icons.bug_report, color: Colors.orange),
                title: Text('Bubble Debug'),
                subtitle: Text('View message history & stats'),
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

  // ✅ GIAI ĐOẠN 4: Show bubble implementation info
  void _showBubbleInfo() {
    if (_unifiedBubbleService == null) return;

    final impl = _unifiedBubbleService!.getImplementationInfo();
    final canMigrate = _unifiedBubbleService!.currentImplementation ==
        BubbleImplementation.windowManager;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bubble Implementation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current: $impl'),
            SizedBox(height: 16),
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

                if (success) {
                  Fluttertoast.showToast(
                    msg: '✅ Migrated to Bubble API',
                    backgroundColor: Colors.green,
                  );
                } else {
                  Fluttertoast.showToast(
                    msg: '❌ Migration failed',
                    backgroundColor: Colors.red,
                  );
                }
              },
              child: Text('Migrate Now'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  // ========================================
  // STEP 4: Add _showBubbleDebugInfo (GIAI ĐOẠN 7)
  // ========================================

  void _showBubbleDebugInfo() async {
    if (_unifiedBubbleService == null) return;

    try {
      // Get message count
      final count = await _unifiedBubbleService!.getMessageCount(
        widget.arguments.peerId,
      );

      // Get stats
      final stats = await _unifiedBubbleService!.getBubbleStats();

      // Log state
      await _unifiedBubbleService!.logBubbleState();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Bubble Debug Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Message count: $count'),
              SizedBox(height: 8),
              Text('Active conversations: ${stats['activeConversations']}'),
              Text('Total messages: ${stats['totalMessages']}'),
              Text('Average messages: ${stats['averageMessages']}'),
              SizedBox(height: 8),
              Text('Check Android logs for detailed state',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _unifiedBubbleService!.clearMessageHistory(
                  widget.arguments.peerId,
                );
                Navigator.pop(context);
                Fluttertoast.showToast(msg: 'History cleared');
              },
              child: Text('Clear History'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ Error showing debug info: $e');
    }
  }

  void _showLockOptions() async {
    if (resourceManager.isDisposed) return;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Lock Conversation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Set PIN'),
              onTap: () => Navigator.pop(context, 'set_pin'),
            ),
            ListTile(
              leading: Icon(Icons.lock_open),
              title: Text('Remove Lock'),
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

  void _toggleFeaturesMenu() {
    if (resourceManager.isDisposed || !mounted) return;
    setState(() {
      _showFeaturesMenu = !_showFeaturesMenu;
      _isShowSticker = false;
    });
  }

  Widget _buildFeaturesMenu() {
    if (!_showFeaturesMenu) return SizedBox.shrink();

    return Container(
      constraints: BoxConstraints(maxHeight: 110),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                setState(() => _showFeaturesMenu = false);
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
                setState(() => _showFeaturesMenu = false);
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
              onTap: () {
                setState(() => _showFeaturesMenu = false);
                _showLockOptions();
              },
            ),
            _buildFeatureButton(
              icon: Icons.location_on,
              label: 'Location',
              onTap: () {
                setState(() => _showFeaturesMenu = false);
                _shareLocation();
              },
            ),
            _buildFeatureButton(
              icon: Icons.schedule_send,
              label: 'Schedule',
              onTap: () {
                setState(() => _showFeaturesMenu = false);
                _scheduleMessage();
              },
            ),
            _buildFeatureButton(
              icon: Icons.bubble_chart,
              label: 'Bubble',
              onTap: () {
                setState(() => _showFeaturesMenu = false);
                _createChatBubble();
              },
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
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: ColorConstants.primaryColor, size: 26),
            SizedBox(height: 4),
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

  Future<void> _shareLocation() async {
    if (_locationProvider == null || resourceManager.isDisposed) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      // ✅ Request permission first
      final hasPermission =
          await _locationProvider!.requestLocationPermission();

      if (!hasPermission) {
        if (mounted && !resourceManager.isDisposed)
          setState(() => _isLoading = false);
        Fluttertoast.showToast(
          msg: '📍 Location permission required',
          backgroundColor: Colors.red,
        );
        return;
      }

      // ✅ Get location with full details
      final locationData =
          await _locationProvider!.getCurrentLocationWithDetails();

      if (mounted && !resourceManager.isDisposed)
        setState(() => _isLoading = false);

      if (locationData != null && !resourceManager.isDisposed) {
        // ✅ Format message with clickable link
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
      if (mounted && !resourceManager.isDisposed)
        setState(() => _isLoading = false);
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
      if (mounted) {
        Fluttertoast.showToast(msg: 'Invalid time');
      }
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

      _recordingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
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
      if (mounted && !resourceManager.isDisposed)
        setState(() => _isRecording = false);
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

    if (mounted && !resourceManager.isDisposed)
      setState(() => _isLoading = false);

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
    if (mounted && !resourceManager.isDisposed)
      setState(() => _isRecording = false);
  }

  Widget _buildPinnedMessages() {
    if (_pinnedMessages.isEmpty) return SizedBox.shrink();

    return Container(
      height: 60,
      color: ColorConstants.greyColor2.withOpacity(0.3),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _pinnedMessages.length,
        itemExtent: 180,
        itemBuilder: (context, index) {
          final message = MessageChat.fromDocument(_pinnedMessages[index]);
          return GestureDetector(
            onTap: () {
              // TODO: Scroll to message
            },
            child: Container(
              width: 170,
              margin: EdgeInsets.symmetric(horizontal: 4),
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.push_pin,
                    size: 14,
                    color: ColorConstants.primaryColor,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
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
                      padding: EdgeInsets.all(10),
                      itemBuilder: (_, index) =>
                          _buildItemMessage(index, snapshot.data?.docs[index]),
                      itemCount: snapshot.data?.docs.length,
                      reverse: true,
                      controller: _listScrollController,
                    );
                  } else {
                    return Center(child: Text("No message here yet..."));
                  }
                } else {
                  return Center(
                    child: CircularProgressIndicator(
                      color: ColorConstants.themeColor,
                    ),
                  );
                }
              },
            )
          : Center(
              child: CircularProgressIndicator(
                color: ColorConstants.themeColor,
              ),
            ),
    );
  }

  Widget _buildItemMessage(int index, DocumentSnapshot? document) {
    if (document == null) return SizedBox.shrink();

    final messageChat = MessageChat.fromDocument(document);
    final isMyMessage = messageChat.idFrom == _currentUserId;

    final data = document.data() as Map<String, dynamic>?;
    final isViewOnce = data?['isViewOnce'] ?? false;
    final isViewed = data?['isViewed'] ?? false;

    if (isViewOnce) {
      return Container(
        margin: EdgeInsets.only(bottom: 10),
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

    // Voice Message
    if (messageChat.type == 3 && _voiceProvider != null) {
      return Container(
        margin: EdgeInsets.only(bottom: 10),
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

    // Text Message
    if (messageChat.type == TypeMessage.text) {
      final location =
          _locationProvider?.parseLocationFromMessage(messageChat.content);

      return Container(
        margin: EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment:
              isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: () =>
                      _showAdvancedMessageOptions(messageChat, document.id),
                  onDoubleTap: () => _showReactionPicker(document.id),
                  child: Container(
                    padding: EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: 250),
                    decoration: BoxDecoration(
                      color: isMyMessage
                          ? ColorConstants.primaryColor
                          : ColorConstants.greyColor2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (messageChat.isDeleted)
                          Text(
                            messageChat.content,
                            style: TextStyle(
                              color: isMyMessage
                                  ? Colors.white70
                                  : ColorConstants.greyColor,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else if (location != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Location icon và title
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    color:
                                        isMyMessage ? Colors.white : Colors.red,
                                    size: 20,
                                  ),
                                  SizedBox(width: 4),
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
                              SizedBox(height: 8),

                              // Address
                              Text(
                                location.address,
                                style: TextStyle(
                                  color: isMyMessage
                                      ? Colors.white
                                      : Colors.black87,
                                  fontSize: 13,
                                ),
                              ),

                              SizedBox(height: 8),

                              // Clickable Maps link
                              InkWell(
                                onTap: () =>
                                    _openLocationInMaps(location.mapsUrl),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
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
                                      SizedBox(width: 4),
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
                                      SizedBox(width: 4),
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
                        else
                          Text(
                            messageChat.content,
                            style: TextStyle(
                              color:
                                  isMyMessage ? Colors.white : Colors.black87,
                            ),
                          ),
                        if (messageChat.editedAt != null)
                          Text(
                            '(edited)',
                            style: TextStyle(
                              fontSize: 10,
                              color: isMyMessage
                                  ? Colors.white70
                                  : ColorConstants.greyColor,
                            ),
                          ),
                        if (isMyMessage && !messageChat.isDeleted)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ReadReceiptWidget(
                              isRead: messageChat.isRead,
                              size: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!messageChat.isDeleted) ...[
                  SizedBox(width: 4),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.add_reaction, size: 18),
                        onPressed: () => _showReactionPicker(document.id),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                      if (!isMyMessage)
                        IconButton(
                          icon: Icon(Icons.alarm_add, size: 18),
                          onPressed: () =>
                              _setMessageReminder(messageChat, document.id),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            // Reactions display
            StreamBuilder<QuerySnapshot>(
              stream: _reactionProvider.getReactions(_groupChatId, document.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return SizedBox.shrink();
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
    }
    // Image Message
    else if (messageChat.type == TypeMessage.image) {
      return Container(
        margin: EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment:
              isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FullPhotoPage(url: messageChat.content),
                  ),
                );
              },
              onLongPress: () =>
                  _showAdvancedMessageOptions(messageChat, document.id),
              child: Container(
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.network(
                  messageChat.content,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: 200,
                      height: 200,
                      color: ColorConstants.greyColor2,
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
                    width: 200,
                    height: 200,
                    color: ColorConstants.greyColor2,
                    child: Icon(Icons.error),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Sticker
    else {
      return Container(
        margin: EdgeInsets.only(bottom: 10),
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
                  child: Icon(Icons.error),
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
      padding: EdgeInsets.symmetric(vertical: 8),
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
        errorBuilder: (_, __, ___) => Icon(Icons.error),
      ),
    );
  }

  // ✅ BUBBLE MODE INPUT ADJUSTMENTS
  Widget _buildAdvancedInput() {
    // ✅ Disable complex features in bubble mode/mini chat
    final showFullFeatures = !widget.isBubbleMode && !widget.isMiniChat;

    // ✅ Auto-focus in mini chat/bubble mode
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
        // Smart Replies (only in normal mode)
        if (_smartReplies.isNotEmpty && showFullFeatures)
          Container(
            constraints: BoxConstraints(maxHeight: 60),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SmartReplyWidget(
                replies: _smartReplies,
                onReplySelected: (reply) {
                  if (!resourceManager.isDisposed) {
                    _chatInputController.text = reply;
                    setState(() => _smartReplies = []);
                    // ✅ Refocus after selecting reply
                    _focusNode.requestFocus();
                  }
                },
              ),
            ),
          ),

        // Reply indicator
        if (_replyingTo != null)
          Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: 50),
            color: ColorConstants.greyColor2.withOpacity(0.2),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Replying: ${_replyingTo!.content}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18),
                  onPressed: () {
                    if (mounted && !resourceManager.isDisposed) {
                      setState(() => _replyingTo = null);
                      // ✅ Refocus after closing reply
                      _focusNode.requestFocus();
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

        // Recording indicator
        if (_isRecording)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            color: Colors.red.withOpacity(0.1),
            child: Row(
              children: [
                Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                SizedBox(width: 8),
                Text(
                  'Recording... $_recordingDuration',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: _cancelRecording,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: Icon(
                    Icons.send,
                    color: ColorConstants.primaryColor,
                    size: 20,
                  ),
                  onPressed: _stopRecording,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),

        // ✅ KEYBOARD FIX: Input area
        Container(
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: 50,
            maxHeight: 120,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: ColorConstants.greyColor2, width: 0.5),
            ),
            color: Colors.white,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // More options button (Disabled in Mini Chat/Bubble Mode)
              if (showFullFeatures)
                Material(
                  color: Colors.white,
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 1),
                    child: IconButton(
                      icon: Icon(
                        _showFeaturesMenu ? Icons.close : Icons.more_horiz,
                        color: ColorConstants.primaryColor,
                        size: 24,
                      ),
                      onPressed: _toggleFeaturesMenu,
                      padding: EdgeInsets.all(8),
                      constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  ),
                ),

              // Image picker (Disabled in Mini Chat/Bubble Mode)
              if (showFullFeatures)
                Material(
                  color: Colors.white,
                  child: IconButton(
                    icon: Icon(Icons.image, size: 24),
                    onPressed: () {
                      _pickImage().then((isSuccess) {
                        if (isSuccess) _uploadFile();
                      });
                    },
                    color: ColorConstants.primaryColor,
                    padding: EdgeInsets.all(8),
                    constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),

              // Sticker button (Disabled in Mini Chat/Bubble Mode)
              if (showFullFeatures)
                Material(
                  color: Colors.white,
                  child: IconButton(
                    icon: Icon(Icons.face, size: 24),
                    onPressed: _getSticker,
                    color: ColorConstants.primaryColor,
                    padding: EdgeInsets.all(8),
                    constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),

              // ✅ KEYBOARD FIX: Text input with better handling
              Expanded(
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: 40,
                    maxHeight: 100,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextField(
                    // ✅ CRITICAL: Don't close keyboard on outside tap in mini chat/bubble mode
                    onTapOutside: (widget.isBubbleMode || widget.isMiniChat)
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
                        // ✅ Refocus after sending in mini chat/bubble mode
                        if (widget.isMiniChat || widget.isBubbleMode) {
                          Future.delayed(Duration(milliseconds: 100), () {
                            if (mounted) _focusNode.requestFocus();
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
                    style: TextStyle(
                      color: ColorConstants.primaryColor,
                      fontSize: 15,
                    ),
                    controller: _chatInputController,
                    decoration: InputDecoration.collapsed(
                      hintText: (widget.isBubbleMode || widget.isMiniChat)
                          ? 'Type...'
                          : 'Type your message...',
                      hintStyle: TextStyle(color: ColorConstants.greyColor),
                    ),
                    focusNode: _focusNode,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    // ✅ CRITICAL: Auto-focus in mini chat/bubble mode (triggers keyboard)
                    autofocus: widget.isMiniChat || widget.isBubbleMode,
                  ),
                ),
              ),

              // Voice button (disabled in mini chat/bubble mode)
              if (!_isRecording && _voiceProvider != null && showFullFeatures)
                Material(
                  color: Colors.white,
                  child: IconButton(
                    icon: Icon(Icons.mic, size: 24),
                    onPressed: _startRecording,
                    color: ColorConstants.primaryColor,
                    padding: EdgeInsets.all(8),
                    constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),

              // Send button
              Material(
                color: Colors.white,
                child: IconButton(
                  icon: Icon(Icons.send, size: 24),
                  onPressed: () {
                    if (!resourceManager.isDisposed) {
                      _onSendMessageWithAutoDelete(
                        _chatInputController.text,
                        TypeMessage.text,
                      );
                      // ✅ Keep focus in mini chat/bubble mode
                      if (widget.isMiniChat || widget.isBubbleMode) {
                        Future.delayed(Duration(milliseconds: 100), () {
                          if (mounted) _focusNode.requestFocus();
                        });
                      }
                    }
                  },
                  color: ColorConstants.primaryColor,
                  padding: EdgeInsets.all(8),
                  constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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

  // ✅ BUBBLE ACTIONS
  void _minimizeBubble() {
    print('📦 Minimizing bubble');

    // Close keyboard if open
    _focusNode.unfocus();

    // Tell BubbleActivity to minimize
    _bubbleChannel.invokeMethod('minimize');
  }

  void _closeBubble() {
    print('❌ Closing bubble');

    // Close keyboard
    _focusNode.unfocus();

    // Tell BubbleActivity to close
    _bubbleChannel.invokeMethod('close');
  }

  // ✅ BUBBLE HEADER
  Widget _buildBubbleHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ColorConstants.primaryColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Drag handle indicator
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Peer Avatar
          CircleAvatar(
            backgroundImage: NetworkImage(widget.arguments.peerAvatar),
            radius: 18,
            onBackgroundImageError: (_, __) {},
            child: widget.arguments.peerAvatar.isEmpty
                ? Icon(Icons.person, size: 18, color: Colors.grey)
                : null,
          ),
          SizedBox(width: 8),

          // Peer Nickname
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.arguments.peerNickname,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // ✅ Show online status
                UserStatusIndicator(
                  userId: widget.arguments.peerId,
                  showText: true,
                  size: 8,
                  textColor: Colors.white70,
                ),
              ],
            ),
          ),

          // Minimize button
          IconButton(
            icon: Icon(Icons.remove, color: Colors.white, size: 22),
            onPressed: _minimizeBubble,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Minimize',
          ),
          SizedBox(width: 4),

          // Close button
          IconButton(
            icon: Icon(Icons.close, color: Colors.white, size: 22),
            onPressed: _closeBubble,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  // ✅ MODIFY: _buildMiniChatHeader to use the correct buttons and close keyboard
  Widget _buildMiniChatHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ColorConstants.primaryColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // Drag handle indicator
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Peer Avatar
          CircleAvatar(
            backgroundImage: NetworkImage(widget.arguments.peerAvatar),
            radius: 18,
            onBackgroundImageError: (_, __) {},
          ),
          SizedBox(width: 8),

          // Peer Nickname
          Expanded(
            child: Text(
              widget.arguments.peerNickname,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Minimize button
          IconButton(
            icon: Icon(Icons.remove, color: Colors.white, size: 22),
            onPressed: () {
              // ✅ Close keyboard before minimizing
              _focusNode.unfocus();
              _miniChatChannel.invokeMethod('minimize');
            },
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          SizedBox(width: 4),

          // Close button
          IconButton(
            icon: Icon(Icons.close, color: Colors.white, size: 22),
            onPressed: () {
              // ✅ Close keyboard before closing
              _focusNode.unfocus();
              _miniChatChannel.invokeMethod('close');
            },
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 36, minHeight: 36),
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
            _buildPinnedMessages(),
            _buildListMessage(),
            _buildTypingIndicator(),
            // Sticker và Feature Menu chỉ nên hiển thị trong main app (Normal Mode)
            if (_isShowSticker &&
                !widget.isMiniChat &&
                !widget.isBubbleMode) // ✅ Check Bubble Mode
              _buildStickers(),
            if (_showFeaturesMenu &&
                !widget.isMiniChat &&
                !widget.isBubbleMode) // ✅ Check Bubble Mode
              _buildFeaturesMenu(),
            _buildAdvancedInput(),
          ],
        ),
        Positioned(
          child: _isLoading ? LoadingView() : SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ BUBBLE MODE: Use custom header
    if (widget.isBubbleMode) {
      return Scaffold(
        body: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            // Minimize bubble instead of popping
            _minimizeBubble();
          },
          child: Column(
            children: [
              _buildBubbleHeader(), // ✅ Custom header for bubble
              Expanded(child: _buildChatContent()),
            ],
          ),
        ),
      );
    }

    // MINI CHAT MODE (existing)
    if (widget.isMiniChat) {
      return Scaffold(
        body: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _miniChatChannel.invokeMethod('minimize');
          },
          child: Container(
            child: Column(
              children: [
                _buildMiniChatHeader(),
                Expanded(child: _buildChatContent()),
              ],
            ),
          ),
        ),
      );
    }

    // NORMAL MODE (Original UI)
    return Scaffold(
      appBar: AppBar(
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
                  builder: (_) =>
                      UserProfilePage(userChat: UserChat.fromDocument(userDoc)),
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
                      style: TextStyle(
                        color: ColorConstants.primaryColor,
                        fontSize: 16,
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

  @override
  void dispose() {
    // ✅ FIX: ResourceManager handles subscriptions and listener cleanup

    // Cancel scheduled messages
    _scheduledMessages.forEach((key, timer) {
      try {
        timer.cancel();
      } catch (e) {
        print('⚠️ Error canceling timer: $e');
      }
    });
    _scheduledMessages.clear();
    _scheduledMessageContents.clear();

    // Cancel recording timer
    _recordingTimer?.cancel();

    // Set user offline
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

    // Dispose voice provider
    try {
      _voiceProvider?.dispose();
    } catch (e) {
      print('⚠️ Error disposing voice provider: $e');
    }

    // Dispose controllers
    try {
      _chatInputController.dispose();
      _listScrollController.dispose();
      _focusNode.dispose();
    } catch (e) {
      print('⚠️ Controller disposal error: $e');
    }

    // Remove lifecycle observer
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (e) {
      print('⚠️ Error removing observer: $e');
    }

    super.dispose();
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
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
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key, required this.group});
  final Group group;

  @override
  GroupChatPageState createState() => GroupChatPageState();
}

class GroupChatPageState extends State<GroupChatPage>
    with WidgetsBindingObserver, ResourceManagerMixin {
  late String _currentUserId;
  int _limit = 30;
  final int _limitIncrement = 20;

  bool _isLoading = false;
  bool _isLoadingMedia = false;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isShowSticker = false;
  bool _showFeaturesMenu = false;
  bool _isRecording = false;
  String _recordingDuration = '0:00';
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  MessageChat? _replyingTo;
  String? _replyingToSenderName;
  String? _replyingToMessageId;

  List<DocumentSnapshot> _pinnedMessages = [];

  bool _showMentionSuggestions = false;
  List<Map<String, dynamic>> _memberSuggestions = [];

  // Single source of truth for member names & avatar cache
  Map<String, String> _memberNames = {};
  final Map<String, String> _avatarUrlCache = {};

  List<SmartReply> _smartReplies = [];
  final Map<String, String> _scamResults = {};

  String? _pendingScrollToMessageId;

  late ChatProvider _chatProvider;
  late AuthProvider _authProvider;
  late MessageProvider _messageProvider;
  late ReactionProvider _reactionProvider;
  late ReminderProvider _reminderProvider;
  late AutoDeleteProvider _autoDeleteProvider;
  late ViewOnceProvider _viewOnceProvider;
  late SmartReplyProvider _smartReplyProvider;
  late TelemetryProvider _telemetryProvider;
  UserPresenceProvider? _presenceProvider;
  TranslationProvider? _translationProvider;
  VoiceMessageProvider? _voiceProvider;
  LocationProvider? _locationProvider;

  // MentionTextEditingController từ Giai đoạn 2
  late MentionTextEditingController _chatInputController;
  late ScrollController _listScrollController;
  late FocusNode _focusNode;

  final Map<String, Timer> _scheduledMessages = {};
  final Map<String, String> _scheduledMessageContents = {};

  String get _groupChatId => widget.group.id;

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _chatInputController = MentionTextEditingController();
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

  void _initializeProviders(BuildContext context) {
    if (resourceManager.isDisposed) return;
    _chatProvider = context.read<ChatProvider>();
    _authProvider = context.read<AuthProvider>();
    _messageProvider = context.read<MessageProvider>();
    _reactionProvider = context.read<ReactionProvider>();
    _reminderProvider = context.read<ReminderProvider>();
    _autoDeleteProvider = context.read<AutoDeleteProvider>();
    _viewOnceProvider = context.read<ViewOnceProvider>();
    _smartReplyProvider = context.read<SmartReplyProvider>();
    _presenceProvider = context.read<UserPresenceProvider>();
    _translationProvider = context.read<TranslationProvider>();
    _telemetryProvider = context.read<TelemetryProvider>();

    try {
      _locationProvider = context.read<LocationProvider>();
    } catch (_) {}

    try {
      _voiceProvider =
          VoiceMessageProvider(firebaseStorage: _chatProvider.firebaseStorage);
    } catch (_) {}

    _readLocal();
    _loadPinnedMessages();
    _loadMemberNames();
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

    _chatProvider.listenToFirebaseChanges(
        _groupChatId, _currentUserId, _groupChatId);

    _markMessagesAsRead();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!resourceManager.isDisposed && mounted) {
        _loadSmartReplies();
      }
    });
  }

  void _scrollListener() {
    if (resourceManager.isDisposed || !_listScrollController.hasClients) return;
    final pos = _listScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 && !pos.outOfRange) {
      final totalMessages = LocalDbService().getMessages(_groupChatId).length;
      if (_limit < totalMessages) {
        if (mounted) setState(() => _limit += _limitIncrement);
      }
    }
  }

  void _onFocusChange() {
    if (resourceManager.isDisposed || !mounted) return;
    if (_focusNode.hasFocus) {
      setState(() {
        _isShowSticker = false;
        _showFeaturesMenu = false;
      });
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _scheduledMessages.forEach((_, t) => t.cancel());
    _scheduledMessages.clear();
    _scheduledMessageContents.clear();
    try {
      _presenceProvider?.setTypingStatus(
          conversationId: _groupChatId,
          userId: _currentUserId,
          isTyping: false);
      _voiceProvider?.dispose();
    } catch (_) {}
    _chatInputController.dispose();
    _listScrollController.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // MEMBER NAMES
  // ---------------------------------------------------------------------------

  Future<void> _loadMemberNames() async {
    final names = <String, String>{};
    for (final uid in widget.group.memberIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(FirestoreConstants.pathUserCollection)
            .doc(uid)
            .get();
        if (doc.exists) {
          final nickname =
              doc.get(FirestoreConstants.nickname) as String? ?? 'User';
          final photoUrl =
              doc.get(FirestoreConstants.photoUrl) as String? ?? '';
          names[uid] = nickname;
          if (photoUrl.isNotEmpty) _avatarUrlCache[uid] = photoUrl;
        }
      } catch (_) {}
    }
    if (mounted && !resourceManager.isDisposed) {
      setState(() => _memberNames = names);
    }
  }

  String _getSenderName(String senderId) {
    if (senderId == _currentUserId) return 'You';
    return _memberNames[senderId] ?? 'User';
  }

  // ---------------------------------------------------------------------------
  // PINNED MESSAGES
  // ---------------------------------------------------------------------------

  void _loadPinnedMessages() {
    if (resourceManager.isDisposed) return;
    final sub = _messageProvider.getPinnedMessages(_groupChatId).listen(
      (snapshot) {
        if (!mounted || resourceManager.isDisposed) return;
        setState(() => _pinnedMessages = snapshot.docs);
      },
      onError: (_) {},
    );
    resourceManager.addSubscription(sub);
  }

  // ---------------------------------------------------------------------------
  // TEXT INPUT & MENTIONS
  // ---------------------------------------------------------------------------

  void _handleTextChange(String text) {
    if (resourceManager.isDisposed) return;
    _handleTyping(text);
    _telemetryProvider.recordTextChange(text);

    if (_telemetryProvider.shouldSuggestElderMode) {
      _showAdaptiveUISuggestion();
      _telemetryProvider.markAsHandled();
    }

    final cursorPos = _chatInputController.selection.baseOffset;
    if (cursorPos < 0) return;

    final textBefore = text.substring(0, cursorPos.clamp(0, text.length));
    final atIdx = textBefore.lastIndexOf('@');
    if (atIdx >= 0) {
      final query = textBefore.substring(atIdx + 1).toLowerCase();
      final suggestions = _memberNames.entries
          .where((e) =>
              e.key != _currentUserId && e.value.toLowerCase().contains(query))
          .map((e) => {'userId': e.key, 'name': e.value})
          .toList();
      if (mounted) {
        setState(() {
          _showMentionSuggestions = suggestions.isNotEmpty;
          _memberSuggestions = suggestions;
        });
      }
    } else {
      if (mounted) setState(() => _showMentionSuggestions = false);
    }

    if (text.isNotEmpty && _smartReplies.isNotEmpty && mounted) {
      setState(() => _smartReplies = []);
    }
  }

  void _insertMention(String userId, String name) {
    HapticFeedback.lightImpact();
    final text = _chatInputController.text;
    final cursorPos = _chatInputController.selection.baseOffset;
    final textBefore = text.substring(0, cursorPos.clamp(0, text.length));
    final atIdx = textBefore.lastIndexOf('@');
    if (atIdx < 0) return;

    final newText = text.replaceRange(atIdx, cursorPos, '@$name ');
    _chatInputController.text = newText;
    _chatInputController.selection =
        TextSelection.collapsed(offset: atIdx + name.length + 2);
    if (mounted) setState(() => _showMentionSuggestions = false);
  }

  void _handleTyping(String text) {
    if (_presenceProvider == null || resourceManager.isDisposed) return;
    _presenceProvider!.setTypingStatus(
      conversationId: _groupChatId,
      userId: _currentUserId,
      isTyping: text.isNotEmpty,
    );
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
            try {
              context.read<AppModeProvider>().setMode(AppMode.elder);
              Fluttertoast.showToast(
                  msg: 'Đã chuyển sang giao diện người lớn tuổi!');
            } catch (e) {
              debugPrint('Lỗi chuyển giao diện: $e');
            }
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // READ RECEIPTS
  // ---------------------------------------------------------------------------

  Future<void> _markMessagesAsRead() async {
    if (resourceManager.isDisposed) return;
    try {
      final unread = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(_groupChatId)
          .collection(_groupChatId)
          .where('isRead', isEqualTo: false)
          .get();

      if (unread.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference,
            {'isRead': true, 'readAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SEND MESSAGE (OFFLINE-FIRST)
  // ---------------------------------------------------------------------------

  Future<void> _onSendMessage(String content, int type) async {
    if (resourceManager.isDisposed) return;
    // Allow non-text types (media, sticker, etc.) even if content appears "empty"
    if (content.trim().isEmpty && type == TypeMessage.text) {
      Fluttertoast.showToast(msg: 'Nothing to send');
      return;
    }

    HapticFeedback.mediumImpact();

    String finalContent = content;
    if (_replyingTo != null) {
      final senderName = _getSenderName(_replyingTo!.idFrom);
      finalContent = '↪ [$senderName]: ${_replyingTo!.content}\n$finalContent';
    }

    _chatInputController.clear();
    if (mounted && !resourceManager.isDisposed) {
      setState(() {
        _replyingTo = null;
        _replyingToSenderName = null;
        _replyingToMessageId = null;
        _smartReplies = [];
        _showMentionSuggestions = false;
      });
    }

    try {
      await _chatProvider.sendMessage(
          finalContent, type, _groupChatId, _currentUserId, _groupChatId);

      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(_groupChatId)
          .set({
        FirestoreConstants.isGroup: true,
        FirestoreConstants.participants: widget.group.memberIds,
        FirestoreConstants.lastMessage: finalContent,
        FirestoreConstants.lastMessageTime:
            DateTime.now().millisecondsSinceEpoch.toString(),
        FirestoreConstants.lastMessageType: type,
      }, SetOptions(merge: true));

      await _autoDeleteProvider.scheduleMessageDeletion(
        groupChatId: _groupChatId,
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        conversationId: _groupChatId,
      );
    } catch (_) {
      Fluttertoast.showToast(msg: 'Gửi thất bại');
    }

    if (_listScrollController.hasClients && !resourceManager.isDisposed) {
      _listScrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _loadSmartReplies() {
    if (resourceManager.isDisposed) return;
    final messages = LocalDbService().getMessages(_groupChatId);
    if (messages.isEmpty) return;

    final lastMessageData = messages.first;
    if (lastMessageData['idFrom'] != _currentUserId &&
        lastMessageData['type'] == TypeMessage.text) {
      final plaintext = lastMessageData['content'];
      final replies = _smartReplyProvider.getRuleBasedReplies(plaintext);
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _smartReplies = replies);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // IMAGE / VIDEO / MEDIA
  // ---------------------------------------------------------------------------

  Future<void> _onPickImage() async {
    HapticFeedback.lightImpact();
    try {
      final XFile? pickedFile =
          await _imagePicker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        await _processAndSendMedia(File(pickedFile.path), isVideo: false);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Không thể chọn ảnh');
    }
  }

  Future<void> _onPickVideo() async {
    HapticFeedback.lightImpact();
    try {
      final XFile? pickedFile =
          await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (pickedFile != null) {
        await _processAndSendMedia(File(pickedFile.path), isVideo: true);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Không thể chọn video');
    }
  }

  Future<void> _processAndSendMedia(File file, {required bool isVideo}) async {
    if (resourceManager.isDisposed) return;

    final mediaLabel = isVideo ? 'Video' : 'Hình Ảnh';
    final mediaIcon = isVideo ? Icons.videocam_rounded : Icons.image_rounded;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => SafeSendDialog(
        title: 'Gửi $mediaLabel',
        content:
            'Bạn có chắc chắn muốn gửi ${isVideo ? 'video' : 'bức ảnh'} này vào nhóm?',
        icon: mediaIcon,
      ),
    );

    if (confirm != true || resourceManager.isDisposed) return;

    if (mounted) setState(() => _isLoadingMedia = true);

    try {
      final success = await _chatProvider.sendMediaMessage(
        originalFile: file,
        isVideo: isVideo,
        groupChatId: _groupChatId,
        currentUserId: _currentUserId,
        peerId: _groupChatId,
        onLoadingStatusChanged: (isLoading) {
          if (mounted) setState(() => _isLoadingMedia = isLoading);
        },
      );

      if (!mounted || resourceManager.isDisposed) return;

      if (success != false) {
        if (_listScrollController.hasClients) {
          _listScrollController.animateTo(0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
        Fluttertoast.showToast(
          msg: isVideo ? '🎬 Video đã gửi' : '📷 Ảnh đã gửi',
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
          msg: 'Lỗi khi gửi $mediaLabel', backgroundColor: Colors.red);
    } finally {
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _isLoadingMedia = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // DOCUMENT PICKER
  // ---------------------------------------------------------------------------

  Future<void> _onPickDocument() async {
    HapticFeedback.lightImpact();
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String fileName = result.files.single.name;
        int fileSize = result.files.single.size;

        if (mounted) setState(() => _isLoadingMedia = true);

        String? fileUrl =
            await _chatProvider.uploadFileAndGetUrl(file, _groupChatId);

        if (fileUrl != null && mounted) {
          String content =
              jsonEncode({'url': fileUrl, 'name': fileName, 'size': fileSize});
          await _onSendMessage(content, TypeMessage.document);
        }
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Lỗi chọn file');
    } finally {
      if (mounted) setState(() => _isLoadingMedia = false);
    }
  }

  // ---------------------------------------------------------------------------
  // VOICE RECORDING
  // ---------------------------------------------------------------------------

  Future<void> _startRecording() async {
    if (_voiceProvider == null || resourceManager.isDisposed) {
      Fluttertoast.showToast(msg: 'Voice recording not available');
      return;
    }
    final init = await _voiceProvider!.initRecorder();
    if (!init) {
      Fluttertoast.showToast(msg: 'Microphone permission required');
      return;
    }
    final started = await _voiceProvider!.startRecording();
    if (started && mounted && !resourceManager.isDisposed) {
      HapticFeedback.lightImpact();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
        _recordingDuration = '0:00';
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || resourceManager.isDisposed) {
          t.cancel();
          return;
        }
        setState(() {
          _recordingSeconds++;
          final m = _recordingSeconds ~/ 60;
          final s = _recordingSeconds % 60;
          _recordingDuration = '$m:${s.toString().padLeft(2, '0')}';
        });
      });
    }
  }

  Future<void> _stopRecording() async {
    if (_voiceProvider == null || resourceManager.isDisposed) return;
    _recordingTimer?.cancel();
    final path = await _voiceProvider!.stopRecording();
    if (path == null) {
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
    final url = await _voiceProvider!.uploadVoiceMessage(path, fileName);
    if (mounted && !resourceManager.isDisposed) {
      setState(() => _isLoading = false);
    }
    if (url != null && !resourceManager.isDisposed) {
      await _onSendMessage(url, 3);
      Fluttertoast.showToast(msg: '🎤 Voice message sent');
    }
  }

  Future<void> _cancelRecording() async {
    HapticFeedback.lightImpact();
    _recordingTimer?.cancel();
    await _voiceProvider?.cancelRecording();
    if (mounted && !resourceManager.isDisposed) {
      setState(() => _isRecording = false);
    }
  }

  // ---------------------------------------------------------------------------
  // LOCATION
  // ---------------------------------------------------------------------------

  Future<void> _shareLocation() async {
    if (_locationProvider == null || resourceManager.isDisposed) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final hasPermission =
          await _locationProvider!.requestLocationPermission();
      if (!hasPermission) {
        if (mounted) setState(() => _isLoading = false);
        Fluttertoast.showToast(msg: '📍 Location permission required');
        return;
      }
      final locationData =
          await _locationProvider!.getCurrentLocationWithDetails();
      if (mounted) setState(() => _isLoading = false);
      if (locationData != null && !resourceManager.isDisposed) {
        await _onSendMessage(
            _locationProvider!.formatLocationMessage(locationData),
            TypeMessage.text);
        Fluttertoast.showToast(msg: '📍 Location shared');
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openLocationInMaps(String mapsUrl) async {
    try {
      final uri = Uri.parse(mapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // AI CONTEXT ANALYSIS
  // ---------------------------------------------------------------------------

  void _showAIContextAnalysis() {
    final messages = LocalDbService().getMessages(_groupChatId);
    if (messages.isEmpty) {
      Fluttertoast.showToast(msg: 'Chưa có đủ tin nhắn để phân tích');
      return;
    }

    final List<String> recentMessages = [];
    for (final data in messages.take(20)) {
      final sender = data['idFrom'] == _currentUserId
          ? 'Tôi'
          : (_memberNames[data['idFrom']] ?? 'Thành viên');
      recentMessages.add('$sender: ${data['content']}');
    }

    if (!mounted || resourceManager.isDisposed) return;

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
              recentMessages.reversed.toList(), 'work', 'extract_tasks'),
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
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MESSAGE OPTIONS
  // ---------------------------------------------------------------------------

  void _showMessageOptions(MessageChat message, String messageId) {
    if (resourceManager.isDisposed) return;
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => EnhancedMessageOptionsDialog(
        isOwnMessage: message.idFrom == _currentUserId,
        isPinned: message.isPinned,
        isDeleted: message.isDeleted,
        messageContent: message.content,
        onEdit: () => _editMessage(messageId, message.content),
        onDelete: () => _deleteMessage(messageId),
        onPin: () => _togglePin(messageId, message.isPinned),
        onCopy: () {
          Clipboard.setData(ClipboardData(text: message.content));
          Fluttertoast.showToast(msg: 'Copied');
        },
        onReply: () => _setReply(message, messageId),
        onReminder: () => _setReminder(message, messageId),
        onTranslate: () => _translateMessage(message.content),
      ),
    );
  }

  Future<void> _editMessage(String messageId, String current) async {
    showDialog(
      context: context,
      builder: (_) => EditMessageDialog(
        originalContent: current,
        onSave: (newContent) async {
          final ok = await _messageProvider.editMessage(
              _groupChatId, messageId, newContent);
          if (ok) Fluttertoast.showToast(msg: 'Message edited');
        },
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Delete this message?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      final ok = await _messageProvider.deleteMessage(_groupChatId, messageId);
      if (ok) Fluttertoast.showToast(msg: 'Đã xóa tin nhắn');
    }
  }

  Future<void> _togglePin(String messageId, bool current) async {
    final ok = await _messageProvider.togglePinMessage(
        _groupChatId, messageId, current);
    if (ok) Fluttertoast.showToast(msg: current ? 'Unpinned' : 'Pinned');
  }

  /// [messageId] dùng để scroll đến tin gốc khi bấm vào reply preview (Giai đoạn 2)
  void _setReply(MessageChat message, [String? messageId]) {
    HapticFeedback.selectionClick();
    if (resourceManager.isDisposed || !mounted) return;
    setState(() {
      _replyingTo = message;
      _replyingToMessageId = messageId;
      _replyingToSenderName = _getSenderName(message.idFrom);
    });
    _focusNode.requestFocus();
  }

  Future<void> _setReminder(MessageChat message, String messageId) async {
    final reminderTime = await _pickReminderTime();
    if (reminderTime != null && !resourceManager.isDisposed) {
      final ok = await _reminderProvider.scheduleReminder(
        userId: _currentUserId,
        messageId: messageId,
        conversationId: _groupChatId,
        reminderTime: reminderTime,
        message: message.content,
      );
      if (ok) Fluttertoast.showToast(msg: '⏰ Reminder set');
    }
  }

  Future<DateTime?> _pickReminderTime() async {
    DateTime selected = DateTime.now().add(const Duration(hours: 1));
    return showDialog<DateTime>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Set Reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Date'),
                subtitle: Text(DateFormat('MMM dd, yyyy').format(selected)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: selected,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) {
                    ss(() => selected = DateTime(d.year, d.month, d.day,
                        selected.hour, selected.minute));
                  }
                },
              ),
              ListTile(
                title: const Text('Time'),
                subtitle: Text(DateFormat('HH:mm').format(selected)),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(selected));
                  if (t != null) {
                    ss(() => selected = DateTime(selected.year, selected.month,
                        selected.day, t.hour, t.minute));
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Set')),
          ],
        ),
      ),
    );
  }

  Future<void> _translateMessage(String content) async {
    showDialog(
      context: context,
      builder: (_) => TranslationDialog(originalMessage: content),
    );
  }

  // ---------------------------------------------------------------------------
  // SCHEDULE MESSAGE
  // ---------------------------------------------------------------------------

  Future<void> _scheduleMessage() async {
    if (resourceManager.isDisposed) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ScheduleMessageDialog(),
    );
    if (result == null || resourceManager.isDisposed || !mounted) return;
    final text = result['message'] as String;
    final time = result['time'] as DateTime;
    final delay = time.difference(DateTime.now());
    if (delay.isNegative) {
      Fluttertoast.showToast(msg: 'Invalid time');
      return;
    }
    final key = time.millisecondsSinceEpoch.toString();
    _scheduledMessageContents[key] = text;
    _scheduledMessages[key] = Timer(delay, () {
      if (!resourceManager.isDisposed && mounted) {
        final c = _scheduledMessageContents[key];
        if (c != null) _onSendMessage(c, TypeMessage.text);
        _scheduledMessages.remove(key);
        _scheduledMessageContents.remove(key);
      }
    });
    Fluttertoast.showToast(
        msg: '📅 Scheduled for ${DateFormat('HH:mm').format(time)}');
  }

  // ---------------------------------------------------------------------------
  // VIEW ONCE / AUTO-DELETE / REACTIONS / STICKER
  // ---------------------------------------------------------------------------

  void _sendViewOnce() {
    showDialog(
      context: context,
      builder: (_) => SendViewOnceDialog(
        onSend: (content, type) async {
          await _viewOnceProvider.sendViewOnceMessage(
            groupChatId: _groupChatId,
            currentUserId: _currentUserId,
            peerId: _groupChatId,
            content: content,
            type: type,
          );
        },
      ),
    );
  }

  void _showAutoDeleteSettings() {
    showDialog(
      context: context,
      builder: (_) => AutoDeleteSettingsDialog(
        conversationId: _groupChatId,
        provider: _autoDeleteProvider,
      ),
    );
  }

  void _showReactionPicker(String messageId) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ReactionPicker(
          onEmojiSelected: (emoji) {
            _reactionProvider.toggleReaction(
                _groupChatId, messageId, _currentUserId, emoji);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _getSticker() {
    HapticFeedback.selectionClick();
    _focusNode.unfocus();
    setState(() {
      _isShowSticker = !_isShowSticker;
      _showFeaturesMenu = false;
    });
  }

  void _toggleFeaturesMenu() {
    HapticFeedback.selectionClick();
    if (resourceManager.isDisposed || !mounted) return;
    setState(() {
      _showFeaturesMenu = !_showFeaturesMenu;
      _isShowSticker = false;
    });
  }

  void _onBackPress() {
    _presenceProvider?.setTypingStatus(
        conversationId: _groupChatId, userId: _currentUserId, isTyping: false);
    Navigator.pop(context);
  }

  // ---------------------------------------------------------------------------
  // SEARCH & SCROLL TO MESSAGE
  // ---------------------------------------------------------------------------

  void _openSearch() async {
    final matchedId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SearchMessagesPage(
          groupChatId: _groupChatId,
          peerName: widget.group.groupName,
          peerId: _groupChatId,
        ),
      ),
    );

    if (matchedId != null && mounted) {
      setState(() => _pendingScrollToMessageId = matchedId);
      Future.delayed(
          const Duration(milliseconds: 400), () => _scrollToMessage(matchedId));
    }
  }

  void _scrollToMessage(String id) {
    if (!_listScrollController.hasClients) return;
    final allMessages = LocalDbService().getMessages(_groupChatId);
    final index = allMessages.indexWhere((map) => map['messageId'] == id);

    if (index == -1) {
      if (mounted && _limit <= allMessages.length) {
        setState(() => _limit += _limitIncrement);
        Future.delayed(
            const Duration(milliseconds: 500), () => _scrollToMessage(id));
      }
      return;
    }

    final offset = (index * 72.0)
        .clamp(0.0, _listScrollController.position.maxScrollExtent);
    _listScrollController.animateTo(offset,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    setState(() => _pendingScrollToMessageId = null);
  }

  // ---------------------------------------------------------------------------
  // CLEAR HISTORY / LEAVE GROUP
  // ---------------------------------------------------------------------------

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Delete all messages in this group?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Clear', style: TextStyle(color: Colors.orange))),
        ],
      ),
    );
    if (confirm != true) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final msgs = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(_groupChatId)
          .collection(_groupChatId)
          .get();
      WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;
      for (final doc in msgs.docs) {
        batch.delete(doc.reference);
        if (++count >= 500) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
      _scamResults.clear();
      Fluttertoast.showToast(msg: 'History cleared');
    } catch (_) {
      Fluttertoast.showToast(msg: 'Failed to clear history');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final newMembers =
          widget.group.memberIds.where((id) => id != _currentUserId).toList();
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_groupChatId)
          .update({FirestoreConstants.memberIds: newMembers});
      await _onSendMessage(
          '${_memberNames[_currentUserId] ?? 'User'} left the group',
          TypeMessage.text);
      if (mounted) Navigator.of(context).pop();
      Fluttertoast.showToast(msg: 'You left the group');
    } catch (_) {
      Fluttertoast.showToast(msg: 'Failed to leave group');
    }
  }

  // ---------------------------------------------------------------------------
  // GROUP INFO
  // ---------------------------------------------------------------------------

  void _openGroupInfo() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupInfoPage(
          group: widget.group,
          currentUserId: _currentUserId,
          memberNames: _memberNames,
        ),
      ),
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'ai_assistant':
        _showAIContextAnalysis();
      case 'info':
        _openGroupInfo();
      case 'media':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupMediaPage(
              groupId: _groupChatId,
              groupName: widget.group.groupName,
            ),
          ),
        );
      case 'search':
        _openSearch();
      case 'autodelete':
        _showAutoDeleteSettings();
      case 'clear':
        _clearHistory();
      case 'leave':
        _leaveGroup();
      default:
        Fluttertoast.showToast(msg: 'Coming soon');
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _onBackPress();
          },
          child: Column(
            children: [
              ActiveGroupCallBanner(
                groupId: _groupChatId,
                currentUserId: _currentUserId,
                memberIds: widget.group.memberIds,
                groupName: widget.group.groupName,
              ),
              if (_showMentionSuggestions) _buildMentionSuggestions(),
              Expanded(child: _buildChatContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatContent() {
    return Stack(
      children: [
        Column(
          children: [
            const OfflineIndicator(),
            if (_pinnedMessages.isNotEmpty) _buildPinnedMessages(),
            _buildListMessage(),
            _buildTypingIndicator(),
            if (_isShowSticker) _buildStickers(),
            if (_showFeaturesMenu) _buildFeaturesMenu(),
            _buildInput(),
          ],
        ),
        Positioned(
          child: _isLoading ? const LoadingView() : const SizedBox.shrink(),
        ),
        if (_isLoadingMedia)
          Positioned.fill(child: _buildMediaLoadingOverlay()),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MEDIA LOADING OVERLAY
  // ---------------------------------------------------------------------------

  Widget _buildMediaLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.45),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Đang nén và tối ưu tệp...',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // APP BAR
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white.withOpacity(0.95),
      elevation: 0,
      scrolledUnderElevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF007AFF)),
        onPressed: _onBackPress,
      ),
      title: InkWell(
        onTap: _openGroupInfo,
        child: Row(
          children: [
            Hero(
              tag: 'group_avatar_${widget.group.id}',
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFFF2F2F7),
                  backgroundImage: widget.group.groupPhotoUrl.isNotEmpty
                      ? NetworkImage(widget.group.groupPhotoUrl)
                      : null,
                  child: widget.group.groupPhotoUrl.isEmpty
                      ? const Icon(Icons.group_rounded,
                          size: 20, color: Color(0xFF8E8E93))
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.group.groupName,
                    style: const TextStyle(
                        color: Color(0xFF111418),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${widget.group.memberIds.length} members',
                    style:
                        const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        GroupVideoCallButton(
          groupId: _groupChatId,
          groupName: widget.group.groupName,
          memberIds: widget.group.memberIds,
        ),
        IconButton(
          icon: const Icon(Icons.search_rounded, color: Color(0xFF007AFF)),
          onPressed: _openSearch,
          tooltip: 'Search',
        ),
        PopupMenuButton<String>(
          onSelected: _onMenuSelected,
          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF007AFF)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'ai_assistant',
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.purple, size: 20),
                  SizedBox(width: 8),
                  Text('AI Assistant'),
                ],
              ),
            ),
            const PopupMenuItem(value: 'info', child: Text('Group Info')),
            const PopupMenuItem(value: 'media', child: Text('Media & Files')),
            const PopupMenuItem(
                value: 'search', child: Text('Search Messages')),
            const PopupMenuItem(
                value: 'mute', child: Text('Mute Notifications')),
            const PopupMenuItem(
                value: 'autodelete', child: Text('Auto-Delete')),
            const PopupMenuItem(value: 'clear', child: Text('Clear History')),
            const PopupMenuItem(
                value: 'leave',
                child: Text('Leave Group',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600))),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PINNED MESSAGES
  // ---------------------------------------------------------------------------

  Widget _buildPinnedMessages() {
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
        itemBuilder: (_, index) {
          final message = MessageChat.fromDocument(_pinnedMessages[index]);
          return Container(
            width: 200,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(16)),
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
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MEDIA GROUP ALGORITHM
  // ---------------------------------------------------------------------------

  List<dynamic> _processMessages(List<Map<dynamic, dynamic>> rawMessages) {
    List<dynamic> grouped = [];
    List<Map<dynamic, dynamic>> currentMediaGroup = [];

    for (int i = 0; i < rawMessages.length; i++) {
      var msg = rawMessages[i];
      int type = msg['type'] ?? 0;
      bool isMedia = (type == TypeMessage.image || type == TypeMessage.video);

      if (isMedia) {
        if (currentMediaGroup.isEmpty) {
          currentMediaGroup.add(msg);
        } else {
          var prevMsg = currentMediaGroup.last;
          int timeDiff = (int.parse(prevMsg['timestamp'] ?? '0') -
                  int.parse(msg['timestamp'] ?? '0'))
              .abs();
          // Group media sent by the same person within 10 seconds
          if (msg['idFrom'] == prevMsg['idFrom'] && timeDiff <= 10000) {
            currentMediaGroup.add(msg);
          } else {
            grouped.add(currentMediaGroup.length == 1
                ? currentMediaGroup.first
                : {
                    'isMediaGroup': true,
                    'messages': List.from(currentMediaGroup)
                  });
            currentMediaGroup = [msg];
          }
        }
      } else {
        if (currentMediaGroup.isNotEmpty) {
          grouped.add(currentMediaGroup.length == 1
              ? currentMediaGroup.first
              : {
                  'isMediaGroup': true,
                  'messages': List.from(currentMediaGroup)
                });
          currentMediaGroup.clear();
        }
        grouped.add(msg);
      }
    }

    if (currentMediaGroup.isNotEmpty) {
      grouped.add(currentMediaGroup.length == 1
          ? currentMediaGroup.first
          : {'isMediaGroup': true, 'messages': List.from(currentMediaGroup)});
    }

    return grouped;
  }

  // ---------------------------------------------------------------------------
  // CORE OFFLINE-FIRST: MESSAGE LIST FROM LOCAL DB
  // ---------------------------------------------------------------------------

  Widget _buildListMessage() {
    return Flexible(
      child: _groupChatId.isNotEmpty
          ? ValueListenableBuilder(
              valueListenable: LocalDbService().messagesBox.listenable(),
              builder: (context, Box box, _) {
                final allMessages = LocalDbService().getMessages(_groupChatId);
                final displayMessages = allMessages.take(_limit).toList();
                final groupedData = _processMessages(displayMessages);

                if (groupedData.isEmpty) {
                  return const Center(
                      child: Text('No messages yet. Say hello! 👋',
                          style: TextStyle(color: Color(0xFF8E8E93))));
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  itemCount: groupedData.length,
                  reverse: true,
                  controller: _listScrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                    decelerationRate: ScrollDecelerationRate.fast,
                  ),
                  itemBuilder: (_, index) {
                    final item = groupedData[index];
                    if (item is Map && item['isMediaGroup'] == true) {
                      return _buildMediaGroup(
                          List<Map<dynamic, dynamic>>.from(item['messages']));
                    }
                    return _buildItemMessageFromLocal(
                        index, item as Map<dynamic, dynamic>, displayMessages);
                  },
                );
              },
            )
          : const Center(
              child:
                  CircularProgressIndicator(color: ColorConstants.themeColor)),
    );
  }

  // ---------------------------------------------------------------------------
  // MEDIA GROUP GRID WIDGET
  // ---------------------------------------------------------------------------

  Widget _buildMediaGroup(List<Map<dynamic, dynamic>> messages) {
    if (messages.isEmpty) return const SizedBox.shrink();

    final firstMsgData = messages.first;
    final isMe = firstMsgData['idFrom'] == _currentUserId;
    final messageId = firstMsgData['messageId'] as String? ?? '';

    final representativeMsg = MessageChat(
      idFrom: firstMsgData['idFrom'] ?? '',
      idTo: firstMsgData['idTo'] ?? '',
      timestamp: firstMsgData['timestamp'] ?? '',
      content: firstMsgData['content'] ?? '',
      type: firstMsgData['type'] ?? 0,
      isRead: firstMsgData['status'] == 'sent',
    );

    return SwipeToReplyWrapper(
      isMe: isMe,
      onSwipe: () => _setReply(representativeMsg, messageId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe) _buildSenderInfo(firstMsgData['idFrom']),
            Row(
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) _buildAvatar(firstMsgData['idFrom']),
                Container(
                  width: MediaQuery.of(context).size.width * 0.7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.transparent,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      var m = messages[i];
                      bool isVideo = m['type'] == TypeMessage.video;
                      String url = m['content'] ?? '';
                      final videoUrl = isVideo ? url.split('|').first : '';
                      final thumbUrl = isVideo
                          ? (url.split('|').length > 1 ? url.split('|')[1] : '')
                          : url;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (isVideo) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        VideoPlayerPage(videoUrl: videoUrl)));
                          } else {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        FullPhotoPage(url: thumbUrl)));
                          }
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              thumbUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: Colors.black12),
                            ),
                            if (isVideo)
                              const Center(
                                child: Icon(Icons.play_circle_fill_rounded,
                                    color: Colors.white, size: 32),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            _buildTimestamp(firstMsgData['timestamp'] ?? '', isMe),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ITEM MESSAGE BUILDER
  // ---------------------------------------------------------------------------

  Widget _buildItemMessageFromLocal(int index, Map<dynamic, dynamic> localData,
      List<Map<dynamic, dynamic>> fullList) {
    final isHighlighted = _pendingScrollToMessageId == localData['messageId'];
    final isPending = localData['status'] == 'pending';

    final messageChat = MessageChat(
      idFrom: localData['idFrom'] ?? '',
      idTo: localData['idTo'] ?? '',
      timestamp: localData['timestamp'] ?? '',
      content: localData['content'] ?? '',
      type: localData['type'] ?? 0,
      isRead: localData['status'] == 'sent',
    );

    bool isLastInGroup = true;
    if (index > 0) {
      final prevMsg = fullList[index - 1];
      isLastInGroup = prevMsg['idFrom'] != messageChat.idFrom;
    }

    final isMe = messageChat.idFrom == _currentUserId;
    final isViewOnce = localData['isViewOnce'] ?? false;
    final bool isScamWarning = localData['scamWarning'] ?? false;
    final String scamReason = localData['scamReason'] ?? '';
    final bool hasReminder = localData['hasReminder'] ?? false;
    final String messageId = localData['messageId'] ?? '';

    // --- Giai đoạn 3: Game Caro (Type 7) ---
    if (messageChat.type == 7) {
      return SwipeToReplyWrapper(
          isMe: isMe,
          onSwipe: () => _setReply(messageChat, messageId),
          child: Container(
              margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isMe)
                      isLastInGroup
                          ? _buildAvatar(messageChat.idFrom)
                          : const SizedBox(width: 40),
                    TicTacToeMessageWidget(
                      content: messageChat.content,
                      messageId: messageId,
                      groupId: _groupChatId,
                      currentUserId: _currentUserId,
                    )
                  ])));
    }

    // --- Giai đoạn 3: Thổi Bóng (Type 8) ---
    if (messageChat.type == 8) {
      return SwipeToReplyWrapper(
          isMe: isMe,
          onSwipe: () => _setReply(messageChat, messageId),
          child: Container(
              margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isMe)
                      isLastInGroup
                          ? _buildAvatar(messageChat.idFrom)
                          : const SizedBox(width: 40),
                    BlowMessageWidget(secretText: messageChat.content)
                  ])));
    }

    // --- Giai đoạn 3: Lắc Máy (Type 9) ---
    if (messageChat.type == 9) {
      return SwipeToReplyWrapper(
          isMe: isMe,
          onSwipe: () => _setReply(messageChat, messageId),
          child: Container(
              margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isMe)
                      isLastInGroup
                          ? _buildAvatar(messageChat.idFrom)
                          : const SizedBox(width: 40),
                    ShakeMessageWidget(secretText: messageChat.content)
                  ])));
    }

    // --- Poll ---
    if (messageChat.type == TypeMessage.poll) {
      return SwipeToReplyWrapper(
        isMe: isMe,
        onSwipe: () => _setReply(messageChat, messageId),
        child: Container(
          margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                isLastInGroup
                    ? _buildAvatar(messageChat.idFrom)
                    : const SizedBox(width: 40),
              PollMessageWidget(
                content: messageChat.content,
                messageId: messageId,
                currentUserId: _currentUserId,
                onVote: (mId, optId) {
                  _chatProvider.votePoll(
                      _groupChatId, mId, optId, _currentUserId);
                },
              ),
            ],
          ),
        ),
      );
    }

    // --- Document ---
    if (messageChat.type == TypeMessage.document) {
      Map<String, dynamic> fileData = {};
      try {
        fileData = jsonDecode(messageChat.content);
      } catch (_) {}
      return SwipeToReplyWrapper(
        isMe: isMe,
        onSwipe: () => _setReply(messageChat, messageId),
        child: Container(
          margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                isLastInGroup
                    ? _buildAvatar(messageChat.idFrom)
                    : const SizedBox(width: 40),
              GestureDetector(
                onTap: () {
                  final url = fileData['url'] as String? ?? '';
                  if (url.isNotEmpty) launchUrl(Uri.parse(url));
                },
                onLongPress: () => _showMessageOptions(messageChat, messageId),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.blue.shade100 : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file,
                          color: Color(0xFF007AFF), size: 30),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileData['name'] as String? ?? 'File',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${((fileData['size'] as num? ?? 0) / 1024).toStringAsFixed(1)} KB',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget messageBubble;

    // --- View Once ---
    if (isViewOnce) {
      messageBubble =
          _buildViewOnceMessageFromLocal(messageChat, localData, messageId);
    }
    // --- Voice ---
    else if (messageChat.type == 3 && _voiceProvider != null) {
      messageBubble = _buildVoiceMessage(messageChat, isMe);
    }
    // --- Image ---
    else if (messageChat.type == TypeMessage.image) {
      messageBubble = _buildImageMessageFromLocal(
          messageId, messageChat, isMe, isLastInGroup, isPending);
    }
    // --- Video ---
    else if (messageChat.type == TypeMessage.video) {
      messageBubble = _buildVideoMessageFromLocal(
          messageId, messageChat, isMe, isLastInGroup, isPending);
    }
    // --- Sticker ---
    else if (messageChat.type == TypeMessage.sticker) {
      messageBubble = _buildStickerMessage(messageChat, isMe, messageId);
    }
    // --- Text ---
    else {
      messageBubble = _buildTextMessageFromLocal(
        messageId: messageId,
        msg: messageChat,
        isMe: isMe,
        isLastInGroup: isLastInGroup,
        isPending: isPending,
        isHighlighted: isHighlighted,
        isScamWarning: isScamWarning,
        scamReason: scamReason,
        hasReminder: hasReminder,
      );
    }

    return SwipeToReplyWrapper(
      isMe: isMe,
      onSwipe: () => _setReply(messageChat, messageId),
      child: messageBubble,
    );
  }

  // ---------------------------------------------------------------------------
  // SENDER INFO & AVATAR
  // ---------------------------------------------------------------------------

  Widget _buildSenderInfo(String senderId) {
    if (senderId == _currentUserId) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 44, bottom: 4),
      child: Text(
        _getSenderName(senderId),
        style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 12,
            fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildAvatar(String senderId) {
    if (senderId == _currentUserId) return const SizedBox.shrink();
    final photoUrl = _avatarUrlCache[senderId] ?? '';
    return Container(
      margin: const EdgeInsets.only(right: 8),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE5E5EA),
        image: photoUrl.isNotEmpty
            ? DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: photoUrl.isEmpty
          ? const Icon(Icons.person_rounded, size: 20, color: Colors.white)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // TEXT MESSAGE
  // ---------------------------------------------------------------------------

  Widget _buildTextMessageFromLocal({
    required String messageId,
    required MessageChat msg,
    required bool isMe,
    required bool isLastInGroup,
    required bool isPending,
    bool isHighlighted = false,
    bool isScamWarning = false,
    String scamReason = '',
    bool hasReminder = false,
  }) {
    final double tailRadius = isLastInGroup ? 4.0 : 20.0;
    final location = _locationProvider?.parseLocationFromMessage(msg.content);

    Widget bubble = Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && isLastInGroup) _buildSenderInfo(msg.idFrom),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                isLastInGroup
                    ? _buildAvatar(msg.idFrom)
                    : const SizedBox(width: 40),
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    HapticFeedback.heavyImpact();
                    _showMessageOptions(msg, messageId);
                  },
                  onDoubleTap: () {
                    HapticFeedback.mediumImpact();
                    _showReactionPicker(messageId);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.72),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? const LinearGradient(
                              colors: [Color(0xFF007AFF), Color(0xFF0056D6)])
                          : null,
                      color: isMe ? null : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMe ? 20 : tailRadius),
                        bottomRight: Radius.circular(isMe ? tailRadius : 20),
                      ),
                      boxShadow: isMe
                          ? [
                              BoxShadow(
                                  color:
                                      const Color(0xFF007AFF).withOpacity(0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4))
                            ]
                          : [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4))
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Scam warning banner
                        if (!isMe && isScamWarning)
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
                        // Reminder detection banner
                        if (!isMe && hasReminder)
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
                                  onPressed: () => _setReminder(msg, messageId),
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(40, 24)),
                                  child: const Text('XEM',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        // Message body
                        if (msg.isDeleted)
                          Text(
                            'This message was deleted',
                            style: TextStyle(
                                color: isMe
                                    ? Colors.white70
                                    : const Color(0xFF8E8E93),
                                fontStyle: FontStyle.italic,
                                fontSize: 15),
                          )
                        else if (location != null)
                          _buildLocationContent(location, isMe)
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.content,
                                style: TextStyle(
                                    color: isMe
                                        ? Colors.white
                                        : const Color(0xFF111418),
                                    fontSize: 16,
                                    height: 1.3),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (isMe)
                                      Icon(
                                        isPending
                                            ? Icons.access_time_rounded
                                            : msg.isRead
                                                ? Icons.done_all_rounded
                                                : Icons.check_rounded,
                                        size: 14,
                                        color: isPending
                                            ? Colors.white54
                                            : msg.isRead
                                                ? Colors.white
                                                : Colors.white70,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // AI scam scan button for incoming text messages
          if (!isMe && msg.type == TypeMessage.text) ...[
            if (_scamResults[messageId] != null &&
                _scamResults[messageId] != 'SAFE')
              ScamWarningWidget(status: _scamResults[messageId]!),
            if (_scamResults[messageId] == null && !isScamWarning)
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 4, bottom: 4),
                child: InkWell(
                  onTap: () async {
                    Fluttertoast.showToast(msg: 'AI Đang quét an toàn...');
                    final status =
                        await AIBackendService().checkScam(msg.content);
                    if (mounted) {
                      setState(() => _scamResults[messageId] = status);
                    }
                    if (status == 'SAFE') {
                      Fluttertoast.showToast(msg: 'Tin nhắn an toàn!');
                    }
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text('Quét an toàn (AI)',
                          style: TextStyle(fontSize: 12, color: Colors.green)),
                    ],
                  ),
                ),
              ),
          ],
          _buildReactions(messageId, isMe),
          _buildTimestamp(msg.timestamp, isMe),
        ],
      ),
    );

    if (!isHighlighted) return bubble;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        color: const Color(0xFF007AFF).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: bubble,
    );
  }

  // ---------------------------------------------------------------------------
  // LOCATION CONTENT
  // ---------------------------------------------------------------------------

  Widget _buildLocationContent(LocationData location, bool isMe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on,
                color: isMe ? Colors.white : Colors.red, size: 20),
            const SizedBox(width: 4),
            Text('Location',
                style: TextStyle(
                    color: isMe ? Colors.white : const Color(0xFF111418),
                    fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(location.address,
            style: TextStyle(
                color: isMe ? Colors.white : const Color(0xFF111418),
                fontSize: 13)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _openLocationInMaps(location.mapsUrl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white24
                  : const Color(0xFF007AFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map,
                    size: 14,
                    color: isMe ? Colors.white : const Color(0xFF007AFF)),
                const SizedBox(width: 4),
                Text('View on Google Maps',
                    style: TextStyle(
                        fontSize: 12,
                        color: isMe ? Colors.white : const Color(0xFF007AFF),
                        decoration: TextDecoration.underline)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // IMAGE / VIDEO / VOICE / STICKER / VIEW-ONCE MESSAGE WIDGETS
  // ---------------------------------------------------------------------------

  Widget _buildImageMessageFromLocal(String messageId, MessageChat msg,
      bool isMe, bool isLastInGroup, bool isPending) {
    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && isLastInGroup) _buildSenderInfo(msg.idFrom),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                isLastInGroup
                    ? _buildAvatar(msg.idFrom)
                    : const SizedBox(width: 40),
              GestureDetector(
                onTap: () {
                  if (!isPending) {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => FullPhotoPage(url: msg.content)));
                  }
                },
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  _showMessageOptions(msg, messageId);
                },
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.65,
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black12,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!isPending)
                          Image.network(
                            msg.content,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                  color: const Color(0xFFF2F2F7),
                                  child: const Center(
                                      child: CircularProgressIndicator()));
                            },
                            errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFF2F2F7),
                                child: const Icon(Icons.error)),
                          ),
                        if (isPending)
                          const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          _buildReactions(messageId, isMe),
          _buildTimestamp(msg.timestamp, isMe),
        ],
      ),
    );
  }

  Widget _buildVideoMessageFromLocal(String messageId, MessageChat msg,
      bool isMe, bool isLastInGroup, bool isPending) {
    final parts = msg.content.split('|');
    final videoUrl = parts.isNotEmpty ? parts[0] : '';
    final thumbnailUrl = parts.length > 1 ? parts[1] : '';

    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && isLastInGroup) _buildSenderInfo(msg.idFrom),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                isLastInGroup
                    ? _buildAvatar(msg.idFrom)
                    : const SizedBox(width: 40),
              GestureDetector(
                onTap: () {
                  if (!isPending) {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerPage(videoUrl: videoUrl),
                      ),
                    );
                  }
                },
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  _showMessageOptions(msg, messageId);
                },
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.65,
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!isPending && thumbnailUrl.isNotEmpty)
                          Image.network(
                            thumbnailUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, __, ___) =>
                                Container(color: Colors.black54),
                          )
                        else
                          Container(color: Colors.black54),
                        if (isPending)
                          const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white))
                        else
                          const Icon(Icons.play_circle_fill_rounded,
                              size: 56, color: Colors.white),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam,
                                    size: 12, color: Colors.white),
                                SizedBox(width: 4),
                                Text('Video',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          _buildReactions(messageId, isMe),
          _buildTimestamp(msg.timestamp, isMe),
        ],
      ),
    );
  }

  Widget _buildVoiceMessage(MessageChat msg, bool isMe) {
    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe) _buildSenderInfo(msg.idFrom),
        Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) _buildAvatar(msg.idFrom),
            const SizedBox(width: 4),
            VoiceMessageWidget(
              voiceUrl: msg.content,
              isMyMessage: isMe,
              voiceProvider: _voiceProvider!,
            ),
          ],
        ),
        _buildTimestamp(msg.timestamp, isMe),
      ],
    );
  }

  Widget _buildStickerMessage(MessageChat msg, bool isMe, String messageId) {
    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe) _buildSenderInfo(msg.idFrom),
        Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMe) _buildAvatar(msg.idFrom),
            const SizedBox(width: 4),
            GestureDetector(
              onLongPress: () => _showMessageOptions(msg, messageId),
              child: Image.asset(
                'images/${msg.content}.gif',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    width: 100,
                    height: 100,
                    color: const Color(0xFFF2F2F7),
                    child: const Icon(Icons.error)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildViewOnceMessageFromLocal(
      MessageChat msg, Map<dynamic, dynamic> localData, String messageId) {
    final isMe = msg.idFrom == _currentUserId;
    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe) _buildSenderInfo(msg.idFrom),
        Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMe) _buildAvatar(msg.idFrom),
            const SizedBox(width: 4),
            ViewOnceMessageWidget(
              groupChatId: _groupChatId,
              messageId: messageId,
              content: msg.content,
              type: msg.type,
              currentUserId: _currentUserId,
              isViewed: localData['isViewed'] ?? false,
              provider: _viewOnceProvider,
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // REACTIONS & TIMESTAMP
  // ---------------------------------------------------------------------------

  Widget _buildReactions(String messageId, bool isMe) {
    return StreamBuilder<QuerySnapshot>(
      stream: _reactionProvider.getReactions(_groupChatId, messageId),
      builder: (_, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final reactions = <String, int>{};
        final userReactions = <String, bool>{};
        for (final doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final emoji = d['emoji'] as String;
          final uid = d['userId'] as String;
          reactions[emoji] = (reactions[emoji] ?? 0) + 1;
          if (uid == _currentUserId) userReactions[emoji] = true;
        }
        return Padding(
          padding: EdgeInsets.only(left: isMe ? 0 : 45, top: 2),
          child: MessageReactionsDisplay(
            reactions: reactions,
            currentUserId: _currentUserId,
            userReactions: userReactions,
            onReactionTap: (emoji) => _reactionProvider.toggleReaction(
                _groupChatId, messageId, _currentUserId, emoji),
          ),
        );
      },
    );
  }

  Widget _buildTimestamp(String ts, bool isMe) {
    String label = '';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
      final now = DateTime.now();
      label = now.difference(dt).inDays == 0
          ? DateFormat('HH:mm').format(dt)
          : DateFormat('MMM dd HH:mm').format(dt);
    } catch (_) {}
    return Padding(
      padding:
          EdgeInsets.only(left: isMe ? 0 : 52, right: isMe ? 8 : 0, bottom: 0),
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
    );
  }

  // ---------------------------------------------------------------------------
  // TYPING INDICATOR
  // ---------------------------------------------------------------------------

  Widget _buildTypingIndicator() {
    if (_presenceProvider == null) return const SizedBox.shrink();
    return StreamBuilder<Map<String, bool>>(
      stream: _presenceProvider!.getTypingStatus(_groupChatId),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final typingUsers = snap.data!.entries
            .where((e) => e.key != _currentUserId && e.value)
            .map((e) => _getSenderName(e.key))
            .toList();
        if (typingUsers.isEmpty) return const SizedBox.shrink();
        final label = typingUsers.length == 1
            ? typingUsers.first
            : '${typingUsers.length} people';
        return TypingIndicator(userName: label);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MENTION SUGGESTIONS
  // ---------------------------------------------------------------------------

  Widget _buildMentionSuggestions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _memberSuggestions.length,
        itemBuilder: (_, i) {
          final m = _memberSuggestions[i];
          final userId = m['userId'] as String? ?? '';
          final name = m['name'] as String? ?? '';
          if (userId.isEmpty || name.isEmpty) return const SizedBox.shrink();
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF007AFF).withOpacity(0.1),
              child: Text(
                name.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: Color(0xFF007AFF), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text('@$name',
                style: const TextStyle(
                    color: Color(0xFF111418),
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            onTap: () => _insertMention(userId, name),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STICKERS
  // ---------------------------------------------------------------------------

  Widget _buildStickers() {
    return Container(
      decoration: const BoxDecoration(
          border: Border(
              top: BorderSide(color: ColorConstants.greyColor2, width: 0.5)),
          color: Colors.white),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStickerRow(['mimi1', 'mimi2', 'mimi3']),
          _buildStickerRow(['mimi4', 'mimi5', 'mimi6']),
          _buildStickerRow(['mimi7', 'mimi8', 'mimi9']),
        ],
      ),
    );
  }

  Widget _buildStickerRow(List<String> stickers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: stickers
          .map((s) => TextButton(
              onPressed: () => _onSendMessage(s, TypeMessage.sticker),
              child: Image.asset('images/$s.gif',
                  width: 50, height: 50, fit: BoxFit.cover)))
          .toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // FEATURES MENU
  // ---------------------------------------------------------------------------

  Widget _buildFeaturesMenu() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: ColorConstants.greyColor2))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _featureBtn(Icons.image_rounded, 'Ảnh', _onPickImage),
            _featureBtn(Icons.videocam_rounded, 'Video', _onPickVideo),

            // --- Giai đoạn 3: Tính năng Viral & Game ---
            _featureBtn(Icons.games, 'Caro 3x3', () {
              setState(() => _showFeaturesMenu = false);
              String gameState = jsonEncode({
                'board': ["", "", "", "", "", "", "", "", ""],
                'turn': "",
                'winner': "",
                'playerX': "",
                'playerO': ""
              });
              _onSendMessage(gameState, 7); // 7 is TypeMessage.game
            }),
            _featureBtn(Icons.air, 'Thổi bóng', () {
              setState(() => _showFeaturesMenu = false);
              _onSendMessage(
                  "Bí mật: Hôm nay đi nhậu không?", 8); // 8 is TypeMessage.blow
            }),
            _featureBtn(Icons.vibration, 'Lắc máy', () {
              setState(() => _showFeaturesMenu = false);
              _onSendMessage(
                  "Surprise! Quà của bạn đây 🎁", 9); // 9 is TypeMessage.shake
            }),

            _featureBtn(Icons.attach_file, 'Tài liệu', () {
              setState(() => _showFeaturesMenu = false);
              _onPickDocument();
            }),
            _featureBtn(Icons.poll, 'Bình chọn', () {
              setState(() => _showFeaturesMenu = false);
              showDialog(
                context: context,
                builder: (_) => CreatePollDialog(
                  onCreate: (question, options) {
                    final opts = options
                        .asMap()
                        .entries
                        .map((e) => {
                              'id': e.key.toString(),
                              'text': e.value,
                              'votes': <String>[],
                            })
                        .toList();
                    final content =
                        jsonEncode({'question': question, 'options': opts});
                    _onSendMessage(content, TypeMessage.poll);
                  },
                ),
              );
            }),
            _featureBtn(Icons.visibility_off, 'View Once', () {
              setState(() => _showFeaturesMenu = false);
              _sendViewOnce();
            }),
            _featureBtn(Icons.timer, 'Auto-Delete', () {
              setState(() => _showFeaturesMenu = false);
              _showAutoDeleteSettings();
            }),
            _featureBtn(Icons.location_on, 'Location', () {
              setState(() => _showFeaturesMenu = false);
              _shareLocation();
            }),
            _featureBtn(Icons.schedule_send, 'Schedule', () {
              setState(() => _showFeaturesMenu = false);
              _scheduleMessage();
            }),
          ],
        ),
      ),
    );
  }

  Widget _featureBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        if (resourceManager.isDisposed) return;
        onTap();
      },
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF007AFF), size: 26),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF007AFF)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INPUT BAR
  // ---------------------------------------------------------------------------

  Widget _buildInput() {
    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 12,
        left: 16,
        right: 16,
        top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Smart replies
          if (_smartReplies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
          // Reply preview — tap to scroll to original message (Giai đoạn 2)
          if (_replyingTo != null)
            GestureDetector(
              onTap: () {
                if (_replyingToMessageId != null) {
                  _scrollToMessage(_replyingToMessageId!);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04), blurRadius: 8)
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded,
                        color: Color(0xFF007AFF), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying to $_replyingToSenderName: ${_replyingTo!.content}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8E8E93),
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _replyingTo = null;
                          _replyingToSenderName = null;
                          _replyingToMessageId = null;
                        });
                      },
                      child: const Icon(Icons.close_rounded,
                          size: 20, color: Color(0xFF8E8E93)),
                    ),
                  ],
                ),
              ),
            ),
          // Recording indicator
          if (_isRecording)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04), blurRadius: 8)
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.fiber_manual_record,
                      color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Text('Recording... $_recordingDuration',
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  BouncingWrapper(
                    onTap: _cancelRecording,
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.delete, color: Colors.red, size: 20),
                    ),
                  ),
                  BouncingWrapper(
                    onTap: _stopRecording,
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child:
                          Icon(Icons.send, color: Color(0xFF007AFF), size: 20),
                    ),
                  ),
                ],
              ),
            ),
          // Main input row
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 6))
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                BouncingWrapper(
                  onTap: _toggleFeaturesMenu,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Icon(
                      _showFeaturesMenu
                          ? Icons.close_rounded
                          : Icons.add_circle_rounded,
                      color: const Color(0xFF8E8E93),
                      size: 28,
                    ),
                  ),
                ),
                if (!_showFeaturesMenu)
                  BouncingWrapper(
                    onTap: _onPickImage,
                    child: const Padding(
                      padding: EdgeInsets.all(10.0),
                      child: Icon(Icons.image_rounded,
                          color: Color(0xFF8E8E93), size: 26),
                    ),
                  ),
                BouncingWrapper(
                  onTap: _getSticker,
                  child: const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: Icon(Icons.face, color: Color(0xFF8E8E93), size: 26),
                  ),
                ),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding:
                        const EdgeInsets.only(right: 8, top: 12, bottom: 12),
                    child: TextField(
                      controller:
                          _chatInputController, // MentionTextEditingController
                      focusNode: _focusNode,
                      style: const TextStyle(
                          fontSize: 16, color: Color(0xFF111418)),
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      onTapOutside: (_) => Utilities.closeKeyboard(),
                      decoration: const InputDecoration.collapsed(
                        hintText: 'Type a message... (@ to mention)',
                        hintStyle: TextStyle(color: Color(0xFF8E8E93)),
                      ),
                      onChanged: _handleTextChange,
                    ),
                  ),
                ),
                BouncingWrapper(
                  scaleFactor: 0.85,
                  onTap: () {
                    if (_chatInputController.text.trim().isNotEmpty) {
                      _onSendMessage(
                          _chatInputController.text, TypeMessage.text);
                    } else {
                      _startRecording();
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                        color: Color(0xFF007AFF), shape: BoxShape.circle),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _chatInputController,
                      builder: (context, value, child) {
                        final hasText = value.text.trim().isNotEmpty;
                        return Icon(
                          hasText ? Icons.send_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 20,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

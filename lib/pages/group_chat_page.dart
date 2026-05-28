import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/utils/utils.dart';
import 'package:flutter_chat_demo/widgets/swipe_reply_cards.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GroupChatPage
// ─────────────────────────────────────────────────────────────────────────────

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key, required this.group});
  final Group group;

  @override
  GroupChatPageState createState() => GroupChatPageState();
}

class GroupChatPageState extends State<GroupChatPage>
    with WidgetsBindingObserver, ResourceManagerMixin {
  // ── state ──────────────────────────────────────────────────────────────────
  late String _currentUserId;
  int _limit = 30;
  final int _limitIncrement = 20;

  bool _isLoading = false;
  bool _isLoadingMedia = false;

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

  Map<String, String> _memberNames = {};
  final Map<String, String> _avatarUrlCache = {};

  List<SmartReply> _smartReplies = [];
  final Map<String, dynamic> _scamResults = {};
  String? _pendingScrollToMessageId;

  bool _isAutoPilotOn = false;
  bool _isShowingSwipeCards = false;
  List<String> _swipeReplies = [];
  String _lastAutoRepliedMessageId = '';
  StreamSubscription? _autoPilotSubscription;

  // ── providers ──────────────────────────────────────────────────────────────
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

  // ── controllers ────────────────────────────────────────────────────────────
  late MentionTextEditingController _chatInputController;
  late ScrollController _listScrollController;
  late FocusNode _focusNode;

  final Map<String, Timer> _scheduledMessages = {};
  final Map<String, String> _scheduledMessageContents = {};

  String get groupChatId => widget.group.id;

  // ── colour palette ─────────────────────────────────────────────────────────
  static const _bg = Color(0xFF0D0F14);
  static const _surface = Color(0xFF181B24);
  static const _accent = Color(0xFF4F8EF7);
  static const _accentGlow = Color(0x334F8EF7);
  static const _textPrimary = Color(0xFFEEF2FF);
  static const _textSecondary = Color(0xFF8B93B0);
  static const _divider = Color(0xFF252A3A);
  static const _bubbleSent = Color(0xFF1A4A9E);
  static const _bubbleRecv = Color(0xFF1E2233);

  // ── lifecycle ──────────────────────────────────────────────────────────────

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
        _listenForAutoPilot();
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
          MaterialPageRoute(builder: (_) => LoginPage()), (_) => false);
      return;
    }
    _chatProvider.listenToFirebaseChanges(
        groupChatId, _currentUserId, groupChatId);
    _markMessagesAsRead();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!resourceManager.isDisposed && mounted) _loadSmartReplies();
    });
  }

  void _scrollListener() {
    if (resourceManager.isDisposed || !_listScrollController.hasClients) return;
    final pos = _listScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 && !pos.outOfRange) {
      final total = LocalDbService().getMessages(groupChatId).length;
      if (_limit < total && mounted) setState(() => _limit += _limitIncrement);
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
    _autoPilotSubscription?.cancel();
    _recordingTimer?.cancel();
    _scheduledMessages.forEach((_, t) => t.cancel());
    _scheduledMessages.clear();
    _scheduledMessageContents.clear();
    try {
      _presenceProvider?.setTypingStatus(
          conversationId: groupChatId, userId: _currentUserId, isTyping: false);
      _voiceProvider?.dispose();
    } catch (_) {}
    _chatInputController.dispose();
    _listScrollController.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── member names ────────────────────────────────────────────────────────────

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

  // ── pinned messages ─────────────────────────────────────────────────────────

  void _loadPinnedMessages() {
    if (resourceManager.isDisposed) return;
    final sub = _messageProvider.getPinnedMessages(groupChatId).listen((snap) {
      if (!mounted || resourceManager.isDisposed) return;
      setState(() => _pinnedMessages = snap.docs);
    }, onError: (_) {});
    resourceManager.addSubscription(sub);
  }

  // ── text / mentions ─────────────────────────────────────────────────────────

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
    _presenceProvider?.setTypingStatus(
      conversationId: groupChatId,
      userId: _currentUserId,
      isTyping: text.isNotEmpty,
    );
  }

  void _showAdaptiveUISuggestion() {
    if (resourceManager.isDisposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.accessibility_new, color: Colors.white),
        SizedBox(width: 8),
        Expanded(child: Text('Khó gõ? Bật Elder Mode để font lớn hơn!')),
      ]),
      duration: const Duration(seconds: 7),
      backgroundColor: const Color(0xFF1E2233),
      action: SnackBarAction(
        label: 'BẬT',
        textColor: Colors.amberAccent,
        onPressed: () {
          try {
            context.read<AppModeProvider>().setMode(AppMode.elder);
          } catch (_) {}
        },
      ),
    ));
  }

  // ── read receipts ───────────────────────────────────────────────────────────

  Future<void> _markMessagesAsRead() async {
    if (resourceManager.isDisposed) return;
    try {
      final unread = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
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

  // ── send message ────────────────────────────────────────────────────────────

  Future<void> _onSendMessage(String content, int type) async {
    if (resourceManager.isDisposed) return;
    if (content.trim().isEmpty && type == TypeMessage.text) {
      _showToast('Nothing to send');
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
          finalContent, type, groupChatId, _currentUserId, groupChatId);
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(groupChatId)
          .set({
        FirestoreConstants.isGroup: true,
        FirestoreConstants.participants: widget.group.memberIds,
        FirestoreConstants.lastMessage: finalContent,
        FirestoreConstants.lastMessageTime:
            DateTime.now().millisecondsSinceEpoch.toString(),
        FirestoreConstants.lastMessageType: type,
      }, SetOptions(merge: true));
      await _autoDeleteProvider.scheduleMessageDeletion(
        groupChatId: groupChatId,
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        conversationId: groupChatId,
      );
    } catch (_) {
      _showToast('Send failed');
    }

    if (_listScrollController.hasClients && !resourceManager.isDisposed) {
      _listScrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _loadSmartReplies() {
    if (resourceManager.isDisposed) return;
    final messages = LocalDbService().getMessages(groupChatId);
    if (messages.isEmpty) return;
    final last = messages.first;
    if (last['idFrom'] != _currentUserId && last['type'] == TypeMessage.text) {
      final replies = _smartReplyProvider.getRuleBasedReplies(last['content']);
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _smartReplies = replies);
      }
    }
  }

  // ── media ───────────────────────────────────────────────────────────────────

  Future<void> _onPickImage() async {
    HapticFeedback.lightImpact();
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null) {
        await _processAndSendMedia(File(file.path), isVideo: false);
      }
    } catch (_) {
      _showToast('Cannot pick image');
    }
  }

  Future<void> _onPickVideo() async {
    HapticFeedback.lightImpact();
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file != null) {
        await _processAndSendMedia(File(file.path), isVideo: true);
      }
    } catch (_) {
      _showToast('Cannot pick video');
    }
  }

  Future<void> _processAndSendMedia(File file, {required bool isVideo}) async {
    if (resourceManager.isDisposed) return;
    final label = isVideo ? 'Video' : 'Photo';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => SafeSendDialog(
        title: 'Send $label',
        content:
            'Are you sure you want to send this ${isVideo ? 'video' : 'photo'} to the group?',
        icon: isVideo ? Icons.videocam_rounded : Icons.image_rounded,
      ),
    );
    if (confirm != true || resourceManager.isDisposed) return;
    if (mounted) setState(() => _isLoadingMedia = true);
    try {
      final success = await _chatProvider.sendMediaMessage(
        originalFile: file,
        isVideo: isVideo,
        groupChatId: groupChatId,
        currentUserId: _currentUserId,
        peerId: groupChatId,
        onLoadingStatusChanged: (loading) {
          if (mounted) setState(() => _isLoadingMedia = loading);
        },
      );
      if (!mounted || resourceManager.isDisposed) return;
      if (success != false) {
        if (_listScrollController.hasClients) {
          _listScrollController.animateTo(0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
        _showToast(isVideo ? '🎬 Video sent' : '📷 Photo sent',
            isSuccess: true);
      }
    } catch (_) {
      _showToast('Failed to send $label');
    } finally {
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _isLoadingMedia = false);
      }
    }
  }

  Future<void> _onPickDocument() async {
    HapticFeedback.lightImpact();
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;
        final fileSize = result.files.single.size;
        if (mounted) setState(() => _isLoadingMedia = true);
        final fileUrl =
            await _chatProvider.uploadFileAndGetUrl(file, groupChatId);
        if (fileUrl != null && mounted) {
          final content =
              jsonEncode({'url': fileUrl, 'name': fileName, 'size': fileSize});
          await _onSendMessage(content, TypeMessage.document);
        }
      }
    } catch (_) {
      _showToast('Error picking file');
    } finally {
      if (mounted) setState(() => _isLoadingMedia = false);
    }
  }

  // ── voice recording ─────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_voiceProvider == null || resourceManager.isDisposed) {
      _showToast('Voice not available');
      return;
    }
    if (!await _voiceProvider!.initRecorder()) {
      _showToast('Microphone permission required');
      return;
    }
    if (await _voiceProvider!.startRecording() &&
        mounted &&
        !resourceManager.isDisposed) {
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
      _showToast('Recording failed');
      return;
    }
    if (mounted && !resourceManager.isDisposed) {
      setState(() {
        _isRecording = false;
        _isLoading = true;
      });
    }
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    final uploadResult =
        await _voiceProvider!.uploadVoiceMessage(path, fileName);
    if (mounted && !resourceManager.isDisposed) {
      setState(() => _isLoading = false);
    }
    if (uploadResult != null && !resourceManager.isDisposed) {
      await _onSendMessage(uploadResult.url, 3);
      _showToast('🎤 Voice sent', isSuccess: true);
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

  // ── location ────────────────────────────────────────────────────────────────

  Future<void> _shareLocation() async {
    if (_locationProvider == null || resourceManager.isDisposed) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      if (!await _locationProvider!.requestLocationPermission()) {
        _showToast('Location permission required');
        return;
      }
      final data = await _locationProvider!.getCurrentLocationWithDetails();
      if (data != null && !resourceManager.isDisposed) {
        await _onSendMessage(
            _locationProvider!.formatLocationMessage(data), TypeMessage.text);
        _showToast('📍 Location shared', isSuccess: true);
      }
    } catch (_) {
    } finally {
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

  // ── auto-pilot ──────────────────────────────────────────────────────────────

  void _listenForAutoPilot() {
    _autoPilotSubscription = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) async {
      if (snap.docs.isEmpty || !_isAutoPilotOn) return;
      final data = snap.docs.first.data();
      final String idFrom = data['idFrom'] ?? '';
      final String content = data['content'] ?? '';
      final String msgId = data['timestamp'] ?? '';
      if (idFrom != _currentUserId &&
          idFrom != 'AI_BOT' &&
          !content.startsWith('[AI]') &&
          msgId != _lastAutoRepliedMessageId) {
        _lastAutoRepliedMessageId = msgId;
        try {
          final result = await FirebaseFunctions.instance
              .httpsCallable('generateAutoPilotReply')
              .call({
            'incomingMessage': content,
            'myStyleContext':
                'Thường dùng từ gen Z: okela, chịu, đỉnh, emoji 😂🔥',
          });
          await _onSendMessage(
              "[AI]: ${result.data['reply']}", TypeMessage.text);
        } catch (e) {
          debugPrint('Auto-Pilot Error: $e');
        }
      }
    });
  }

  Future<void> _triggerZeroTypeSwipe() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final messages = LocalDbService().getMessages(groupChatId);
      final lastMsg = messages.isNotEmpty
          ? (messages.first['content'] ?? 'Hello')
          : 'Hello';
      final result = await FirebaseFunctions.instance
          .httpsCallable('generateSwipeReplies')
          .call({'incomingMessage': lastMsg, 'contextMessages': ''});
      final replies = List<String>.from(result.data as List);
      if (mounted) {
        setState(() {
          _swipeReplies = replies;
          _isShowingSwipeCards = true;
        });
      }
    } catch (_) {
      _showToast('AI unavailable');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendGeoLockedMessage() async {
    setState(() => _showFeaturesMenu = false);
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => _GeoLockDialog(
        textController: ctrl,
        onSend: () async {
          Navigator.pop(context);
          if (mounted) setState(() => _isLoading = true);
          try {
            final pos = await Geolocator.getCurrentPosition();
            final content = jsonEncode({
              'text': ctrl.text,
              'lat': pos.latitude,
              'lng': pos.longitude,
            });
            await _onSendMessage(content, TypeMessage.geoLocked);
          } catch (_) {
            _showToast('GPS error');
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },
      ),
    );
    ctrl.dispose();
  }

  void _showAIContextAnalysis() {
    final messages = LocalDbService().getMessages(groupChatId);
    if (messages.isEmpty) {
      _showToast('Not enough messages to analyse');
      return;
    }
    final recent = messages.take(20).map((d) {
      final sender = d['idFrom'] == _currentUserId
          ? 'Tôi'
          : (_memberNames[d['idFrom']] ?? 'Member');
      return '$sender: ${d['content']}';
    }).toList();

    if (!mounted || resourceManager.isDisposed) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AIAnalysisDialog(
        messages: recent.reversed.toList(),
      ),
    );
  }

  // ── message actions ─────────────────────────────────────────────────────────

  void _showMessageOptions(MessageChat message, String messageId) {
    if (resourceManager.isDisposed) return;
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
          _showToast('Copied to clipboard', isSuccess: true);
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
              groupChatId, messageId, newContent);
          if (ok) _showToast('Message edited', isSuccess: true);
        },
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirm = await _showConfirmDialog(
      title: 'Delete Message',
      message: 'Delete this message for everyone?',
      confirmLabel: 'Delete',
      isDangerous: true,
    );
    if (confirm == true) {
      final ok = await _messageProvider.deleteMessage(groupChatId, messageId);
      if (ok) _showToast('Message deleted', isSuccess: true);
    }
  }

  Future<void> _togglePin(String messageId, bool current) async {
    final ok = await _messageProvider.togglePinMessage(
        groupChatId, messageId, current);
    if (ok) _showToast(current ? 'Unpinned' : '📌 Pinned', isSuccess: true);
  }

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
    final time = await _pickReminderTime();
    if (time != null && !resourceManager.isDisposed) {
      await _reminderProvider.scheduleReminder(
        userId: _currentUserId,
        messageId: messageId,
        conversationId: groupChatId,
        reminderTime: time,
        message: message.content,
      );
      _showToast('⏰ Reminder set', isSuccess: true);
    }
  }

  Future<DateTime?> _pickReminderTime() async {
    DateTime selected = DateTime.now().add(const Duration(hours: 1));
    return showDialog<DateTime>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => _DarkDialog(
          title: 'Set Reminder',
          icon: Icons.alarm_rounded,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReminderTile(
                label: 'Date',
                value: DateFormat('MMM dd, yyyy').format(selected),
                icon: Icons.calendar_today_rounded,
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
              _ReminderTile(
                label: 'Time',
                value: DateFormat('HH:mm').format(selected),
                icon: Icons.access_time_rounded,
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
            _DialogBtn(label: 'Cancel', onTap: () => Navigator.pop(ctx)),
            _DialogBtn(
              label: 'Set',
              isPrimary: true,
              onTap: () => Navigator.pop(ctx, selected),
            ),
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
      _showToast('Invalid time');
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
    _showToast('📅 Scheduled for ${DateFormat('HH:mm').format(time)}',
        isSuccess: true);
  }

  void _sendViewOnce() {
    showDialog(
      context: context,
      builder: (_) => SendViewOnceDialog(
        onSend: (content, type, durationSeconds) async {
          await _viewOnceProvider.sendViewOnceMessage(
            groupChatId: groupChatId,
            currentUserId: _currentUserId,
            peerId: groupChatId,
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
        conversationId: groupChatId,
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
        backgroundColor: _surface,
        child: ReactionPicker(
          onEmojiSelected: (emoji) {
            _reactionProvider.toggleReaction(
                groupChatId, messageId, _currentUserId, emoji);
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
        conversationId: groupChatId, userId: _currentUserId, isTyping: false);
    Navigator.pop(context);
  }

  void _openSearch() async {
    final matchedId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SearchMessagesPage(
          groupChatId: groupChatId,
          peerName: widget.group.groupName,
          peerId: groupChatId,
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
    final all = LocalDbService().getMessages(groupChatId);
    final index = all.indexWhere((m) => m['messageId'] == id);
    if (index == -1) {
      if (mounted && _limit <= all.length) {
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

  Future<void> _clearHistory() async {
    final confirm = await _showConfirmDialog(
      title: 'Clear History',
      message: 'Delete all messages in this group? This cannot be undone.',
      confirmLabel: 'Clear',
      isDangerous: true,
    );
    if (confirm != true) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final msgs = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
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
      _showToast('History cleared', isSuccess: true);
    } catch (_) {
      _showToast('Failed to clear history');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await _showConfirmDialog(
      title: 'Leave Group',
      message: 'Are you sure you want to leave "${widget.group.groupName}"?',
      confirmLabel: 'Leave',
      isDangerous: true,
    );
    if (confirm != true) return;
    try {
      final newMembers =
          widget.group.memberIds.where((id) => id != _currentUserId).toList();
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(groupChatId)
          .update({FirestoreConstants.memberIds: newMembers});
      await _onSendMessage(
          '${_memberNames[_currentUserId] ?? 'User'} left the group',
          TypeMessage.text);
      if (mounted) Navigator.of(context).pop();
      _showToast('You left the group');
    } catch (_) {
      _showToast('Failed to leave group');
    }
  }

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
                    groupId: groupChatId, groupName: widget.group.groupName)));
      case 'search':
        _openSearch();
      case 'autodelete':
        _showAutoDeleteSettings();
      case 'clear':
        _clearHistory();
      case 'leave':
        _leaveGroup();
      default:
        _showToast('Coming soon');
    }
  }

  // helpers
  void _showToast(String msg, {bool isSuccess = false}) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor:
          isSuccess ? const Color(0xFF1A3A2A) : const Color(0xFF2A1A1A),
      textColor: isSuccess ? Colors.greenAccent : Colors.white70,
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDangerous = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (_) => _DarkDialog(
          title: title,
          icon:
              isDangerous ? Icons.warning_rounded : Icons.help_outline_rounded,
          iconColor: isDangerous ? const Color(0xFFFF5A5A) : _accent,
          content: Text(message,
              style: const TextStyle(
                  color: _textSecondary, fontSize: 14.5, height: 1.5)),
          actions: [
            _DialogBtn(
                label: 'Cancel', onTap: () => Navigator.pop(context, false)),
            _DialogBtn(
              label: confirmLabel,
              isPrimary: true,
              isDanger: isDangerous,
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _bg,
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
                  groupId: groupChatId,
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
      ),
    );
  }

  // ── app bar ─────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      scrolledUnderElevation: .5,
      surfaceTintColor: Colors.transparent,
      shadowColor: _divider,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: _accent, size: 20),
        onPressed: _onBackPress,
      ),
      title: InkWell(
        onTap: _openGroupInfo,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Hero(
                tag: 'group_avatar_${widget.group.id}',
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                        colors: [_accent, Color(0xFF6B4AE8)]),
                    border:
                        Border.all(color: _accent.withOpacity(.4), width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.transparent,
                    backgroundImage: widget.group.groupPhotoUrl.isNotEmpty
                        ? NetworkImage(widget.group.groupPhotoUrl)
                        : null,
                    child: widget.group.groupPhotoUrl.isEmpty
                        ? const Icon(Icons.group_rounded,
                            size: 20, color: Colors.white)
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
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.3),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${widget.group.memberIds.length} members',
                      style:
                          const TextStyle(color: _textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Auto-pilot toggle
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Auto',
                style: TextStyle(
                    fontSize: 11,
                    color: _isAutoPilotOn ? Colors.greenAccent : _textSecondary,
                    fontWeight: FontWeight.w700)),
            Transform.scale(
              scale: .75,
              child: Switch(
                value: _isAutoPilotOn,
                activeColor: Colors.greenAccent,
                trackColor: WidgetStateProperty.resolveWith((s) {
                  if (s.contains(WidgetState.selected)) {
                    return Colors.greenAccent.withOpacity(.3);
                  }
                  return _divider;
                }),
                onChanged: (val) {
                  setState(() => _isAutoPilotOn = val);
                  _showToast(val ? '🤖 Auto-pilot ON' : '✋ Auto-pilot OFF');
                },
              ),
            ),
          ],
        ),
        GroupVideoCallButton(
          groupId: groupChatId,
          groupName: widget.group.groupName,
          memberIds: widget.group.memberIds,
        ),
        IconButton(
          icon: const Icon(Icons.search_rounded, color: _accent, size: 22),
          onPressed: _openSearch,
        ),
        PopupMenuButton<String>(
          onSelected: _onMenuSelected,
          icon: const Icon(Icons.more_vert_rounded, color: _accent, size: 22),
          color: _surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          itemBuilder: (_) => [
            _menuItem('ai_assistant', Icons.auto_awesome, 'AI Assistant',
                Colors.purpleAccent),
            _menuItem(
                'info', Icons.info_outline_rounded, 'Group Info', _accent),
            _menuItem('media', Icons.perm_media_rounded, 'Media & Files',
                const Color(0xFF43C6AC)),
            _menuItem('search', Icons.search_rounded, 'Search Messages',
                _textSecondary),
            const PopupMenuDivider(),
            _menuItem('autodelete', Icons.timer_rounded, 'Auto-Delete',
                Colors.orangeAccent),
            _menuItem('clear', Icons.delete_sweep_rounded, 'Clear History',
                Colors.orangeAccent),
            const PopupMenuDivider(),
            _menuItem('leave', Icons.exit_to_app_rounded, 'Leave Group',
                const Color(0xFFFF5A5A),
                isDestructive: true),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, Color color,
      {bool isDestructive = false}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: isDestructive ? const Color(0xFFFF5A5A) : _textPrimary,
                  fontSize: 14,
                  fontWeight:
                      isDestructive ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }

  // ── chat content ────────────────────────────────────────────────────────────

  Widget _buildChatContent() {
    return Stack(
      children: [
        // Background pattern
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topRight,
              radius: 1.5,
              colors: [Color(0xFF131729), _bg],
            ),
          ),
        ),
        Column(
          children: [
            const OfflineIndicator(),
            if (_pinnedMessages.isNotEmpty) _buildPinnedMessages(),
            _buildListMessage(),
            _buildTypingIndicator(),
            if (_isShowSticker) _buildStickers(),
            if (_showFeaturesMenu) _buildFeaturesMenu(),
            if (!_isShowingSwipeCards) _buildInput(),
          ],
        ),
        if (_isLoading)
          const Positioned(
            child: _FullScreenLoader(),
          ),
        if (_isLoadingMedia) Positioned.fill(child: _buildMediaOverlay()),
        if (_isShowingSwipeCards)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SwipeReplyCards(
              replies: _swipeReplies,
              onSend: (text) async {
                await _onSendMessage(text, TypeMessage.text);
                setState(() => _isShowingSwipeCards = false);
              },
              onCancel: () => setState(() => _isShowingSwipeCards = false),
            ),
          ),
      ],
    );
  }

  Widget _buildMediaOverlay() {
    return Container(
      color: Colors.black.withOpacity(.6),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
            SizedBox(height: 16),
            Text('Optimising & uploading...',
                style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ── pinned messages ─────────────────────────────────────────────────────────

  Widget _buildPinnedMessages() {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _divider, width: .8)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _pinnedMessages.length,
        itemBuilder: (_, i) {
          final message = MessageChat.fromDocument(_pinnedMessages[i]);
          return Container(
            constraints: const BoxConstraints(maxWidth: 220),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _accentGlow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accent.withOpacity(.25), width: .8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.push_pin_rounded, size: 13, color: _accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    message.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: _textPrimary,
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

  // ── message list ────────────────────────────────────────────────────────────

  List<dynamic> _processMessages(List<Map<dynamic, dynamic>> raw) {
    final grouped = <dynamic>[];
    final mediaGroup = <Map<dynamic, dynamic>>[];

    for (final msg in raw) {
      final int type = msg['type'] ?? 0;
      final isMedia = type == TypeMessage.image || type == TypeMessage.video;

      if (isMedia) {
        if (mediaGroup.isEmpty) {
          mediaGroup.add(msg);
        } else {
          final prev = mediaGroup.last;
          final diff = (int.parse(prev['timestamp'] ?? '0') -
                  int.parse(msg['timestamp'] ?? '0'))
              .abs();
          if (msg['idFrom'] == prev['idFrom'] && diff <= 10000) {
            mediaGroup.add(msg);
          } else {
            grouped.add(mediaGroup.length == 1
                ? mediaGroup.first
                : {'isMediaGroup': true, 'messages': List.from(mediaGroup)});
            mediaGroup
              ..clear()
              ..add(msg);
          }
        }
      } else {
        if (mediaGroup.isNotEmpty) {
          grouped.add(mediaGroup.length == 1
              ? mediaGroup.first
              : {'isMediaGroup': true, 'messages': List.from(mediaGroup)});
          mediaGroup.clear();
        }
        grouped.add(msg);
      }
    }
    if (mediaGroup.isNotEmpty) {
      grouped.add(mediaGroup.length == 1
          ? mediaGroup.first
          : {'isMediaGroup': true, 'messages': List.from(mediaGroup)});
    }
    return grouped;
  }

  Widget _buildListMessage() {
    return Flexible(
      child: groupChatId.isNotEmpty
          ? ValueListenableBuilder(
              valueListenable: LocalDbService().messagesBox.listenable(),
              builder: (context, Box box, _) {
                final all = LocalDbService().getMessages(groupChatId);
                final display = all.take(_limit).toList();
                final grouped = _processMessages(display);

                if (grouped.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: _divider),
                          ),
                          child: const Icon(Icons.chat_bubble_outline_rounded,
                              size: 40, color: _textSecondary),
                        ),
                        const SizedBox(height: 16),
                        const Text('No messages yet',
                            style: TextStyle(
                                color: _textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        const Text('Say hello! 👋',
                            style:
                                TextStyle(color: _textSecondary, fontSize: 14)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  itemCount: grouped.length,
                  reverse: true,
                  controller: _listScrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemBuilder: (_, index) {
                    final item = grouped[index];
                    if (item is Map && item['isMediaGroup'] == true) {
                      return _buildMediaGroup(
                          List<Map<dynamic, dynamic>>.from(item['messages']));
                    }
                    return _buildItemMessage(
                        index, item as Map<dynamic, dynamic>, display);
                  },
                );
              },
            )
          : const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
    );
  }

  // ── media group grid ────────────────────────────────────────────────────────

  Widget _buildMediaGroup(List<Map<dynamic, dynamic>> messages) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final first = messages.first;
    final isMe = first['idFrom'] == _currentUserId;
    final messageId = first['messageId'] as String? ?? '';
    final representative = MessageChat(
      idFrom: first['idFrom'] ?? '',
      idTo: first['idTo'] ?? '',
      timestamp: first['timestamp'] ?? '',
      content: first['content'] ?? '',
      type: first['type'] ?? 0,
      isRead: first['status'] == 'sent',
    );

    return SwipeToReplyWrapper(
      isMe: isMe,
      onSwipe: () => _setReply(representative, messageId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe) _buildSenderName(first['idFrom']),
            Row(
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) _buildAvatar(first['idFrom']),
                SizedBox(
                  width: MediaQuery.of(context).size.width * .7,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
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
                      itemBuilder: (_, i) {
                        final m = messages[i];
                        final isVideo = m['type'] == TypeMessage.video;
                        final url = m['content'] ?? '';
                        final videoUrl = isVideo ? url.split('|').first : '';
                        final thumbUrl = isVideo
                            ? (url.split('|').length > 1
                                ? url.split('|')[1]
                                : '')
                            : url;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            isVideo
                                ? Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          VideoPlayerPage(videoUrl: videoUrl),
                                    ))
                                : Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          FullPhotoPage(url: thumbUrl),
                                    ));
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(thumbUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Container(color: _surfaceHigh)),
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
                ),
              ],
            ),
            _buildTimestamp(first['timestamp'] ?? '', isMe),
          ],
        ),
      ),
    );
  }

  // ── item message ────────────────────────────────────────────────────────────

  Widget _buildItemMessage(int index, Map<dynamic, dynamic> localData,
      List<Map<dynamic, dynamic>> fullList) {
    final isHighlighted = _pendingScrollToMessageId == localData['messageId'];
    final isPending = localData['status'] == 'pending';
    final msg = MessageChat(
      idFrom: localData['idFrom'] ?? '',
      idTo: localData['idTo'] ?? '',
      timestamp: localData['timestamp'] ?? '',
      content: localData['content'] ?? '',
      type: localData['type'] ?? 0,
      isRead: localData['status'] == 'sent',
    );

    bool isLastInGroup = true;
    if (index > 0) {
      isLastInGroup = fullList[index - 1]['idFrom'] != msg.idFrom;
    }

    final isMe = msg.idFrom == _currentUserId;
    final isViewOnce = localData['isViewOnce'] ?? false;
    final isScamWarning = localData['scamWarning'] ?? false;
    final scamReason = localData['scamReason'] ?? '';
    final hasReminder = localData['hasReminder'] ?? false;
    final messageId = localData['messageId'] ?? '';

    // Special message types
    Widget? special = _buildSpecialMessage(
        msg, messageId, isMe, isLastInGroup, localData, isViewOnce);
    if (special != null) {
      return SwipeToReplyWrapper(
          isMe: isMe, onSwipe: () => _setReply(msg, messageId), child: special);
    }

    // Voice
    Widget bubble;
    if (msg.type == 3 && _voiceProvider != null) {
      bubble = _buildVoiceMessage(msg, isMe);
    } else if (msg.type == TypeMessage.image) {
      bubble =
          _buildImageMessage(messageId, msg, isMe, isLastInGroup, isPending);
    } else if (msg.type == TypeMessage.video) {
      bubble =
          _buildVideoMessage(messageId, msg, isMe, isLastInGroup, isPending);
    } else if (msg.type == TypeMessage.sticker) {
      bubble = _buildStickerMessage(msg, isMe, messageId);
    } else {
      bubble = _buildTextMessage(
        messageId: messageId,
        msg: msg,
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
      onSwipe: () => _setReply(msg, messageId),
      child: bubble,
    );
  }

  Widget? _buildSpecialMessage(MessageChat msg, String messageId, bool isMe,
      bool isLastInGroup, Map<dynamic, dynamic> localData, bool isViewOnce) {
    Widget wrap(Widget child) => Container(
          margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                isLastInGroup
                    ? _buildAvatar(msg.idFrom)
                    : const SizedBox(width: 38),
              child,
            ],
          ),
        );

    if (isViewOnce) {
      return wrap(ViewOnceMessageWidget(
        groupChatId: groupChatId,
        messageId: messageId,
        content: msg.content,
        type: msg.type,
        currentUserId: _currentUserId,
        isViewed: localData['isViewed'] ?? false,
        provider: _viewOnceProvider,
      ));
    }
    if (msg.type == TypeMessage.geoLocked) {
      return wrap(GeoLockedMessageWidget(content: msg.content, isMe: isMe));
    }
    if (msg.type == 7) {
      return wrap(TicTacToeMessageWidget(
        content: msg.content,
        messageId: messageId,
        groupId: groupChatId,
        currentUserId: _currentUserId,
      ));
    }
    if (msg.type == 8) {
      return wrap(BlowMessageWidget(secretText: msg.content));
    }
    if (msg.type == 9) {
      return wrap(ShakeMessageWidget(secretText: msg.content));
    }
    if (msg.type == TypeMessage.poll) {
      return wrap(PollMessageWidget(
        content: msg.content,
        messageId: messageId,
        currentUserId: _currentUserId,
        onVote: (mId, optionId) => _chatProvider.votePoll(
          groupChatId: groupChatId,
          messageId: messageId,
          optionId: optionId,
          userId: _currentUserId,
        ),
      ));
    }
    if (msg.type == TypeMessage.document) {
      Map<String, dynamic> fileData = {};
      try {
        fileData = jsonDecode(msg.content);
      } catch (_) {}
      return Container(
        margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe)
              isLastInGroup
                  ? _buildAvatar(msg.idFrom)
                  : const SizedBox(width: 38),
            GestureDetector(
              onTap: () {
                final url = fileData['url'] as String? ?? '';
                if (url.isNotEmpty) launchUrl(Uri.parse(url));
              },
              onLongPress: () => _showMessageOptions(msg, messageId),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * .7),
                decoration: BoxDecoration(
                  color: isMe ? _bubbleSent : _bubbleRecv,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _divider, width: .8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.insert_drive_file_rounded,
                          color: _accent, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileData['name'] as String? ?? 'File',
                            style: const TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${((fileData['size'] as num? ?? 0) / 1024).toStringAsFixed(1)} KB',
                            style: const TextStyle(
                                color: _textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return null;
  }

  // ── avatar & sender name ────────────────────────────────────────────────────

  static const _surfaceHigh = Color(0xFF1E2233);

  Widget _buildSenderName(String senderId) {
    if (senderId == _currentUserId) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 42, bottom: 3),
      child: Text(
        _getSenderName(senderId),
        style: const TextStyle(
            color: _textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildAvatar(String senderId) {
    if (senderId == _currentUserId) return const SizedBox.shrink();
    final photoUrl = _avatarUrlCache[senderId] ?? '';
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 2),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [_accent, Color(0xFF6B4AE8)]),
        image: photoUrl.isNotEmpty
            ? DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: photoUrl.isEmpty
          ? Center(
              child: Text(
                (_memberNames[senderId] ?? 'U').substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            )
          : null,
    );
  }

  // ── text message bubble ─────────────────────────────────────────────────────

  Widget _buildTextMessage({
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
    final tailRadius = isLastInGroup ? 4.0 : 18.0;
    final location = _locationProvider?.parseLocationFromMessage(msg.content);

    Widget bubble = Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && isLastInGroup) _buildSenderName(msg.idFrom),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                isLastInGroup
                    ? _buildAvatar(msg.idFrom)
                    : const SizedBox(width: 36),
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
                        horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * .72),
                    decoration: BoxDecoration(
                      color: isMe ? _bubbleSent : _bubbleRecv,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : tailRadius),
                        bottomRight: Radius.circular(isMe ? tailRadius : 18),
                      ),
                      border: Border.all(
                        color: isMe ? _accent.withOpacity(.3) : _divider,
                        width: .8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.2),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe && isScamWarning)
                          _ScamBanner(reason: scamReason),
                        if (!isMe && hasReminder)
                          _ReminderBanner(
                              msg: msg,
                              messageId: messageId,
                              onSet: _setReminder),
                        if (msg.isDeleted)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.block_rounded,
                                  size: 14,
                                  color:
                                      isMe ? Colors.white38 : _textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                'Message deleted',
                                style: TextStyle(
                                    color:
                                        isMe ? Colors.white38 : _textSecondary,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 14),
                              ),
                            ],
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
                                    color: isMe ? Colors.white : _textPrimary,
                                    fontSize: 15.5,
                                    height: 1.35),
                              ),
                              if (isMe)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Icon(
                                      isPending
                                          ? Icons.access_time_rounded
                                          : msg.isRead
                                              ? Icons.done_all_rounded
                                              : Icons.done_rounded,
                                      size: 13,
                                      color:
                                          msg.isRead ? _accent : Colors.white38,
                                    ),
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
          // Scam scan
          if (!isMe && msg.type == TypeMessage.text) ...[
            if (_scamResults[messageId] != null &&
                _scamResults[messageId] != 'SAFE')
              ScamWarningWidget(status: _scamResults[messageId]!),
            if (_scamResults[messageId] == null && !isScamWarning)
              Padding(
                padding: const EdgeInsets.only(left: 44, top: 3),
                child: GestureDetector(
                  onTap: () async {
                    _showToast('🛡 Scanning message...');
                    final status =
                        await AIBackendService().checkScam(msg.content);
                    if (mounted) {
                      setState(() => _scamResults[messageId] = status);
                    }
                    if (status == 'SAFE') {
                      _showToast('✅ Message is safe', isSuccess: true);
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.shield_outlined,
                          size: 13, color: Colors.greenAccent),
                      SizedBox(width: 4),
                      Text('AI Scan',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.greenAccent)),
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
        color: _accent.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: bubble,
    );
  }

  Widget _buildLocationContent(LocationData location, bool isMe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_rounded,
                color: isMe ? Colors.white : Colors.redAccent, size: 18),
            const SizedBox(width: 5),
            Text('Location',
                style: TextStyle(
                    color: isMe ? Colors.white : _textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ],
        ),
        const SizedBox(height: 4),
        Text(location.address,
            style: TextStyle(
                color: isMe ? Colors.white70 : _textSecondary, fontSize: 12.5)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _openLocationInMaps(location.mapsUrl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withOpacity(.15)
                  : _accent.withOpacity(.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isMe ? Colors.white30 : _accent.withOpacity(.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_rounded,
                    size: 13, color: isMe ? Colors.white : _accent),
                const SizedBox(width: 5),
                Text('Open in Maps',
                    style: TextStyle(
                        fontSize: 12,
                        color: isMe ? Colors.white : _accent,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageMessage(String messageId, MessageChat msg, bool isMe,
      bool isLastInGroup, bool isPending) {
    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && isLastInGroup) _buildSenderName(msg.idFrom),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                isLastInGroup
                    ? _buildAvatar(msg.idFrom)
                    : const SizedBox(width: 36),
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * .62,
                    height: 210,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!isPending)
                          Image.network(
                            msg.content,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, prog) {
                              if (prog == null) return child;
                              return Container(
                                color: _surface,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                      color: _accent, strokeWidth: 2),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                                color: _surface,
                                child: const Icon(Icons.broken_image_rounded,
                                    color: _textSecondary)),
                          ),
                        if (isPending)
                          Container(
                            color: _surface,
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: _accent, strokeWidth: 2),
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

  Widget _buildVideoMessage(String messageId, MessageChat msg, bool isMe,
      bool isLastInGroup, bool isPending) {
    final parts = msg.content.split('|');
    final videoUrl = parts.isNotEmpty ? parts[0] : '';
    final thumbUrl = parts.length > 1 ? parts[1] : '';

    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe && isLastInGroup) _buildSenderName(msg.idFrom),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                isLastInGroup
                    ? _buildAvatar(msg.idFrom)
                    : const SizedBox(width: 36),
              GestureDetector(
                onTap: () {
                  if (!isPending) {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                VideoPlayerPage(videoUrl: videoUrl)));
                  }
                },
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  _showMessageOptions(msg, messageId);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * .62,
                    height: 195,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbUrl.isNotEmpty)
                          Image.network(thumbUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: Colors.black))
                        else
                          Container(color: Colors.black),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(.6)
                              ],
                            ),
                          ),
                        ),
                        if (isPending)
                          const Center(
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        else
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white54, width: 1.5),
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 32),
                            ),
                          ),
                        Positioned(
                          bottom: 8,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_rounded,
                                    size: 11, color: Colors.white),
                                SizedBox(width: 3),
                                Text('Video',
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.white)),
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
        if (!isMe) _buildSenderName(msg.idFrom),
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
        if (!isMe) _buildSenderName(msg.idFrom),
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
                width: 90,
                height: 90,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    width: 90,
                    height: 90,
                    color: _surface,
                    child:
                        const Icon(Icons.error_rounded, color: _textSecondary)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── reactions & timestamp ───────────────────────────────────────────────────

  Widget _buildReactions(String messageId, bool isMe) {
    return StreamBuilder<QuerySnapshot>(
      stream: _reactionProvider.getReactions(groupChatId, messageId),
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
          padding: EdgeInsets.only(left: isMe ? 0 : 42, top: 2),
          child: MessageReactionsDisplay(
            reactions: reactions,
            currentUserId: _currentUserId,
            userReactions: userReactions,
            onReactionTap: (emoji) => _reactionProvider.toggleReaction(
                groupChatId, messageId, _currentUserId, emoji),
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
          EdgeInsets.only(left: isMe ? 0 : 44, right: isMe ? 4 : 0, bottom: 2),
      child: Text(label,
          style: const TextStyle(fontSize: 10.5, color: _textSecondary)),
    );
  }

  // ── typing indicator ────────────────────────────────────────────────────────

  Widget _buildTypingIndicator() {
    if (_presenceProvider == null) return const SizedBox.shrink();
    return StreamBuilder<Map<String, TypingInfo>>(
      stream: _presenceProvider!.getTypingStatusStream(groupChatId),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final typing = snap.data!.entries
            .where((e) => e.key != _currentUserId && e.value.isTyping)
            .map((e) => _getSenderName(e.key))
            .toList();
        if (typing.isEmpty) return const SizedBox.shrink();
        final label =
            typing.length == 1 ? typing.first : '${typing.length} people';
        return TypingIndicator(userName: label);
      },
    );
  }

  // ── mention suggestions ─────────────────────────────────────────────────────

  Widget _buildMentionSuggestions() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: .8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.2),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _memberSuggestions.length,
        itemBuilder: (_, i) {
          final m = _memberSuggestions[i];
          final userId = m['userId'] as String? ?? '';
          final name = m['name'] as String? ?? '';
          if (userId.isEmpty || name.isEmpty) {
            return const SizedBox.shrink();
          }
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: _accentGlow,
              child: Text(
                name.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: _accent, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            title: Text('@$name',
                style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            onTap: () => _insertMention(userId, name),
          );
        },
      ),
    );
  }

  // ── stickers ────────────────────────────────────────────────────────────────

  Widget _buildStickers() {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _divider, width: .8)),
      ),
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
                    width: 50, height: 50, fit: BoxFit.cover),
              ))
          .toList(),
    );
  }

  // ── features menu ───────────────────────────────────────────────────────────

  Widget _buildFeaturesMenu() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 110),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _divider, width: .8)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            _featureBtn(Icons.image_rounded, 'Photo', _onPickImage,
                color: _accent),
            _featureBtn(Icons.videocam_rounded, 'Video', _onPickVideo,
                color: const Color(0xFFFF6B9D)),
            _featureBtn(Icons.games_rounded, 'Caro', () {
              setState(() => _showFeaturesMenu = false);
              _onSendMessage(
                  jsonEncode({
                    'board': ["", "", "", "", "", "", "", "", ""],
                    'turn': "",
                    'winner': "",
                    'playerX': "",
                    'playerO': ""
                  }),
                  7);
            }, color: Colors.purpleAccent),
            _featureBtn(Icons.air_rounded, 'Blow', () {
              setState(() => _showFeaturesMenu = false);
              _onSendMessage("Bí mật: Hôm nay đi nhậu không?", 8);
            }, color: const Color(0xFF43C6AC)),
            _featureBtn(Icons.vibration_rounded, 'Shake', () {
              setState(() => _showFeaturesMenu = false);
              _onSendMessage("Surprise! Quà của bạn đây 🎁", 9);
            }, color: Colors.orangeAccent),
            _featureBtn(Icons.add_location_alt_rounded, 'GeoLock',
                _sendGeoLockedMessage,
                color: Colors.redAccent),
            _featureBtn(Icons.attach_file_rounded, 'File', () {
              setState(() => _showFeaturesMenu = false);
              _onPickDocument();
            }, color: const Color(0xFFFFB84D)),
            _featureBtn(Icons.poll_rounded, 'Poll', () {
              setState(() => _showFeaturesMenu = false);
              showDialog(
                context: context,
                builder: (_) => CreatePollDialog(
                  onCreate: (question, options,
                      {bool isMultipleChoice = false,
                      bool isAnonymous = false,
                      DateTime? expiresAt}) {
                    final opts = options
                        .asMap()
                        .entries
                        .map((e) => {
                              'id': e.key.toString(),
                              'text': e.value,
                              'votes': <String>[],
                            })
                        .toList();
                    final content = jsonEncode({
                      'question': question,
                      'options': opts,
                      'isMultipleChoice': isMultipleChoice,
                      'isAnonymous': isAnonymous,
                      if (expiresAt != null)
                        'expiresAt': expiresAt.toIso8601String(),
                    });
                    _onSendMessage(content, TypeMessage.poll);
                  },
                ),
              );
            }, color: const Color(0xFF4FD1C5)),
            _featureBtn(Icons.visibility_off_rounded, 'Once', () {
              setState(() => _showFeaturesMenu = false);
              _sendViewOnce();
            }, color: const Color(0xFF9B59B6)),
            _featureBtn(Icons.timer_rounded, 'Delete', () {
              setState(() => _showFeaturesMenu = false);
              _showAutoDeleteSettings();
            }, color: Colors.grey),
            _featureBtn(Icons.location_on_rounded, 'Location', () {
              setState(() => _showFeaturesMenu = false);
              _shareLocation();
            }, color: Colors.redAccent),
            _featureBtn(Icons.schedule_send_rounded, 'Schedule', () {
              setState(() => _showFeaturesMenu = false);
              _scheduleMessage();
            }, color: const Color(0xFF43C6AC)),
          ],
        ),
      ),
    );
  }

  Widget _featureBtn(IconData icon, String label, VoidCallback onTap,
      {Color color = _accent}) {
    return InkWell(
      onTap: resourceManager.isDisposed ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 68,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(.25), width: .8),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 10.5,
                    color: _textSecondary,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── input bar ───────────────────────────────────────────────────────────────

  Widget _buildInput() {
    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        left: 12,
        right: 12,
        top: 6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Smart replies
          if (_smartReplies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
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
          // Reply preview
          if (_replyingTo != null)
            GestureDetector(
              onTap: () {
                if (_replyingToMessageId != null) {
                  _scrollToMessage(_replyingToMessageId!);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _accent.withOpacity(.4), width: .8),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(.1), blurRadius: 6)
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replying to $_replyingToSenderName',
                            style: const TextStyle(
                                color: _accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _replyingTo!.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: _textSecondary),
                          ),
                        ],
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
                          size: 18, color: _textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          // Recording
          if (_isRecording)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.withOpacity(.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fiber_manual_record_rounded,
                      color: Colors.red, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    'Recording  $_recordingDuration',
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5),
                  ),
                  const Spacer(),
                  BouncingWrapper(
                    onTap: _cancelRecording,
                    child: const Icon(Icons.delete_rounded,
                        color: Colors.red, size: 22),
                  ),
                  const SizedBox(width: 12),
                  BouncingWrapper(
                    onTap: _stopRecording,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: _accent, shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          // Main row
          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _divider, width: .8),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Add
                BouncingWrapper(
                  onTap: _toggleFeaturesMenu,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Icon(
                      _showFeaturesMenu
                          ? Icons.close_rounded
                          : Icons.add_rounded,
                      color: _showFeaturesMenu ? Colors.red : _accent,
                      size: 26,
                    ),
                  ),
                ),
                // Image quick
                if (!_showFeaturesMenu)
                  BouncingWrapper(
                    onTap: _onPickImage,
                    child: const Padding(
                      padding: EdgeInsets.all(10.0),
                      child: Icon(Icons.image_rounded,
                          color: _textSecondary, size: 24),
                    ),
                  ),
                // Sticker
                BouncingWrapper(
                  onTap: _getSticker,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Icon(
                      Icons.sentiment_satisfied_alt_rounded,
                      color: _isShowSticker ? _accent : _textSecondary,
                      size: 24,
                    ),
                  ),
                ),
                // Text field
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding:
                        const EdgeInsets.only(right: 8, top: 12, bottom: 12),
                    child: TextField(
                      controller: _chatInputController,
                      focusNode: _focusNode,
                      style:
                          const TextStyle(fontSize: 15.5, color: _textPrimary),
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      onTapOutside: (_) => Utilities.closeKeyboard(),
                      decoration: const InputDecoration.collapsed(
                        hintText: 'Message... (@mention)',
                        hintStyle: TextStyle(color: _textSecondary),
                      ),
                      onChanged: _handleTextChange,
                    ),
                  ),
                ),
                // AI swipe
                BouncingWrapper(
                  onTap: _triggerZeroTypeSwipe,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Icon(Icons.auto_awesome_rounded,
                        color: _isAutoPilotOn
                            ? Colors.purpleAccent
                            : _textSecondary,
                        size: 24),
                  ),
                ),
                // Send / mic
                BouncingWrapper(
                  scaleFactor: .85,
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
                      gradient: LinearGradient(
                        colors: [_accent, Color(0xFF6B4AE8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _chatInputController,
                      builder: (_, val, __) => Icon(
                        val.text.trim().isNotEmpty
                            ? Icons.send_rounded
                            : Icons.mic_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ScamBanner extends StatelessWidget {
  const _ScamBanner({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5A5A).withOpacity(.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF5A5A).withOpacity(.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFF5A5A), size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'AI Warning: $reason',
              style: const TextStyle(
                  color: Color(0xFFFF5A5A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderBanner extends StatelessWidget {
  const _ReminderBanner({
    required this.msg,
    required this.messageId,
    required this.onSet,
  });
  final MessageChat msg;
  final String messageId;
  final Future<void> Function(MessageChat, String) onSet;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF4F8EF7).withOpacity(.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4F8EF7).withOpacity(.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.alarm_add_rounded,
              color: Color(0xFF4F8EF7), size: 15),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'AI: Task detected — set a reminder?',
              style: TextStyle(color: Color(0xFF4F8EF7), fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: () => onSet(msg, messageId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF4F8EF7).withOpacity(.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Set',
                  style: TextStyle(
                      color: Color(0xFF4F8EF7),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkDialog extends StatelessWidget {
  const _DarkDialog({
    required this.title,
    required this.icon,
    required this.content,
    required this.actions,
    this.iconColor = const Color(0xFF4F8EF7),
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF181B24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: Color(0xFFEEF2FF),
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 20),
            Row(
              children: actions
                  .expand(
                      (w) => [Expanded(child: w), const SizedBox(width: 10)])
                  .toList()
                ..removeLast(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogBtn extends StatelessWidget {
  const _DialogBtn({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.isDanger = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xFF252A3A);
    Color fg = const Color(0xFFEEF2FF);
    if (isPrimary && !isDanger) {
      bg = const Color(0xFF4F8EF7);
      fg = Colors.white;
    } else if (isDanger) {
      bg = const Color(0xFFFF5A5A).withOpacity(.15);
      fg = const Color(0xFFFF5A5A);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF4F8EF7), size: 18),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Color(0xFF8B93B0), fontSize: 11.5)),
                Text(value,
                    style: const TextStyle(
                        color: Color(0xFFEEF2FF),
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8B93B0)),
          ],
        ),
      ),
    );
  }
}

class _GeoLockDialog extends StatelessWidget {
  const _GeoLockDialog({required this.textController, required this.onSend});
  final TextEditingController textController;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF181B24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.add_location_alt_rounded,
                    color: Colors.redAccent, size: 22),
                SizedBox(width: 10),
                Text('GPS-Locked Message',
                    style: TextStyle(
                        color: Color(0xFFEEF2FF),
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Recipient must be within 50m of your current location to read this message.',
              style: TextStyle(
                  color: Color(0xFF8B93B0), fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0F14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: textController,
                style: const TextStyle(color: Color(0xFFEEF2FF), fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Secret message...',
                  hintStyle: TextStyle(color: Color(0xFF8B93B0)),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  prefixIcon: Icon(Icons.lock_rounded,
                      color: Colors.redAccent, size: 18),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF252A3A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Cancel',
                          style: TextStyle(
                              color: Color(0xFF8B93B0),
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: onSend,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(.15),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.redAccent.withOpacity(.4)),
                      ),
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded,
                              color: Colors.redAccent, size: 16),
                          SizedBox(width: 6),
                          Text('Lock & Send',
                              style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AIAnalysisDialog extends StatelessWidget {
  const _AIAnalysisDialog({required this.messages});
  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF181B24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withOpacity(.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.purpleAccent, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('AI Analysing...',
                    style: TextStyle(
                        color: Color(0xFFEEF2FF),
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<String?>(
              future: AIBackendService()
                  .analyzeChatContext(messages, 'work', 'extract_tasks'),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 80,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF4F8EF7), strokeWidth: 2),
                    ),
                  );
                }
                if (snap.hasError || !snap.hasData) {
                  return const Text('❌ AI unavailable at this time.',
                      style: TextStyle(color: Color(0xFF8B93B0)));
                }
                return SingleChildScrollView(
                  child: Text(snap.data!,
                      style: const TextStyle(
                          color: Color(0xFFEEF2FF),
                          fontSize: 14,
                          height: 1.55)),
                );
              },
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252A3A),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('Close',
                    style: TextStyle(
                        color: Color(0xFFEEF2FF), fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenLoader extends StatelessWidget {
  const _FullScreenLoader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black38,
      child: const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF4F8EF7),
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}

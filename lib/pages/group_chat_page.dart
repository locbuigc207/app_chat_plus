// ignore_for_file: use_build_context_synchronously

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
    with
        WidgetsBindingObserver,
        ResourceManagerMixin,
        TickerProviderStateMixin {
  late String _currentUserId;
  int _limit = 30;
  final int _limitIncrement = 20;

  bool _isLoading = false;
  bool _isLoadingMedia = false;
  bool _isShowSticker = false;
  bool _showFeaturesMenu = false;
  bool _isRecording = false;
  bool _showScrollToBottom = false;
  bool _isLoadingSmartReply = false; // AI loading indicator

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

  late final AnimationController _appBarAnim;
  late final AnimationController _fabAnim;
  late final AnimationController _menuAnim;
  late final AnimationController _replyAnim;

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

  late MentionTextEditingController _chatInputController;
  late ScrollController _listScrollController;
  late FocusNode _focusNode;

  final Map<String, Timer> _scheduledMessages = {};
  final Map<String, String> _scheduledMessageContents = {};

  String get groupChatId => widget.group.id;

  // ── INIT ────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _chatInputController = MentionTextEditingController();
    _listScrollController = ScrollController();
    _focusNode = FocusNode();

    _appBarAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _fabAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _menuAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _replyAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));

    resourceManager
      ..addAnimationController(_appBarAnim)
      ..addAnimationController(_fabAnim)
      ..addAnimationController(_menuAnim)
      ..addAnimationController(_replyAnim);

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
    _startToxicityMonitor();
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
    resourceManager.addDelayedTimer(const Duration(milliseconds: 500), () {
      if (!resourceManager.isDisposed && mounted) {
        unawaited(_loadSmartReplies());
        final msgs = LocalDbService().getMessages(groupChatId);
        prefetchLinkPreviews(msgs.take(30).toList());
      }
    });
  }

  void _scrollListener() {
    if (resourceManager.isDisposed || !_listScrollController.hasClients) return;
    final pos = _listScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 && !pos.outOfRange) {
      final total = LocalDbService().getMessages(groupChatId).length;
      if (_limit < total && mounted) setState(() => _limit += _limitIncrement);
    }
    final show = pos.pixels > 400;
    if (show != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = show);
      if (show) {
        _fabAnim.forward();
      } else {
        _fabAnim.reverse();
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

  // ── AI FEATURE METHODS ──────────────────────────────────────────────────────

  void _showSummaryAnalysis() {
    final msgs = LocalDbService()
        .getMessages(groupChatId)
        .take(30)
        .map((d) {
          final content = d['content']?.toString() ?? '';
          if (content.startsWith('{"iv":') || content.startsWith('{'))
            return null;
          final sender = d['idFrom'] == _currentUserId
              ? 'Tôi'
              : (_memberNames[d['idFrom']] ?? 'Member');
          return '$sender: $content';
        })
        .whereType<String>()
        .toList()
        .reversed
        .toList();

    if (msgs.length < 3) {
      _showToast('Cần ít nhất 3 tin nhắn để phân tích');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => ConversationSummarySheet(messages: msgs),
    );
  }

  void _showToneRewriter() {
    final text = _chatInputController.text.trim();
    if (text.isEmpty) {
      _showToast('Nhập nội dung muốn viết lại vào ô chat trước');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => ToneRewriterSheet(
        originalMessage: text,
        onApply: (rewritten) {
          _chatInputController.text = rewritten;
          _focusNode.requestFocus();
        },
      ),
    );
  }

  void _openInsightsPage() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInsightsPage(
          conversationId: groupChatId,
          peerName: widget.group.groupName,
        ),
      ),
    );
  }

  void _openWeeklyRecap() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WeeklyRecapPage(userId: _currentUserId),
      ),
    );
  }

  void _startToxicityMonitor() {
    if (widget.group.adminId != _currentUserId) return;
    final sub = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .orderBy('timestamp', descending: true)
        .limit(5)
        .snapshots()
        .listen((snap) async {
      final newMsgs = snap.docChanges
          .where((c) => c.type == DocumentChangeType.added)
          .map((c) {
            final data = c.doc.data() as Map<String, dynamic>;
            final content = data['content'] as String? ?? '';
            final idFrom = data['idFrom'] as String? ?? '';
            if (idFrom == _currentUserId || idFrom == 'AI_BOT') return null;
            if (content.isEmpty ||
                content.startsWith('{"iv":') ||
                content.startsWith('{')) return null;
            return ToxicityInput(id: c.doc.id, text: content);
          })
          .whereType<ToxicityInput>()
          .toList();

      if (newMsgs.isEmpty) return;
      try {
        final results = await AIBackendService().analyzeToxicityBatch(newMsgs);
        for (final r in results) {
          if (!r.isToxic || r.confidence <= 0.72 || r.id == null) continue;
          await FirebaseFirestore.instance
              .collection(FirestoreConstants.pathMessageCollection)
              .doc(groupChatId)
              .collection(groupChatId)
              .doc(r.id!)
              .update({
            'isToxic': true,
            'toxicCategory': r.category,
            'toxicConfidence': r.confidence,
            'toxicFlaggedAt': FieldValue.serverTimestamp(),
          }).catchError((_) {});
        }
      } catch (e) {
        debugPrint('⚠️ ToxicMonitor: $e');
      }
    });
    resourceManager.addSubscription(sub);
  }

  // ── MEMBERS ─────────────────────────────────────────────────────────────────

  Future<void> _loadMemberNames() async {
    final names = <String, String>{};
    for (final uid in widget.group.memberIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(FirestoreConstants.pathUserCollection)
            .doc(uid)
            .get();
        if (doc.exists) {
          names[uid] =
              doc.get(FirestoreConstants.nickname) as String? ?? 'User';
          final photoUrl =
              doc.get(FirestoreConstants.photoUrl) as String? ?? '';
          if (photoUrl.isNotEmpty) _avatarUrlCache[uid] = photoUrl;
        }
      } catch (_) {}
    }
    if (mounted && !resourceManager.isDisposed)
      setState(() => _memberNames = names);
  }

  String _getSenderName(String senderId) {
    if (senderId == _currentUserId) return 'Bạn';
    return _memberNames[senderId] ?? 'User';
  }

  void _loadPinnedMessages() {
    if (resourceManager.isDisposed) return;
    final sub = _messageProvider.getPinnedMessages(groupChatId).listen((snap) {
      if (!mounted || resourceManager.isDisposed) return;
      setState(() => _pinnedMessages = snap.docs);
    });
    resourceManager.addSubscription(sub);
  }

  // ── INPUT HANDLERS ──────────────────────────────────────────────────────────

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
      if (mounted)
        setState(() {
          _showMentionSuggestions = suggestions.isNotEmpty;
          _memberSuggestions = suggestions;
        });
    } else {
      if (mounted) setState(() => _showMentionSuggestions = false);
    }
    if (text.isNotEmpty && _smartReplies.isNotEmpty && mounted)
      setState(() => _smartReplies = []);
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
        isTyping: text.isNotEmpty);
  }

  void _showAdaptiveUISuggestion() {
    if (resourceManager.isDisposed || !mounted) return;
    final p = context.read<ThemeProvider>().palette;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.accessibility_new, color: Colors.white),
        SizedBox(width: 8),
        Expanded(child: Text('Khó gõ? Bật Elder Mode để font lớn hơn!')),
      ]),
      duration: const Duration(seconds: 7),
      backgroundColor: p.surface,
      action: SnackBarAction(
          label: 'BẬT',
          textColor: p.warningColor,
          onPressed: () {
            try {
              context.read<AppModeProvider>().setMode(AppMode.elder);
            } catch (_) {}
          }),
    ));
  }

  // ── MARK READ ───────────────────────────────────────────────────────────────

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

  // ── SEND ────────────────────────────────────────────────────────────────────

  Future<void> _onSendMessage(String content, int type) async {
    if (resourceManager.isDisposed) return;
    if (content.trim().isEmpty && type == TypeMessage.text) {
      _showToast('Không có nội dung');
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
      _replyAnim.reverse();
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
          conversationId: groupChatId);
    } catch (_) {
      _showToast('Gửi thất bại');
    }
    if (_listScrollController.hasClients && !resourceManager.isDisposed) {
      _listScrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }

    if (!resourceManager.isDisposed) unawaited(_loadSmartReplies());
  }

  Future<void> _loadSmartReplies() async {
    if (resourceManager.isDisposed) return;
    final messages = LocalDbService().getMessages(groupChatId);
    if (messages.isEmpty) return;

    final last = messages.first;
    // Chỉ gợi ý khi tin nhắn cuối là từ người khác và là text
    if (last['idFrom'] == _currentUserId || last['type'] != TypeMessage.text)
      return;

    final content = last['content'] as String? ?? '';
    if (content.isEmpty || content.startsWith('{"iv":')) return;

    if (mounted && !resourceManager.isDisposed) {
      setState(() => _isLoadingSmartReply = true);
    }

    try {
      final history = messages
          .take(6)
          .map((m) => m['content']?.toString() ?? '')
          .where((c) => c.isNotEmpty && !c.startsWith('{"iv":'))
          .toList()
          .reversed
          .toList();

      final replies = await _smartReplyProvider.getAiSmartReplies(
        lastMessage: content,
        recentMessages: history,
        language: 'vi',
        replyIntent: 'helpful',
      );

      if (mounted && !resourceManager.isDisposed) {
        setState(() {
          _smartReplies = replies;
          _isLoadingSmartReply = false;
        });
      }
    } catch (e) {
      if (mounted && !resourceManager.isDisposed) {
        final fallback = _smartReplyProvider.getRuleBasedReplies(content);
        setState(() {
          _smartReplies = fallback;
          _isLoadingSmartReply = false;
        });
      }
    }
  }

  // ── MEDIA ───────────────────────────────────────────────────────────────────

  Future<void> _onPickImage() async {
    HapticFeedback.lightImpact();
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null)
        await _processAndSendMedia(File(file.path), isVideo: false);
    } catch (_) {
      _showToast('Không thể chọn ảnh');
    }
  }

  Future<void> _onPickVideo() async {
    HapticFeedback.lightImpact();
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file != null)
        await _processAndSendMedia(File(file.path), isVideo: true);
    } catch (_) {
      _showToast('Không thể chọn video');
    }
  }

  Future<void> _processAndSendMedia(File file, {required bool isVideo}) async {
    if (resourceManager.isDisposed) return;
    final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => SafeSendDialog(
            title: 'Gửi ${isVideo ? 'Video' : 'Ảnh'}',
            content: 'Gửi ${isVideo ? 'video' : 'ảnh'} này vào nhóm?',
            icon: isVideo ? Icons.videocam_rounded : Icons.image_rounded));
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
          });
      if (!mounted || resourceManager.isDisposed) return;
      if (success != false) {
        if (_listScrollController.hasClients) {
          _listScrollController.animateTo(0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
        _showToast(isVideo ? '🎬 Video đã gửi' : '📷 Ảnh đã gửi',
            isSuccess: true);
      }
    } catch (_) {
      _showToast('Gửi thất bại');
    } finally {
      if (mounted && !resourceManager.isDisposed)
        setState(() => _isLoadingMedia = false);
    }
  }

  Future<void> _onPickDocument() async {
    HapticFeedback.lightImpact();
    try {
      final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx']);
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
      _showToast('Lỗi chọn file');
    } finally {
      if (mounted) setState(() => _isLoadingMedia = false);
    }
  }

  // ── VOICE ───────────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_voiceProvider == null || resourceManager.isDisposed) {
      _showToast('Ghi âm không khả dụng');
      return;
    }
    if (!await _voiceProvider!.initRecorder()) {
      _showToast('Cần quyền microphone');
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
          final m = _recordingSeconds ~/ 60, s = _recordingSeconds % 60;
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
      if (mounted && !resourceManager.isDisposed)
        setState(() => _isRecording = false);
      _showToast('Ghi âm thất bại');
      return;
    }
    if (mounted && !resourceManager.isDisposed)
      setState(() {
        _isRecording = false;
        _isLoading = true;
      });
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    final uploadResult =
        await _voiceProvider!.uploadVoiceMessage(path, fileName);
    if (mounted && !resourceManager.isDisposed)
      setState(() => _isLoading = false);
    final url = uploadResult?.url;
    if (url != null && !resourceManager.isDisposed) {
      await _onSendMessage(url, 3);
      _showToast('🎤 Thoại đã gửi', isSuccess: true);
    } else {
      _showToast('Gửi thoại thất bại');
    }
  }

  Future<void> _cancelRecording() async {
    HapticFeedback.lightImpact();
    _recordingTimer?.cancel();
    await _voiceProvider?.cancelRecording();
    if (mounted && !resourceManager.isDisposed)
      setState(() => _isRecording = false);
  }

  // ── LOCATION ────────────────────────────────────────────────────────────────

  Future<void> _shareLocation() async {
    if (_locationProvider == null || resourceManager.isDisposed) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      if (!await _locationProvider!.requestLocationPermission()) {
        _showToast('Cần quyền vị trí');
        return;
      }
      final data = await _locationProvider!.getCurrentLocationWithDetails();
      if (data != null && !resourceManager.isDisposed) {
        await _onSendMessage(
            _locationProvider!.formatLocationMessage(data), TypeMessage.text);
        _showToast('📍 Đã chia sẻ vị trí', isSuccess: true);
      }
    } catch (_) {
      _showToast('Lỗi vị trí');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openLocationInMaps(String mapsUrl) async {
    try {
      final uri = Uri.parse(mapsUrl);
      if (await canLaunchUrl(uri))
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ── GEO LOCKED ──────────────────────────────────────────────────────────────

  Future<void> _sendGeoLockedMessage() async {
    if (resourceManager.isDisposed) return;
    if (mounted) setState(() => _showFeaturesMenu = false);
    _menuAnim.reverse();

    final result = await Navigator.push<GeoLockData>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const GeoLockPickerPage(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 340),
        fullscreenDialog: true,
      ),
    );

    if (result == null || resourceManager.isDisposed || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final content = jsonEncode(result.toJson());
      await _onSendMessage(content, TypeMessage.geoLocked);
      _showToast(
        result.hideLocation
            ? '🔐 Đã gửi tin nhắn ẩn địa điểm'
            : '📍 Đã gửi tin nhắn khóa địa điểm',
        isSuccess: true,
      );
    } catch (e) {
      debugPrint('❌ GeoLock send error: $e');
      _showToast('Không thể gửi tin nhắn');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── GAME CENTER ─────────────────────────────────────────────────────────────

  void _openGameCenter() {
    HapticFeedback.lightImpact();
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameCenterHubPage(
            groupId: groupChatId,
            groupName: widget.group.groupName,
            currentUserId: _currentUserId,
            currentUserName: _memberNames[_currentUserId] ?? 'Bạn',
            currentUserAvatar: _avatarUrlCache[_currentUserId] ?? '',
          ),
        ));
  }

  // ── AUTO-PILOT ──────────────────────────────────────────────────────────────

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
          final reply = await AIBackendService().generateAutoPilotReply(
              incomingMessage: content,
              myStyleContext: 'Gen Z: okela, đỉnh 😂🔥');
          if (reply != null && !resourceManager.isDisposed) {
            await _onSendMessage('[AI]: $reply', TypeMessage.text);
          }
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
      final replies = await AIBackendService().generateSwipeReplies(
          incomingMessage: lastMsg, contextMessages: '', replyStyle: 'genz');
      if (mounted)
        setState(() {
          _swipeReplies = replies;
          _isShowingSwipeCards = true;
        });
    } catch (_) {
      _showToast('AI không khả dụng');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAIContextAnalysis() {
    final messages = LocalDbService().getMessages(groupChatId);
    if (messages.isEmpty) {
      _showToast('Chưa đủ tin nhắn để phân tích');
      return;
    }
    final recent = messages.take(20).map((d) {
      final sender = d['idFrom'] == _currentUserId
          ? 'Tôi'
          : (_memberNames[d['idFrom']] ?? 'Member');
      return '$sender: ${d['content']}';
    }).toList();
    if (!mounted || resourceManager.isDisposed) return;
    final p = context.read<ThemeProvider>().palette;
    final primary = context.read<ThemeProvider>().primaryColor;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AIAnalysisDialog(
            messages: recent.reversed.toList(), palette: p, primary: primary));
  }

  // ── MESSAGE OPTIONS ─────────────────────────────────────────────────────────

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
                _showToast('📋 Đã sao chép', isSuccess: true);
              },
              onReply: () => _setReply(message, messageId),
              onReminder: () => _setReminder(message, messageId),
              onTranslate: () => _translateMessage(message.content),
            ));
  }

  Future<void> _editMessage(String messageId, String current) async {
    showDialog(
        context: context,
        builder: (_) => EditMessageDialog(
            originalContent: current,
            onSave: (newContent) async {
              final ok = await _messageProvider.editMessage(
                  groupChatId, messageId, newContent);
              if (ok) _showToast('Đã chỉnh sửa', isSuccess: true);
            }));
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirm = await _showConfirmDialog(
        title: 'Xoá tin nhắn',
        message: 'Xóa tin nhắn này cho tất cả?',
        confirmLabel: 'Xoá',
        isDangerous: true);
    if (confirm == true) {
      final ok = await _messageProvider.deleteMessage(groupChatId, messageId);
      if (ok) _showToast('Đã xoá', isSuccess: true);
    }
  }

  Future<void> _togglePin(String messageId, bool current) async {
    final ok = await _messageProvider.togglePinMessage(
        groupChatId, messageId, current);
    if (ok) _showToast(current ? 'Đã bỏ ghim' : '📌 Đã ghim', isSuccess: true);
  }

  void _setReply(MessageChat message, [String? messageId]) {
    HapticFeedback.selectionClick();
    if (resourceManager.isDisposed || !mounted) return;
    setState(() {
      _replyingTo = message;
      _replyingToMessageId = messageId;
      _replyingToSenderName = _getSenderName(message.idFrom);
    });
    _replyAnim.forward();
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
          message: message.content);
      _showToast('⏰ Đã đặt nhắc nhở', isSuccess: true);
    }
  }

  Future<DateTime?> _pickReminderTime() async {
    DateTime selected = DateTime.now().add(const Duration(hours: 1));
    final p = context.read<ThemeProvider>().palette;
    final primary = context.read<ThemeProvider>().primaryColor;
    return showDialog<DateTime>(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, ss) => _ThemedDialog(
                  title: 'Đặt Nhắc Nhở',
                  icon: Icons.alarm_rounded,
                  iconColor: primary,
                  palette: p,
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    _PickerTile(
                        label: 'Ngày',
                        value: DateFormat('dd/MM/yyyy').format(selected),
                        icon: Icons.calendar_today_rounded,
                        palette: p,
                        primary: primary,
                        onTap: () async {
                          final d = await showDatePicker(
                              context: ctx,
                              initialDate: selected,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)));
                          if (d != null)
                            ss(() => selected = DateTime(d.year, d.month, d.day,
                                selected.hour, selected.minute));
                        }),
                    const SizedBox(height: 8),
                    _PickerTile(
                        label: 'Giờ',
                        value: DateFormat('HH:mm').format(selected),
                        icon: Icons.access_time_rounded,
                        palette: p,
                        primary: primary,
                        onTap: () async {
                          final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.fromDateTime(selected));
                          if (t != null)
                            ss(() => selected = DateTime(
                                selected.year,
                                selected.month,
                                selected.day,
                                t.hour,
                                t.minute));
                        }),
                  ]),
                  actions: [
                    _ThemedDialogAction(
                        label: 'Huỷ',
                        palette: p,
                        primary: primary,
                        onTap: () => Navigator.pop(ctx)),
                    _ThemedDialogAction(
                        label: 'Đặt',
                        isPrimary: true,
                        palette: p,
                        primary: primary,
                        onTap: () => Navigator.pop(ctx, selected)),
                  ],
                )));
  }

  Future<void> _translateMessage(String content) async {
    showDialog(
        context: context,
        builder: (_) => TranslationDialog(originalMessage: content));
  }

  Future<void> _scheduleMessage() async {
    if (resourceManager.isDisposed) return;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ScheduleMessageDialog());
    if (result == null || resourceManager.isDisposed || !mounted) return;
    final text = result['message'] as String;
    final time = result['time'] as DateTime;
    final delay = time.difference(DateTime.now());
    if (delay.isNegative) {
      _showToast('Thời gian không hợp lệ');
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
    _showToast('📅 Lên lịch lúc ${DateFormat('HH:mm').format(time)}',
        isSuccess: true);
  }

  void _sendViewOnce() {
    showDialog(
        context: context,
        builder: (_) => SendViewOnceDialog(onSend: (content, type, _) async {
              await _viewOnceProvider.sendViewOnceMessage(
                  groupChatId: groupChatId,
                  currentUserId: _currentUserId,
                  peerId: groupChatId,
                  content: content,
                  type: type);
            }));
  }

  void _showReactionPicker(String messageId) {
    HapticFeedback.mediumImpact();
    showDialog(
        context: context,
        builder: (_) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: ReactionPicker(onEmojiSelected: (emoji) {
                _reactionProvider.toggleReaction(
                    groupChatId, messageId, _currentUserId, emoji);
                Navigator.pop(context);
              }),
            ));
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
    if (_showFeaturesMenu) {
      _menuAnim.forward();
      _focusNode.unfocus();
    } else {
      _menuAnim.reverse();
    }
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
                peerId: groupChatId)));
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
        title: 'Xoá lịch sử',
        message: 'Xóa toàn bộ tin nhắn trong nhóm?',
        confirmLabel: 'Xoá',
        isDangerous: true);
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
      _showToast('Đã xoá lịch sử', isSuccess: true);
    } catch (_) {
      _showToast('Xoá thất bại');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await _showConfirmDialog(
        title: 'Rời nhóm',
        message: 'Bạn có chắc muốn rời "${widget.group.groupName}"?',
        confirmLabel: 'Rời',
        isDangerous: true);
    if (confirm != true) return;
    try {
      final newMembers =
          widget.group.memberIds.where((id) => id != _currentUserId).toList();
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(groupChatId)
          .update({FirestoreConstants.memberIds: newMembers});
      await _onSendMessage(
          '${_memberNames[_currentUserId] ?? 'User'} đã rời nhóm',
          TypeMessage.text);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _showToast('Rời nhóm thất bại');
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
                memberNames: _memberNames)));
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'ai_assistant':
        _showAIContextAnalysis();
        break;
      case 'summarize':
        _showSummaryAnalysis();
        break;
      case 'tone_rewriter':
        _showToneRewriter();
        break;
      case 'insights':
        _openInsightsPage();
        break;
      case 'weekly':
        _openWeeklyRecap();
        break;
      case 'info':
        _openGroupInfo();
        break;
      case 'media':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => GroupMediaPage(
                    groupId: groupChatId, groupName: widget.group.groupName)));
        break;
      case 'search':
        _openSearch();
        break;
      case 'autodelete':
        showDialog(
            context: context,
            builder: (_) => AutoDeleteSettingsDialog(
                conversationId: groupChatId, provider: _autoDeleteProvider));
        break;
      case 'clear':
        _clearHistory();
        break;
      case 'leave':
        _leaveGroup();
        break;
      case 'theme':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ThemeSettingsPage()));
        break;
    }
  }

  void _showToast(String msg, {bool isSuccess = false}) {
    final p = context.read<ThemeProvider>().palette;
    Fluttertoast.showToast(
        msg: msg,
        backgroundColor: isSuccess ? p.successColor : p.surface,
        textColor: isSuccess ? Colors.white : p.textPrimary);
  }

  Future<bool?> _showConfirmDialog(
      {required String title,
      required String message,
      required String confirmLabel,
      bool isDangerous = false}) {
    final p = context.read<ThemeProvider>().palette;
    final primary = context.read<ThemeProvider>().primaryColor;
    return showDialog<bool>(
        context: context,
        builder: (_) => _ThemedDialog(
              title: title,
              icon: isDangerous
                  ? Icons.warning_rounded
                  : Icons.help_outline_rounded,
              iconColor: isDangerous ? p.dangerColor : primary,
              palette: p,
              content: Text(message,
                  style: TextStyle(
                      color: p.textSecondary, fontSize: 14.5, height: 1.5)),
              actions: [
                _ThemedDialogAction(
                    label: 'Huỷ',
                    palette: p,
                    primary: primary,
                    onTap: () => Navigator.pop(context, false)),
                _ThemedDialogAction(
                    label: confirmLabel,
                    isPrimary: !isDangerous,
                    isDanger: isDangerous,
                    palette: p,
                    primary: primary,
                    onTap: () => Navigator.pop(context, true)),
              ],
            ));
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: _buildAppBar(p, theme),
        body: SafeArea(
            child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _onBackPress();
          },
          child: Column(children: [
            ActiveGroupCallBanner(
                groupId: groupChatId,
                currentUserId: _currentUserId,
                memberIds: widget.group.memberIds,
                groupName: widget.group.groupName),
            if (_showMentionSuggestions) _buildMentionSuggestions(p, theme),
            Expanded(child: _buildChatContent(p, theme)),
          ]),
        )),
      ),
    );
  }

  // ── APP BAR ──────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(ThemePalette p, ThemeProvider theme) {
    return PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: FadeTransition(
          opacity: _appBarAnim,
          child: Container(
            decoration: BoxDecoration(color: p.appBarBackground, boxShadow: [
              BoxShadow(
                  color: p.shadow, blurRadius: 8, offset: const Offset(0, 2))
            ]),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: theme.primaryColor, size: 20),
                  onPressed: _onBackPress),
              title: InkWell(
                onTap: _openGroupInfo,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Hero(
                      tag: 'group_avatar_${widget.group.id}',
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [
                              theme.primaryLightColor,
                              theme.primaryColor
                            ]),
                            border: Border.all(
                                color:
                                    theme.primaryColor.withValues(alpha: 0.4),
                                width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                  color: theme.primaryColor
                                      .withValues(alpha: 0.25),
                                  blurRadius: 8)
                            ]),
                        child: ClipOval(
                            child: widget.group.groupPhotoUrl.isNotEmpty
                                ? Image.network(widget.group.groupPhotoUrl,
                                    fit: BoxFit.cover)
                                : Icon(Icons.group_rounded,
                                    size: 20, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(widget.group.groupName,
                              style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3),
                              overflow: TextOverflow.ellipsis),
                          Text('${widget.group.memberIds.length} thành viên',
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: 11.5)),
                        ])),
                  ]),
                ),
              ),
              actions: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Auto',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _isAutoPilotOn ? p.successColor : p.textHint)),
                  Transform.scale(
                      scale: .75,
                      child: Switch(
                        value: _isAutoPilotOn,
                        activeThumbColor: p.successColor,
                        activeTrackColor: p.successColor.withValues(alpha: .3),
                        inactiveThumbColor: p.textHint,
                        inactiveTrackColor: p.divider,
                        onChanged: (val) {
                          setState(() => _isAutoPilotOn = val);
                          _showToast(
                              val ? '🤖 Auto-pilot BẬT' : '✋ Auto-pilot TẮT');
                        },
                      )),
                ]),
                IconButton(
                  icon: Icon(Icons.sports_esports_rounded,
                      color: theme.primaryColor, size: 22),
                  tooltip: 'Game Center',
                  onPressed: _openGameCenter,
                ),
                GroupVideoCallButton(
                    groupId: groupChatId,
                    groupName: widget.group.groupName,
                    memberIds: widget.group.memberIds),
                // ── AI Sentiment Indicator ──────────────────────────────────
                SentimentIndicatorWidget(groupChatId: groupChatId),
                const SizedBox(width: 2),
                IconButton(
                    icon: Icon(Icons.search_rounded,
                        color: theme.primaryColor, size: 22),
                    onPressed: _openSearch),
                PopupMenuButton<String>(
                  onSelected: _onMenuSelected,
                  icon: Icon(Icons.more_vert_rounded,
                      color: p.textSecondary, size: 22),
                  color: p.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  itemBuilder: (_) => [
                    _menuItem('ai_assistant', Icons.auto_awesome,
                        'AI Assistant', const Color(0xFF8B5CF6), p),
                    _menuItem('info', Icons.info_outline_rounded,
                        'Thông tin nhóm', theme.primaryColor, p),
                    _menuItem('media', Icons.perm_media_rounded,
                        'Media & Files', const Color(0xFF43C6AC), p),
                    _menuItem('search', Icons.search_rounded, 'Tìm kiếm',
                        p.textSecondary, p),
                    const PopupMenuDivider(),
                    _menuItem('summarize', Icons.summarize_rounded,
                        'Tóm tắt & Phân tích', const Color(0xFF0EA5E9), p),
                    _menuItem('tone_rewriter', Icons.edit_note_rounded,
                        'Viết lại tông giọng', const Color(0xFF8B5CF6), p),
                    _menuItem('insights', Icons.psychology_rounded,
                        'AI Insights nhóm', const Color(0xFFF59E0B), p),
                    _menuItem('weekly', Icons.analytics_rounded, 'Weekly Recap',
                        const Color(0xFF10B981), p),
                    const PopupMenuDivider(),
                    _menuItem('autodelete', Icons.timer_rounded, 'Tự xoá',
                        p.warningColor, p),
                    _menuItem('clear', Icons.delete_sweep_rounded,
                        'Xoá lịch sử', p.warningColor, p),
                    _menuItem('theme', Icons.palette_rounded, 'Giao diện',
                        theme.primaryColor, p),
                    const PopupMenuDivider(),
                    _menuItem('leave', Icons.exit_to_app_rounded, 'Rời nhóm',
                        p.dangerColor, p,
                        isDestructive: true),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ));
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
          Color color, ThemePalette p,
          {bool isDestructive = false}) =>
      PopupMenuItem(
          value: value,
          child: Row(children: [
            Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 16)),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: isDestructive ? p.dangerColor : p.textPrimary,
                    fontSize: 14,
                    fontWeight:
                        isDestructive ? FontWeight.w700 : FontWeight.w500)),
          ]));

  // ── CHAT CONTENT ─────────────────────────────────────────────────────────────

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

  Widget _buildChatContent(ThemePalette p, ThemeProvider theme) {
    return ChatWallpaperWidget(
      wallpaper: theme.chatWallpaper,
      color: theme.primaryColor,
      opacity: theme.chatWallpaperOpacity,
      child: Stack(children: [
        Column(children: [
          const OfflineIndicator(),
          if (_pinnedMessages.isNotEmpty) _buildPinnedMessages(p, theme),
          _buildListMessage(p, theme),
          _buildTypingIndicator(p, theme),
          if (_isShowSticker) _buildStickers(p, theme),
          if (_showFeaturesMenu) _buildFeaturesMenu(p, theme),
          if (!_isShowingSwipeCards) _buildInput(p, theme),
        ]),
        if (_isLoading)
          Positioned.fill(
              child: Container(
                  color: Colors.black26,
                  child: Center(
                      child: CircularProgressIndicator(
                          color: theme.primaryColor, strokeWidth: 2.5)))),
        if (_isLoadingMedia)
          Positioned.fill(child: _buildMediaOverlay(p, theme)),
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
                  onCancel: () =>
                      setState(() => _isShowingSwipeCards = false))),
        Positioned(
          right: 12,
          bottom: _isShowingSwipeCards ? 200 : 90,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _fabAnim, curve: Curves.elasticOut),
            child: GestureDetector(
                onTap: () {
                  _listScrollController.animateTo(0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic);
                },
                child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: p.surface,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: p.shadow, blurRadius: 8)]),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: p.textSecondary, size: 22))),
          ),
        ),
      ]),
    );
  }

  Widget _buildMediaOverlay(ThemePalette p, ThemeProvider theme) => Container(
        color: Colors.black.withValues(alpha: .55),
        child: Center(
            child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: p.shadowStrong, blurRadius: 16)]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(
                color: theme.primaryColor, strokeWidth: 2.5),
            const SizedBox(height: 16),
            Text('Đang tải lên...',
                style: TextStyle(
                    color: p.textPrimary, fontWeight: FontWeight.w600)),
          ]),
        )),
      );

  Widget _buildPinnedMessages(ThemePalette p, ThemeProvider theme) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
          color: p.surface,
          border: Border(bottom: BorderSide(color: p.divider, width: .8))),
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
                color: p.pinnedBackground,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: theme.primaryColor.withValues(alpha: .25),
                    width: .8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.push_pin_rounded, size: 13, color: theme.primaryColor),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(message.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w500))),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildListMessage(ThemePalette p, ThemeProvider theme) {
    return Flexible(
        child: groupChatId.isNotEmpty
            ? ValueListenableBuilder(
                valueListenable: LocalDbService().messagesBox.listenable(),
                builder: (context, Box box, _) {
                  final all = LocalDbService().getMessages(groupChatId);
                  final display = all.take(_limit).toList();
                  final grouped = _processMessages(display);
                  prefetchLinkPreviews(display);

                  if (grouped.isEmpty) {
                    return Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              color: p.primaryContainer,
                              shape: BoxShape.circle),
                          child: Icon(Icons.chat_bubble_outline_rounded,
                              size: 40, color: theme.primaryColor)),
                      const SizedBox(height: 16),
                      Text('Chưa có tin nhắn',
                          style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('Hãy chào cả nhóm! 👋',
                          style:
                              TextStyle(color: p.textSecondary, fontSize: 14)),
                    ]));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    itemCount: grouped.length,
                    reverse: true,
                    controller: _listScrollController,
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    itemBuilder: (_, index) {
                      final item = grouped[index];
                      if (item is Map && item['isMediaGroup'] == true) {
                        return _buildMediaGroup(
                            List<Map<dynamic, dynamic>>.from(item['messages']),
                            p,
                            theme);
                      }
                      return _buildItemMessage(index,
                          item as Map<dynamic, dynamic>, display, p, theme);
                    },
                  );
                },
              )
            : Center(
                child: CircularProgressIndicator(
                    color: theme.primaryColor, strokeWidth: 2)));
  }

  Widget _buildMediaGroup(List<Map<dynamic, dynamic>> messages, ThemePalette p,
      ThemeProvider theme) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final first = messages.first;
    final isMe = first['idFrom'] == _currentUserId;
    final msgId = first['messageId'] as String? ?? '';
    final representative = MessageChat(
        idFrom: first['idFrom'] ?? '',
        idTo: first['idTo'] ?? '',
        timestamp: first['timestamp'] ?? '',
        content: first['content'] ?? '',
        type: first['type'] ?? 0,
        isRead: first['status'] == 'sent');

    return SwipeToReplyWrapper(
      isMe: isMe,
      onSwipe: () => _setReply(representative, msgId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe) _buildSenderName(first['idFrom'] as String? ?? '', p),
              Row(
                  mainAxisAlignment:
                      isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isMe)
                      _buildGroupAvatar(
                          first['idFrom'] as String? ?? '', theme),
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
                                  mainAxisSpacing: 2),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final m = messages[i];
                            final isVideo = m['type'] == TypeMessage.video;
                            final url = m['content'] ?? '';
                            final videoUrl =
                                isVideo ? url.split('|').first : '';
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
                                            builder: (_) => VideoPlayerPage(
                                                videoUrl: videoUrl)))
                                    : Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                FullPhotoPage(url: thumbUrl)));
                              },
                              child: Stack(fit: StackFit.expand, children: [
                                Image.network(thumbUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        Container(color: p.surfaceVariant)),
                                if (isVideo)
                                  const Center(
                                      child: Icon(
                                          Icons.play_circle_fill_rounded,
                                          color: Colors.white,
                                          size: 32)),
                              ]),
                            );
                          },
                        ),
                      ),
                    ),
                  ]),
              _buildTimestamp(first['timestamp'] ?? '', isMe, p, theme),
            ]),
      ),
    );
  }

  Widget _buildItemMessage(
      int index,
      Map<dynamic, dynamic> localData,
      List<Map<dynamic, dynamic>> fullList,
      ThemePalette p,
      ThemeProvider theme) {
    final isHighlighted = _pendingScrollToMessageId == localData['messageId'];
    final isPending = localData['status'] == 'pending';
    final msg = MessageChat(
        idFrom: localData['idFrom'] ?? '',
        idTo: localData['idTo'] ?? '',
        timestamp: localData['timestamp'] ?? '',
        content: localData['content'] ?? '',
        type: localData['type'] ?? 0,
        isRead: localData['status'] == 'sent');
    bool isLastInGroup = true;
    if (index > 0) isLastInGroup = fullList[index - 1]['idFrom'] != msg.idFrom;
    final isMe = msg.idFrom == _currentUserId;
    final messageId = localData['messageId'] ?? '';

    Widget? special = _buildSpecialMessage(
        msg, messageId, isMe, isLastInGroup, localData, p, theme);
    if (special != null) {
      return SwipeToReplyWrapper(
          isMe: isMe, onSwipe: () => _setReply(msg, messageId), child: special);
    }
    Widget bubble;
    if (msg.type == 3 && _voiceProvider != null) {
      bubble = _buildVoiceMessage(msg, isMe, p, theme);
    } else if (msg.type == TypeMessage.image) {
      bubble = _buildImageMessage(
          messageId, msg, isMe, isLastInGroup, isPending, p, theme);
    } else if (msg.type == TypeMessage.video) {
      bubble = _buildVideoMessage(
          messageId, msg, isMe, isLastInGroup, isPending, p, theme);
    } else if (msg.type == TypeMessage.sticker) {
      bubble = _buildStickerMessage(msg, isMe, messageId, p, theme);
    } else {
      bubble = _buildTextMessage(
          messageId: messageId,
          msg: msg,
          isMe: isMe,
          isLastInGroup: isLastInGroup,
          isPending: isPending,
          isHighlighted: isHighlighted,
          isScamWarning: localData['scamWarning'] ?? false,
          scamReason: localData['scamReason'] ?? '',
          hasReminder: localData['hasReminder'] ?? false,
          isToxic: localData['isToxic'] ?? false,
          toxicCategory: localData['toxicCategory'] ?? 'hate',
          p: p,
          theme: theme);
    }
    return SwipeToReplyWrapper(
        isMe: isMe, onSwipe: () => _setReply(msg, messageId), child: bubble);
  }

  Widget? _buildSpecialMessage(
      MessageChat msg,
      String messageId,
      bool isMe,
      bool isLastInGroup,
      Map<dynamic, dynamic> localData,
      ThemePalette p,
      ThemeProvider theme) {
    Widget wrapRow(Widget child) => Container(
          margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  isLastInGroup
                      ? _buildGroupAvatar(msg.idFrom, theme)
                      : const SizedBox(width: 36),
                child,
              ]),
        );

    if (localData['isViewOnce'] ?? false) {
      return wrapRow(ViewOnceMessageWidget(
          groupChatId: groupChatId,
          messageId: messageId,
          content: msg.content,
          type: msg.type,
          currentUserId: _currentUserId,
          isViewed: localData['isViewed'] ?? false,
          provider: _viewOnceProvider));
    }
    // ── GeoLocked ──────────────────────────────────────────────────────────
    if (msg.type == TypeMessage.geoLocked) {
      return Container(
        margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && isLastInGroup) _buildSenderName(msg.idFrom, p),
            Row(
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  isLastInGroup
                      ? _buildGroupAvatar(msg.idFrom, theme)
                      : const SizedBox(width: 36),
                GestureDetector(
                  onLongPress: () => _showMessageOptions(msg, messageId),
                  child:
                      GeoLockedMessageWidget(content: msg.content, isMe: isMe),
                ),
              ],
            ),
            _buildTimestamp(msg.timestamp, isMe, p, theme),
          ],
        ),
      );
    }
    if (msg.type == 7) {
      return wrapRow(TicTacToeMessageWidget(
          content: msg.content,
          messageId: messageId,
          groupId: groupChatId,
          currentUserId: _currentUserId));
    }
    if (msg.type == 8)
      return wrapRow(BlowMessageWidget(secretText: msg.content));
    if (msg.type == 9)
      return wrapRow(ShakeMessageWidget(secretText: msg.content));
    if (msg.type == TypeMessage.poll) {
      return wrapRow(PollMessageWidget(
          content: msg.content,
          messageId: messageId,
          currentUserId: _currentUserId,
          onVote: (mId, optionId) => _chatProvider.votePoll(
              groupChatId: groupChatId,
              messageId: messageId,
              optionId: optionId,
              userId: _currentUserId)));
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
                    ? _buildGroupAvatar(msg.idFrom, theme)
                    : const SizedBox(width: 36),
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
                      color: isMe ? p.outgoingBubble : p.incomingBubble,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: p.divider, width: .8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.insert_drive_file_rounded,
                            color: theme.primaryColor, size: 24)),
                    const SizedBox(width: 10),
                    Flexible(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(fileData['name'] as String? ?? 'File',
                              style: TextStyle(
                                  color: isMe ? Colors.white : p.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                              '${((fileData['size'] as num? ?? 0) / 1024).toStringAsFixed(1)} KB',
                              style: TextStyle(
                                  color:
                                      isMe ? Colors.white70 : p.textSecondary,
                                  fontSize: 12)),
                        ])),
                  ]),
                ),
              ),
            ]),
      );
    }
    return null;
  }

  Widget _buildSenderName(String senderId, ThemePalette p) {
    if (senderId == _currentUserId) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(left: 40, bottom: 3),
        child: Text(_getSenderName(senderId),
            style: TextStyle(
                color: p.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)));
  }

  Widget _buildGroupAvatar(String senderId, ThemeProvider theme) {
    if (senderId == _currentUserId) return const SizedBox.shrink();
    final photoUrl = _avatarUrlCache[senderId] ?? '';
    final name = _memberNames[senderId] ?? 'U';
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 2),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              colors: [theme.primaryLightColor, theme.primaryColor]),
          image: photoUrl.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(photoUrl), fit: BoxFit.cover)
              : null),
      child: photoUrl.isEmpty
          ? Center(
              child: Text(name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)))
          : null,
    );
  }

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
    bool isToxic = false,
    String toxicCategory = 'hate',
    required ThemePalette p,
    required ThemeProvider theme,
  }) {
    final location = _locationProvider?.parseLocationFromMessage(msg.content);
    final fs = theme.fontSizeMultiplier;
    final hasUrl = !msg.isDeleted &&
        msg.type == TypeMessage.text &&
        location == null &&
        UrlDetector.containsUrl(msg.content);

    Widget bubble = Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && isLastInGroup && theme.showAvatarsInChat)
              _buildSenderName(msg.idFrom, p),
            Row(
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMe)
                    (isLastInGroup && theme.showAvatarsInChat)
                        ? _buildGroupAvatar(msg.idFrom, theme)
                        : SizedBox(width: theme.showAvatarsInChat ? 36 : 0),
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
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width *
                              (hasUrl ? 0.84 : theme.bubbleMaxWidthFactor)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: theme.bubblePadding,
                        decoration: BoxDecoration(
                          gradient: isMe && theme.useGradientBubble
                              ? theme.outgoingBubbleGradient(p.isDark)
                              : null,
                          color: isMe && !theme.useGradientBubble
                              ? theme.primaryColor
                              : (!isMe ? p.incomingBubble : null),
                          borderRadius: isMe
                              ? theme.outgoingRadius(isLastInGroup)
                              : theme.incomingRadius(isLastInGroup),
                          border: isMe
                              ? null
                              : Border.all(color: p.divider, width: .5),
                          boxShadow: [
                            BoxShadow(
                                color: isMe
                                    ? theme.primaryColor.withValues(alpha: 0.2)
                                    : p.shadow,
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Scam Warning ───────────────────────────────────
                              if (!isMe && isScamWarning)
                                _GroupScamBanner(
                                    reason: scamReason, palette: p),
                              // ── Toxic Badge ────────────────────────────────────
                              if (!isMe && isToxic)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: ToxicMessageBadge(
                                      category: toxicCategory,
                                      showDetails: true),
                                ),
                              // ── Reminder Banner ────────────────────────────────
                              if (!isMe && hasReminder)
                                _GroupReminderBanner(
                                    msg: msg,
                                    messageId: messageId,
                                    onSet: _setReminder,
                                    palette: p,
                                    theme: theme),
                              // ── Content ────────────────────────────────────────
                              if (msg.isDeleted)
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.block_rounded,
                                      size: 14,
                                      color: isMe
                                          ? Colors.white38
                                          : p.textSecondary),
                                  const SizedBox(width: 6),
                                  Text('Tin nhắn đã xóa',
                                      style: TextStyle(
                                          color: isMe
                                              ? Colors.white38
                                              : p.textSecondary,
                                          fontStyle: FontStyle.italic,
                                          fontSize: 14 * fs)),
                                ])
                              else if (location != null)
                                _GroupLocationContent(
                                    location: location,
                                    isMe: isMe,
                                    palette: p,
                                    theme: theme,
                                    onOpen: () =>
                                        _openLocationInMaps(location.mapsUrl))
                              else if (hasUrl)
                                ChatMessageWithLinkPreview(
                                  content: msg.content,
                                  isMe: isMe,
                                  textColor:
                                      isMe ? Colors.white : p.incomingText,
                                  fontSize: 15 * fs,
                                  primaryColor: theme.primaryColor,
                                  showPreview: true,
                                )
                              else
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(msg.content,
                                          style: TextStyle(
                                              color: isMe
                                                  ? Colors.white
                                                  : p.incomingText,
                                              fontSize: 15 * fs,
                                              height: 1.35)),
                                      if (isMe)
                                        Align(
                                            alignment: Alignment.centerRight,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 3),
                                              child: Icon(
                                                  isPending
                                                      ? Icons
                                                          .access_time_rounded
                                                      : msg.isRead
                                                          ? Icons
                                                              .done_all_rounded
                                                          : Icons.done_rounded,
                                                  size: 13,
                                                  color: msg.isRead
                                                      ? Colors.white
                                                      : Colors.white38),
                                            )),
                                    ]),
                            ]),
                      ),
                    ),
                  )),
                ]),
            if (!isMe && msg.type == TypeMessage.text) ...[
              if (_scamResults[messageId] != null &&
                  _scamResults[messageId] != 'SAFE')
                Padding(
                    padding:
                        EdgeInsets.only(left: theme.showAvatarsInChat ? 42 : 4),
                    child: ScamWarningWidget(status: _scamResults[messageId]!)),
              if (_scamResults[messageId] == null && !isScamWarning)
                Padding(
                  padding: EdgeInsets.only(
                      left: theme.showAvatarsInChat ? 42 : 4, top: 3),
                  child: GestureDetector(
                    onTap: () async {
                      _showToast('🛡 Đang quét...');
                      final status =
                          await AIBackendService().checkScam(msg.content);
                      if (mounted)
                        setState(() => _scamResults[messageId] =
                            status.name.toUpperCase());
                      if (status.name.toUpperCase() == 'SAFE')
                        _showToast('✅ Tin nhắn an toàn', isSuccess: true);
                    },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.shield_outlined,
                          size: 13, color: p.successColor),
                      const SizedBox(width: 4),
                      Text('Quét AI',
                          style:
                              TextStyle(fontSize: 11.5, color: p.successColor)),
                    ]),
                  ),
                ),
            ],
            _buildReactions(messageId, isMe, p, theme),
            _buildTimestamp(msg.timestamp, isMe, p, theme),
          ]),
    );

    if (!isHighlighted) return bubble;
    return AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16)),
        child: bubble);
  }

  Widget _buildImageMessage(String messageId, MessageChat msg, bool isMe,
      bool isLastInGroup, bool isPending, ThemePalette p, ThemeProvider theme) {
    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && isLastInGroup && theme.showAvatarsInChat)
              _buildSenderName(msg.idFrom, p),
            Row(
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMe)
                    (isLastInGroup && theme.showAvatarsInChat)
                        ? _buildGroupAvatar(msg.idFrom, theme)
                        : const SizedBox(width: 36),
                  GestureDetector(
                    onTap: () {
                      if (!isPending) {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    FullPhotoPage(url: msg.content)));
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
                        child: isPending
                            ? Container(
                                color: p.surfaceVariant,
                                child: Center(
                                    child: CircularProgressIndicator(
                                        color: theme.primaryColor,
                                        strokeWidth: 2)))
                            : Image.network(msg.content,
                                fit: BoxFit.cover,
                                loadingBuilder: (_, child, prog) => prog == null
                                    ? child
                                    : Container(
                                        color: p.surfaceVariant,
                                        child: Center(
                                            child: CircularProgressIndicator(
                                                color: theme.primaryColor,
                                                strokeWidth: 2))),
                                errorBuilder: (_, __, ___) => Container(
                                    color: p.surfaceVariant,
                                    child: Icon(Icons.broken_image_rounded,
                                        color: p.textHint))),
                      ),
                    ),
                  ),
                ]),
            _buildReactions(messageId, isMe, p, theme),
            _buildTimestamp(msg.timestamp, isMe, p, theme),
          ]),
    );
  }

  Widget _buildVideoMessage(String messageId, MessageChat msg, bool isMe,
      bool isLastInGroup, bool isPending, ThemePalette p, ThemeProvider theme) {
    final parts = msg.content.split('|');
    final videoUrl = parts.isNotEmpty ? parts[0] : '';
    final thumbUrl = parts.length > 1 ? parts[1] : '';
    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && isLastInGroup && theme.showAvatarsInChat)
              _buildSenderName(msg.idFrom, p),
            Row(
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMe)
                    (isLastInGroup && theme.showAvatarsInChat)
                        ? _buildGroupAvatar(msg.idFrom, theme)
                        : const SizedBox(width: 36),
                  GestureDetector(
                    onTap: () {
                      if (!isPending)
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    VideoPlayerPage(videoUrl: videoUrl)));
                    },
                    onLongPress: () => _showMessageOptions(msg, messageId),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * .62,
                        height: 195,
                        child: Stack(fit: StackFit.expand, children: [
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
                                Colors.black.withValues(alpha: .6)
                              ]))),
                          if (isPending)
                            const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                          else
                            Center(
                                child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: Colors.black45,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white54, width: 1.5)),
                                    child: const Icon(Icons.play_arrow_rounded,
                                        color: Colors.white, size: 32))),
                          Positioned(
                              bottom: 8,
                              right: 10,
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(6)),
                                  child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.videocam_rounded,
                                            size: 11, color: Colors.white),
                                        SizedBox(width: 3),
                                        Text('Video',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white)),
                                      ]))),
                        ]),
                      ),
                    ),
                  ),
                ]),
            _buildReactions(messageId, isMe, p, theme),
            _buildTimestamp(msg.timestamp, isMe, p, theme),
          ]),
    );
  }

  Widget _buildVoiceMessage(
      MessageChat msg, bool isMe, ThemePalette p, ThemeProvider theme) {
    return Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe) _buildSenderName(msg.idFrom, p),
          Row(
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) _buildGroupAvatar(msg.idFrom, theme),
                const SizedBox(width: 4),
                VoiceMessageWidget(
                    voiceUrl: msg.content,
                    isMyMessage: isMe,
                    voiceProvider: _voiceProvider!),
              ]),
          _buildTimestamp(msg.timestamp, isMe, p, theme),
        ]);
  }

  Widget _buildStickerMessage(MessageChat msg, bool isMe, String messageId,
      ThemePalette p, ThemeProvider theme) {
    return Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe) _buildSenderName(msg.idFrom, p),
          Row(
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isMe) _buildGroupAvatar(msg.idFrom, theme),
                const SizedBox(width: 4),
                GestureDetector(
                    onLongPress: () => _showMessageOptions(msg, messageId),
                    child: Image.asset('images/${msg.content}.gif',
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            width: 90,
                            height: 90,
                            color: p.surfaceVariant,
                            child:
                                Icon(Icons.error_rounded, color: p.textHint)))),
              ]),
        ]);
  }

  Widget _buildReactions(
      String messageId, bool isMe, ThemePalette p, ThemeProvider theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: _reactionProvider.getReactions(groupChatId, messageId),
      builder: (_, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty)
          return const SizedBox.shrink();
        final reactions = <String, int>{};
        final userReactions = <String, bool>{};
        for (final doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final emoji = d['emoji'] as String, uid = d['userId'] as String;
          reactions[emoji] = (reactions[emoji] ?? 0) + 1;
          if (uid == _currentUserId) userReactions[emoji] = true;
        }
        return Padding(
            padding: EdgeInsets.only(
                left: isMe ? 0 : (theme.showAvatarsInChat ? 42 : 4), top: 2),
            child: MessageReactionsDisplay(
                reactions: reactions,
                currentUserId: _currentUserId,
                userReactions: userReactions,
                onReactionTap: (emoji) => _reactionProvider.toggleReaction(
                    groupChatId, messageId, _currentUserId, emoji)));
      },
    );
  }

  Widget _buildTimestamp(
      String ts, bool isMe, ThemePalette p, ThemeProvider theme) {
    String label = '';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
      final now = DateTime.now();
      label = now.difference(dt).inDays == 0
          ? DateFormat('HH:mm').format(dt)
          : DateFormat('dd/MM HH:mm').format(dt);
    } catch (_) {}
    return Padding(
        padding: EdgeInsets.only(
            left: isMe ? 0 : (theme.showAvatarsInChat ? 44 : 4),
            right: isMe ? 4 : 0,
            bottom: 2),
        child:
            Text(label, style: TextStyle(fontSize: 10.5, color: p.textHint)));
  }

  Widget _buildTypingIndicator(ThemePalette p, ThemeProvider theme) {
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
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TypingIndicator(
                userName: typing.length == 1
                    ? typing.first
                    : '${typing.length} người'));
      },
    );
  }

  Widget _buildMentionSuggestions(ThemePalette p, ThemeProvider theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.divider, width: .8),
          boxShadow: [
            BoxShadow(
                color: p.shadowStrong,
                blurRadius: 16,
                offset: const Offset(0, 4))
          ]),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _memberSuggestions.length,
        itemBuilder: (_, i) {
          final m = _memberSuggestions[i];
          final userId = m['userId'] as String? ?? '';
          final name = m['name'] as String? ?? '';
          if (userId.isEmpty || name.isEmpty) return const SizedBox.shrink();
          return ListTile(
              dense: true,
              leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                  child: Text(name.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12))),
              title: Text('@$name',
                  style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              onTap: () => _insertMention(userId, name));
        },
      ),
    );
  }

  Widget _buildStickers(ThemePalette p, ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.divider, width: .8))),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
              3,
              (row) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                      3,
                      (col) => TextButton(
                          onPressed: () => _onSendMessage(
                              'mimi${row * 3 + col + 1}', TypeMessage.sticker),
                          child: Image.asset(
                              'images/mimi${row * 3 + col + 1}.gif',
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover)))))),
    );
  }

  Widget _buildFeaturesMenu(ThemePalette p, ThemeProvider theme) {
    final items = [
      _GFeatureItem(
          Icons.image_rounded, 'Ảnh', _onPickImage, theme.primaryColor),
      _GFeatureItem(Icons.videocam_rounded, 'Video', _onPickVideo,
          const Color(0xFFFF6B9D)),
      _GFeatureItem(Icons.add_location_alt_rounded, 'GeoLock',
          _sendGeoLockedMessage, p.dangerColor),
      _GFeatureItem(Icons.games_rounded, 'Caro', () {
        setState(() => _showFeaturesMenu = false);
        _onSendMessage(
            jsonEncode({
              'board': List.filled(9, ''),
              'turn': '',
              'winner': '',
              'playerX': '',
              'playerO': ''
            }),
            7);
      }, const Color(0xFF8B5CF6)),
      _GFeatureItem(Icons.air_rounded, 'Blow', () {
        setState(() => _showFeaturesMenu = false);
        _onSendMessage('Bí mật 🤫', 8);
      }, const Color(0xFF43C6AC)),
      _GFeatureItem(Icons.vibration_rounded, 'Shake', () {
        setState(() => _showFeaturesMenu = false);
        _onSendMessage('Surprise! 🎁', 9);
      }, p.warningColor),
      _GFeatureItem(Icons.attach_file_rounded, 'File', () {
        setState(() => _showFeaturesMenu = false);
        _onPickDocument();
      }, const Color(0xFFFFB84D)),
      _GFeatureItem(Icons.poll_rounded, 'Poll', () {
        setState(() => _showFeaturesMenu = false);
        showDialog(
            context: context,
            builder: (_) => CreatePollDialog(onCreate: (question, options,
                    {bool isMultipleChoice = false,
                    bool isAnonymous = false,
                    DateTime? expiresAt}) {
                  final opts = options
                      .asMap()
                      .entries
                      .map((e) => {
                            'id': e.key.toString(),
                            'text': e.value,
                            'votes': <String>[]
                          })
                      .toList();
                  _onSendMessage(
                      jsonEncode({
                        'question': question,
                        'options': opts,
                        'isMultipleChoice': isMultipleChoice,
                        'isAnonymous': isAnonymous,
                        if (expiresAt != null)
                          'expiresAt': expiresAt.toIso8601String()
                      }),
                      TypeMessage.poll);
                }));
      }, const Color(0xFF4FD1C5)),
      _GFeatureItem(Icons.visibility_off_rounded, 'Once', () {
        setState(() => _showFeaturesMenu = false);
        _sendViewOnce();
      }, const Color(0xFF9B59B6)),
      _GFeatureItem(Icons.timer_rounded, 'Auto-del', () {
        setState(() => _showFeaturesMenu = false);
        showDialog(
            context: context,
            builder: (_) => AutoDeleteSettingsDialog(
                conversationId: groupChatId, provider: _autoDeleteProvider));
      }, p.textSecondary),
      _GFeatureItem(Icons.location_on_rounded, 'Vị trí', () {
        setState(() => _showFeaturesMenu = false);
        _shareLocation();
      }, p.dangerColor),
      _GFeatureItem(Icons.schedule_send_rounded, 'Lên lịch', () {
        setState(() => _showFeaturesMenu = false);
        _scheduleMessage();
      }, const Color(0xFF43C6AC)),
      _GFeatureItem(Icons.sports_esports_rounded, 'Game', () {
        setState(() => _showFeaturesMenu = false);
        _openGameCenter();
      }, const Color(0xFF9C27B0)),
    ];

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
              CurvedAnimation(parent: _menuAnim, curve: Curves.easeOutCubic)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 110),
        decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.divider, width: .8)),
            boxShadow: [BoxShadow(color: p.shadow, blurRadius: 8)]),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
              children: items
                  .map((item) => InkWell(
                        onTap: resourceManager.isDisposed ? null : item.onTap,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 68,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                    color: item.color.withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color:
                                            item.color.withValues(alpha: .25),
                                        width: .8)),
                                child: Icon(item.icon,
                                    color: item.color, size: 22)),
                            const SizedBox(height: 4),
                            Text(item.label,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: p.textSecondary,
                                    fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center),
                          ]),
                        ),
                      ))
                  .toList()),
        ),
      ),
    );
  }

  // ── INPUT ────────────────────────────────────────────────────────────────────

  Widget _buildInput(ThemePalette p, ThemeProvider theme) {
    final fs = theme.fontSizeMultiplier;
    return Container(
      margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 8,
          left: 12,
          right: 12,
          top: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_smartReplies.isNotEmpty || _isLoadingSmartReply)
          Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildSmartReplyBar(p, theme)),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: _replyingTo == null
              ? const SizedBox.shrink()
              : GestureDetector(
                  onTap: () {
                    if (_replyingToMessageId != null)
                      _scrollToMessage(_replyingToMessageId!);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border(
                            left: BorderSide(
                                color: theme.primaryColor, width: 3)),
                        boxShadow: [BoxShadow(color: p.shadow, blurRadius: 6)]),
                    child: Row(children: [
                      Container(
                          width: 3,
                          height: 34,
                          decoration: BoxDecoration(
                              color: theme.primaryColor,
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Trả lời $_replyingToSenderName',
                                style: TextStyle(
                                    color: theme.primaryColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                            Text(_replyingTo!.content,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5, color: p.textSecondary)),
                          ])),
                      GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _replyingTo = null;
                              _replyingToSenderName = null;
                              _replyingToMessageId = null;
                            });
                            _replyAnim.reverse();
                          },
                          child: Icon(Icons.close_rounded,
                              size: 18, color: p.textHint)),
                    ]),
                  ),
                ),
        ),
        if (_isRecording)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.dangerColor.withValues(alpha: .4))),
            child: Row(children: [
              _RecDot(color: p.dangerColor),
              const SizedBox(width: 8),
              Text('Đang ghi âm  $_recordingDuration',
                  style: TextStyle(
                      color: p.dangerColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
              const Spacer(),
              GestureDetector(
                  onTap: _cancelRecording,
                  child: Icon(Icons.delete_rounded,
                      color: p.dangerColor, size: 22)),
              const SizedBox(width: 12),
              GestureDetector(
                  onTap: _stopRecording,
                  child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: theme.primaryColor, shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 16))),
            ]),
          ),
        Container(
          decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: p.inputBorder, width: .6),
              boxShadow: [
                BoxShadow(
                    color: p.shadow, blurRadius: 12, offset: const Offset(0, 3))
              ]),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            GestureDetector(
                onTap: _toggleFeaturesMenu,
                child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: AnimatedRotation(
                        turns: _showFeaturesMenu ? 0.125 : 0,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        child: Icon(
                            _showFeaturesMenu
                                ? Icons.close_rounded
                                : Icons.add_rounded,
                            color: _showFeaturesMenu
                                ? p.dangerColor
                                : theme.primaryColor,
                            size: 26)))),
            if (!_showFeaturesMenu)
              GestureDetector(
                  onTap: _onPickImage,
                  child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Icon(Icons.image_rounded,
                          color: p.textHint, size: 24))),
            GestureDetector(
                onTap: _getSticker,
                child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Icon(Icons.sentiment_satisfied_alt_rounded,
                        color: _isShowSticker ? theme.primaryColor : p.textHint,
                        size: 24))),
            Expanded(
                child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding:
                        const EdgeInsets.only(right: 8, top: 12, bottom: 12),
                    child: TextField(
                      controller: _chatInputController,
                      focusNode: _focusNode,
                      style: TextStyle(fontSize: 15 * fs, color: p.textPrimary),
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      onTapOutside: (_) => Utilities.closeKeyboard(),
                      decoration: InputDecoration.collapsed(
                          hintText: 'Nhắn tin... (@đề cập)',
                          hintStyle:
                              TextStyle(color: p.textHint, fontSize: 15 * fs)),
                      onChanged: _handleTextChange,
                    ))),
            GestureDetector(
                onTap: _triggerZeroTypeSwipe,
                child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Icon(Icons.auto_awesome_rounded,
                        color: _isAutoPilotOn
                            ? const Color(0xFF8B5CF6)
                            : p.textHint,
                        size: 24))),
            Padding(
              padding: const EdgeInsets.all(6),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _chatInputController,
                builder: (_, val, __) {
                  final hasText = val.text.trim().isNotEmpty;
                  return GestureDetector(
                    onTap: () {
                      if (hasText) {
                        _onSendMessage(
                            _chatInputController.text, TypeMessage.text);
                      } else {
                        _startRecording();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: hasText
                            ? theme.outgoingBubbleGradient(p.isDark)
                            : null,
                        color: hasText ? null : p.surfaceVariant,
                        shape: BoxShape.circle,
                        boxShadow: hasText
                            ? [
                                BoxShadow(
                                    color: theme.primaryColor
                                        .withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3))
                              ]
                            : null,
                      ),
                      child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                              hasText ? Icons.send_rounded : Icons.mic_rounded,
                              key: ValueKey(hasText),
                              color: hasText ? Colors.white : p.textHint,
                              size: 20)),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSmartReplyBar(ThemePalette p, ThemeProvider theme) {
    return SizedBox(
      height: 50,
      child: _isLoadingSmartReply
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: theme.primaryColor)),
                const SizedBox(width: 10),
                Text('AI đang gợi ý...',
                    style: TextStyle(fontSize: 12, color: p.textHint)),
              ]),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SmartReplyWidget(
                  replies: _smartReplies,
                  onReplySelected: (reply) {
                    if (!resourceManager.isDisposed) {
                      _chatInputController.text = reply;
                      setState(() => _smartReplies = []);
                      _focusNode.requestFocus();
                    }
                  }),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _GroupScamBanner extends StatelessWidget {
  const _GroupScamBanner({required this.reason, required this.palette});
  final String reason;
  final ThemePalette palette;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: palette.dangerColor.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: palette.dangerColor.withValues(alpha: .4))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded,
              color: palette.dangerColor, size: 15),
          const SizedBox(width: 6),
          Flexible(
              child: Text('AI: $reason',
                  style: TextStyle(
                      color: palette.dangerColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
        ]),
      );
}

class _GroupReminderBanner extends StatelessWidget {
  const _GroupReminderBanner({
    required this.msg,
    required this.messageId,
    required this.onSet,
    required this.palette,
    required this.theme,
  });
  final MessageChat msg;
  final String messageId;
  final Future<void> Function(MessageChat, String) onSet;
  final ThemePalette palette;
  final ThemeProvider theme;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: palette.infoColor.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.infoColor.withValues(alpha: .3))),
        child: Row(children: [
          Icon(Icons.alarm_add_rounded, color: palette.infoColor, size: 15),
          const SizedBox(width: 6),
          Expanded(
              child: Text('AI: Phát hiện việc cần nhắc nhở',
                  style: TextStyle(color: palette.infoColor, fontSize: 12))),
          GestureDetector(
              onTap: () => onSet(msg, messageId),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: palette.infoColor.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('Đặt',
                      style: TextStyle(
                          color: palette.infoColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)))),
        ]),
      );
}

class _GroupLocationContent extends StatelessWidget {
  const _GroupLocationContent({
    required this.location,
    required this.isMe,
    required this.palette,
    required this.theme,
    required this.onOpen,
  });
  final dynamic location;
  final bool isMe;
  final ThemePalette palette;
  final ThemeProvider theme;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_on_rounded,
              color: isMe ? Colors.white : palette.dangerColor, size: 18),
          const SizedBox(width: 5),
          Text('Vị trí',
              style: TextStyle(
                  color: isMe ? Colors.white : palette.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ]),
        const SizedBox(height: 4),
        Text(location.address,
            style: TextStyle(
                color: isMe ? Colors.white70 : palette.textSecondary,
                fontSize: 12.5)),
        const SizedBox(height: 8),
        GestureDetector(
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white.withValues(alpha: .15)
                      : palette.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isMe
                          ? Colors.white30
                          : theme.primaryColor.withValues(alpha: .3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.map_rounded,
                    size: 13, color: isMe ? Colors.white : theme.primaryColor),
                const SizedBox(width: 5),
                Text('Xem trên Maps',
                    style: TextStyle(
                        fontSize: 12,
                        color: isMe ? Colors.white : theme.primaryColor,
                        fontWeight: FontWeight.w600)),
              ]),
            )),
      ]);
}

class _ThemedDialog extends StatelessWidget {
  const _ThemedDialog({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.content,
    required this.actions,
    required this.palette,
  });
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget content;
  final List<Widget> actions;
  final ThemePalette palette;
  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: palette.surface,
        child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, color: iconColor, size: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(title,
                            style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 18),
                  content,
                  const SizedBox(height: 20),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions
                          .map((a) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: a))
                          .toList()),
                ])),
      );
}

class _ThemedDialogAction extends StatelessWidget {
  const _ThemedDialogAction({
    required this.label,
    required this.onTap,
    required this.palette,
    required this.primary,
    this.isPrimary = false,
    this.isDanger = false,
  });
  final String label;
  final VoidCallback onTap;
  final ThemePalette palette;
  final Color primary;
  final bool isPrimary, isDanger;
  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
              backgroundColor: primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
          child: Text(label));
    }
    if (isDanger) {
      return TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(foregroundColor: palette.dangerColor),
          child: Text(label));
    }
    return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
        child: Text(label));
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    required this.palette,
    required this.primary,
  });
  final String label, value;
  final IconData icon;
  final VoidCallback onTap;
  final ThemePalette palette;
  final Color primary;
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              color: palette.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.divider)),
          child: Row(children: [
            Icon(icon, color: primary, size: 20),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: palette.textHint)),
              Text(value,
                  style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
            ]),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: palette.textHint, size: 20),
          ])));
}

class _RecDot extends StatefulWidget {
  const _RecDot({required this.color});
  final Color color;
  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: _ctrl,
      child: Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: widget.color, shape: BoxShape.circle)));
}

class _AIAnalysisDialog extends StatelessWidget {
  const _AIAnalysisDialog({
    required this.messages,
    required this.palette,
    required this.primary,
  });
  final List<String> messages;
  final ThemePalette palette;
  final Color primary;
  @override
  Widget build(BuildContext context) => _ThemedDialog(
        title: 'AI Phân Tích',
        icon: Icons.auto_awesome,
        iconColor: const Color(0xFF8B5CF6),
        palette: palette,
        content: FutureBuilder<String?>(
          future: AIBackendService()
              .analyzeChatContext(messages, 'work', 'extract_tasks'),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                  height: 80,
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF8B5CF6), strokeWidth: 2)));
            }
            if (snap.hasError || !snap.hasData) {
              return Text('AI không khả dụng lúc này.',
                  style: TextStyle(color: palette.textSecondary));
            }
            return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                    child: Text(snap.data!,
                        style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                            height: 1.55))));
          },
        ),
        actions: [
          _ThemedDialogAction(
              label: 'Đóng',
              palette: palette,
              primary: primary,
              onTap: () => Navigator.pop(context))
        ],
      );
}

class _GFeatureItem {
  const _GFeatureItem(this.icon, this.label, this.onTap, this.color);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
}

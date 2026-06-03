// ignore_for_file: avoid_print, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatPageArguments {
  final String peerId;
  final String peerAvatar;
  final String peerNickname;

  const ChatPageArguments({
    required this.peerId,
    required this.peerAvatar,
    required this.peerNickname,
  });
}

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
    with
        WidgetsBindingObserver,
        ResourceManagerMixin,
        TickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────────────────────
  late final String _currentUserId;
  String _groupChatId = '';

  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  late final FocusNode _focusNode;

  late final AnimationController _sendBtnAnim;
  late final AnimationController _fabAnim;
  late final AnimationController _menuAnim;
  late final AnimationController _replyAnim;
  late final AnimationController _appBarAnim;
  late final AnimationController _msgEntryAnim;

  static const _miniChatChannel = MethodChannel('mini_chat_channel');
  static const _bubbleChannel = MethodChannel('bubble_chat_channel');

  // ── Providers ────────────────────────────────────────────────────────────
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
  UserPresenceProvider? _presenceProvider;
  UnifiedBubbleService? _bubbleService;
  VoiceMessageProvider? _voiceProvider;
  LocationProvider? _locationProvider;

  // ── UI State ─────────────────────────────────────────────────────────────
  int _limit = 30;
  final int _limitIncrement = 20;

  bool _isLoading = false;
  bool _isShowSticker = false;
  bool _isLoadingMedia = false;
  bool _isTyping = false;
  bool _showMenu = false;
  bool _isRecording = false;
  bool _showScrollToBottom = false;
  bool _lockChecked = false;
  bool _isProcessingMsg = false;
  bool _isLoadingSmartReply = false;

  String _recDuration = '0:00';
  int _recSeconds = 0;
  Timer? _recTimer;

  List<DocumentSnapshot> _pinned = [];
  List<SmartReply> _smartReplies = [];
  MessageChat? _replyingTo;
  String? _pendingScrollId;

  final Set<String> _processedIds = {};
  final Map<String, Timer> _scheduled = {};
  final Map<String, String> _scheduledContent = {};
  final Map<String, dynamic> _scamResults = {};
  final Set<String> _expandedPreviews = {};
  final ImagePicker _picker = ImagePicker();

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _focusNode = FocusNode();

    _sendBtnAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _fabAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _menuAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _replyAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _appBarAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();
    _msgEntryAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));

    resourceManager
      ..addAnimationController(_sendBtnAnim)
      ..addAnimationController(_fabAnim)
      ..addAnimationController(_menuAnim)
      ..addAnimationController(_replyAnim)
      ..addAnimationController(_appBarAnim)
      ..addAnimationController(_msgEntryAnim)
      ..addController(_inputController)
      ..addScrollController(_scrollController)
      ..addFocusNode(_focusNode);

    WidgetsBinding.instance.addObserver(this);

    _focusNode.addListener(_onFocusChange);
    _scrollController.addListener(_onScroll);
    _inputController.addListener(_onInputChanged);

    resourceManager
      ..addDisposer(() => _focusNode.removeListener(_onFocusChange))
      ..addDisposer(() => _scrollController.removeListener(_onScroll))
      ..addDisposer(() => _inputController.removeListener(_onInputChanged))
      ..addDisposer(() => WidgetsBinding.instance.removeObserver(this));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!resourceManager.isDisposed && mounted) {
        _initProviders(context);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (resourceManager.isDisposed || _currentUserId.isEmpty) return;
    if (state == AppLifecycleState.paused) {
      _presenceProvider?.setUserOffline(_currentUserId);
    } else if (state == AppLifecycleState.resumed) {
      _presenceProvider?.setUserOnline(_currentUserId);
      _markRead();
    }
  }

  @override
  void dispose() {
    _scheduled.forEach((_, t) {
      try {
        t.cancel();
      } catch (_) {}
    });
    _scheduled.clear();
    _scheduledContent.clear();
    _recTimer?.cancel();
    try {
      if (_presenceProvider != null && _currentUserId.isNotEmpty) {
        _presenceProvider!
          ..setUserOffline(_currentUserId)
          ..setTypingStatus(
              conversationId: _groupChatId,
              userId: _currentUserId,
              isTyping: false);
      }
    } catch (_) {}
    try {
      _voiceProvider?.dispose();
    } catch (_) {}
    super.dispose();
  }

  // ── Init ─────────────────────────────────────────────────────────────────

  void _initProviders(BuildContext ctx) {
    if (resourceManager.isDisposed) return;

    _chatProvider = ctx.read<ChatProvider>();
    _authProvider = ctx.read<AuthProvider>();
    _messageProvider = ctx.read<MessageProvider>();
    _reactionProvider = ctx.read<ReactionProvider>();
    _reminderProvider = ctx.read<ReminderProvider>();
    _autoDeleteProvider = ctx.read<AutoDeleteProvider>();
    _lockProvider = ctx.read<ConversationLockProvider>();
    _viewOnceProvider = ctx.read<ViewOnceProvider>();
    _smartReplyProvider = ctx.read<SmartReplyProvider>();
    _telemetryProvider = ctx.read<TelemetryProvider>();
    _presenceProvider = ctx.read<UserPresenceProvider>();
    _bubbleService = ctx.read<UnifiedBubbleService>();

    PushNotificationService.initialize()
        .catchError((e) => debugPrint('⚠️ Push: $e'));

    final sub = _bubbleService?.bubbleClickStream.listen((event) {
      if (event.userId == widget.arguments.peerId && mounted) {
        _toast('📨 ${widget.arguments.peerNickname}: ${event.message}',
            isSuccess: true);
      }
    });
    if (sub != null) resourceManager.addSubscription(sub);

    try {
      _voiceProvider =
          VoiceMessageProvider(firebaseStorage: _chatProvider.firebaseStorage);
    } catch (_) {}
    _locationProvider = LocationProvider();

    _readLocal();
    _loadPinned();
    _checkLock();

    if (_presenceProvider != null && _currentUserId.isNotEmpty) {
      _presenceProvider!.setUserOnline(_currentUserId);
    }

    ErrorLogger.logScreenView('chat_page');
  }

  void _readLocal() {
    final uid = _authProvider.userFirebaseId;
    if (uid == null || uid.isEmpty) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginPage()), (_) => false);
      return;
    }
    _currentUserId = uid;

    final peerId = widget.arguments.peerId;
    _groupChatId = _currentUserId.compareTo(peerId) > 0
        ? '$_currentUserId-$peerId'
        : '$peerId-$_currentUserId';

    _chatProvider.listenToFirebaseChanges(_groupChatId, _currentUserId, peerId);
    _listenIncoming();

    _chatProvider.updateDataFirestore(
      FirestoreConstants.pathUserCollection,
      _currentUserId,
      {FirestoreConstants.chattingWith: peerId},
    );

    resourceManager.addDelayedTimer(const Duration(milliseconds: 500), () {
      if (!resourceManager.isDisposed && mounted) {
        _markRead();
        unawaited(_loadSmartReplies());
        final msgs = LocalDbService().getMessages(_groupChatId);
        prefetchLinkPreviews(msgs.take(30).toList());
      }
    });
  }

  // ── Scroll ───────────────────────────────────────────────────────────────

  void _onScroll() {
    if (resourceManager.isDisposed || !_scrollController.hasClients) return;
    final pos = _scrollController.position;

    if (pos.pixels >= pos.maxScrollExtent - 200 && !pos.outOfRange) {
      final total = LocalDbService().getMessages(_groupChatId).length;
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

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic);
  }

  // ── Input ────────────────────────────────────────────────────────────────

  void _onInputChanged() {
    if (_inputController.text.trim().isNotEmpty) {
      _sendBtnAnim.forward();
    } else {
      _sendBtnAnim.reverse();
    }
  }

  void _onFocusChange() {
    if (resourceManager.isDisposed || !mounted) return;
    if (_focusNode.hasFocus) {
      setState(() {
        _isShowSticker = false;
        _showMenu = false;
      });
      _menuAnim.reverse();
    }
  }

  void _handleTyping(String text) {
    if (_presenceProvider == null || resourceManager.isDisposed) return;
    _telemetryProvider.recordTextChange(text);
    if (_telemetryProvider.shouldSuggestElderMode) {
      _showElderModeSuggestion();
      _telemetryProvider.markAsHandled();
    }
    if (text.isEmpty) {
      if (_isTyping) {
        _isTyping = false;
        _presenceProvider!.setTypingStatus(
            conversationId: _groupChatId,
            userId: _currentUserId,
            isTyping: false);
      }
      return;
    }
    if (!_isTyping) {
      _isTyping = true;
      _presenceProvider!.setTypingStatus(
          conversationId: _groupChatId, userId: _currentUserId, isTyping: true);
    }
    resourceManager.addDelayedTimer(const Duration(seconds: 3), () {
      if (!resourceManager.isDisposed) {
        _isTyping = false;
        _presenceProvider?.setTypingStatus(
            conversationId: _groupChatId,
            userId: _currentUserId,
            isTyping: false);
      }
    });
  }

  void _showElderModeSuggestion() {
    if (resourceManager.isDisposed || !mounted) return;
    final p = context.read<ThemeProvider>().palette;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.accessibility_new_rounded, color: Colors.white, size: 18),
        SizedBox(width: 10),
        Expanded(child: Text('Gặp khó khi gõ? Thử giao diện lớn hơn nhé!')),
      ]),
      duration: const Duration(seconds: 8),
      backgroundColor: p.textPrimary,
      action: SnackBarAction(
        label: 'BẬT',
        textColor: p.warningColor,
        onPressed: () {
          try {
            context.read<AppModeProvider>().setMode(AppMode.elder);
          } catch (_) {}
        },
      ),
    ));
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _onSend(String content, int type) async {
    if (resourceManager.isDisposed) return;
    if (content.trim().isEmpty && type == TypeMessage.text) {
      _toast('Không có nội dung để gửi');
      return;
    }
    HapticFeedback.mediumImpact();
    String finalContent = content;
    if (_replyingTo != null) {
      finalContent = '↪ ${_replyingTo!.content}\n$finalContent';
    }

    _inputController.clear();
    if (mounted && !resourceManager.isDisposed) {
      setState(() {
        _replyingTo = null;
        _smartReplies = [];
      });
      _replyAnim.reverse();
    }

    try {
      await _chatProvider.sendMessage(finalContent, type, _groupChatId,
          _currentUserId, widget.arguments.peerId);
      ErrorLogger.logMessageSent(
          conversationId: _groupChatId, messageType: type);
      await _updateBubble(finalContent, type, fromUser: true);
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'SendMessage');
      _toast('Lỗi gửi tin nhắn');
      return;
    }

    try {
      final msgId = DateTime.now().millisecondsSinceEpoch.toString();
      await _autoDeleteProvider.scheduleMessageDeletion(
          groupChatId: _groupChatId,
          messageId: msgId,
          conversationId: _groupChatId);
    } catch (_) {}

    if (!resourceManager.isDisposed) unawaited(_loadSmartReplies());

    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    }
  }

  Future<void> _updateBubble(String content, int type,
      {required bool fromUser}) async {
    if (_bubbleService == null || resourceManager.isDisposed) return;
    if (!_bubbleService!.isBubbleActive(widget.arguments.peerId)) return;
    String msgType = 'text', display = content;
    switch (type) {
      case TypeMessage.image:
        msgType = 'image';
        display = '📷 Ảnh';
        break;
      case TypeMessage.video:
        msgType = 'video';
        display = '🎬 Video';
        break;
      case 3:
        msgType = 'voice';
        display = '🎤 Thoại';
        break;
      case TypeMessage.geoLocked:
        msgType = 'text';
        display = '🔐 Tin nhắn ẩn địa điểm';
        break;
      default:
        if (content.contains('maps.google.com') ||
            content.contains('Location:')) {
          msgType = 'location';
          display = '📍 Vị trí';
        }
    }
    try {
      await _bubbleService!.sendMessage(
          userId: widget.arguments.peerId,
          userName: widget.arguments.peerNickname,
          message: display,
          avatarUrl: widget.arguments.peerAvatar,
          messageType: msgType);
    } catch (e) {
      debugPrint('❌ Bubble: $e');
    }
  }

  Future<void> _showBubbleIfNeeded() async {
    if (resourceManager.isDisposed) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      await _bubbleService?.showChatBubble(
          userId: widget.arguments.peerId,
          userName: widget.arguments.peerNickname,
          avatarUrl: widget.arguments.peerAvatar);
    }
  }

  // ── Media ────────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    try {
      final f = await _picker.pickImage(source: ImageSource.gallery);
      if (f != null) await _sendMedia(File(f.path), isVideo: false);
    } catch (_) {
      _toast('Không thể chọn ảnh');
    }
  }

  Future<void> _pickVideo() async {
    HapticFeedback.lightImpact();
    try {
      final f = await _picker.pickVideo(source: ImageSource.gallery);
      if (f != null) await _sendMedia(File(f.path), isVideo: true);
    } catch (_) {
      _toast('Không thể chọn video');
    }
  }

  Future<void> _sendMedia(File file, {required bool isVideo}) async {
    if (resourceManager.isDisposed) return;
    final confirmed = await _confirm(
        title: 'Gửi ${isVideo ? 'Video' : 'Ảnh'}',
        message:
            'Gửi ${isVideo ? 'video' : 'ảnh'} này đến ${widget.arguments.peerNickname}?',
        confirmLabel: 'Gửi',
        icon: isVideo ? Icons.videocam_rounded : Icons.image_rounded);
    if (confirmed != true || resourceManager.isDisposed) return;
    if (mounted) setState(() => _isLoadingMedia = true);
    try {
      final ok = await _chatProvider.sendMediaMessage(
          originalFile: file,
          isVideo: isVideo,
          groupChatId: _groupChatId,
          currentUserId: _currentUserId,
          peerId: widget.arguments.peerId,
          onLoadingStatusChanged: (v) {
            if (mounted) setState(() => _isLoadingMedia = v);
          });
      if (!mounted || resourceManager.isDisposed) return;
      _toast(
          ok != false
              ? (isVideo ? '🎬 Video đã gửi' : '📷 Ảnh đã gửi')
              : 'Gửi thất bại',
          isSuccess: ok != false);
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'SendMedia');
      _toast('Lỗi gửi media');
    } finally {
      if (mounted && !resourceManager.isDisposed)
        setState(() => _isLoadingMedia = false);
    }
  }

  // ── Sticker & Menu ───────────────────────────────────────────────────────

  void _toggleSticker() {
    if (resourceManager.isDisposed) return;
    HapticFeedback.lightImpact();
    _focusNode.unfocus();
    setState(() {
      _isShowSticker = !_isShowSticker;
      _showMenu = false;
    });
    _menuAnim.reverse();
  }

  // ── Voice ────────────────────────────────────────────────────────────────

  Future<void> _startRec() async {
    if (_voiceProvider == null) {
      _toast('Ghi âm không khả dụng');
      return;
    }
    final ok = await _voiceProvider!.initRecorder();
    if (!ok) {
      _toast('Cần quyền microphone');
      return;
    }
    final started = await _voiceProvider!.startRecording();
    if (started && mounted && !resourceManager.isDisposed) {
      HapticFeedback.lightImpact();
      setState(() {
        _isRecording = true;
        _recSeconds = 0;
        _recDuration = '0:00';
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || resourceManager.isDisposed) {
          t.cancel();
          return;
        }
        setState(() {
          _recSeconds++;
          final m = _recSeconds ~/ 60, s = _recSeconds % 60;
          _recDuration = '$m:${s.toString().padLeft(2, '0')}';
        });
      });
    }
  }

  Future<void> _stopRec() async {
    if (_voiceProvider == null) return;
    _recTimer?.cancel();
    final path = await _voiceProvider!.stopRecording();
    if (path == null) {
      if (mounted) setState(() => _isRecording = false);
      _toast('Ghi âm thất bại');
      return;
    }
    if (mounted)
      setState(() {
        _isRecording = false;
        _isLoading = true;
      });
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    final result = await _voiceProvider!.uploadVoiceMessage(path, fileName);
    if (mounted) setState(() => _isLoading = false);
    final url = result?.url;
    if (url != null && !resourceManager.isDisposed) {
      await _onSend(url, 3);
      _toast('🎤 Đã gửi tin nhắn thoại', isSuccess: true);
    } else {
      _toast('Gửi thoại thất bại');
    }
  }

  Future<void> _cancelRec() async {
    _recTimer?.cancel();
    await _voiceProvider?.cancelRecording();
    if (mounted) setState(() => _isRecording = false);
    HapticFeedback.heavyImpact();
  }

  // ── Location ─────────────────────────────────────────────────────────────

  Future<void> _shareLocation() async {
    if (_locationProvider == null) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final ok = await _locationProvider!.requestLocationPermission();
      if (!ok) {
        _toast('📍 Cần quyền vị trí');
        return;
      }
      final data = await _locationProvider!.getCurrentLocationWithDetails();
      if (data != null && !resourceManager.isDisposed) {
        await _onSend(
            _locationProvider!.formatLocationMessage(data), TypeMessage.text);
        _toast('📍 Đã chia sẻ vị trí', isSuccess: true);
      }
    } catch (_) {
      _toast('❌ Lỗi lấy vị trí');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── GeoLock ───────────────────────────────────────────────────────────────

  Future<void> _sendGeoLockedMessage() async {
    if (resourceManager.isDisposed) return;
    if (mounted)
      setState(() {
        _showMenu = false;
      });
    _menuAnim.reverse();

    final result = await Navigator.push<GeoLockData>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const GeoLockPickerPage(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
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
      await _onSend(content, TypeMessage.geoLocked);
      _toast(
          result.hideLocation
              ? '🔐 Đã gửi tin nhắn ẩn địa điểm'
              : '📍 Đã gửi tin nhắn khóa địa điểm',
          isSuccess: true);
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'SendGeoLock');
      _toast('Không thể gửi tin nhắn');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Maps ──────────────────────────────────────────────────────────────────

  Future<void> _openMaps(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri))
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ── Scheduled Message ────────────────────────────────────────────────────

  Future<void> _scheduleMessage() async {
    if (resourceManager.isDisposed) return;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ScheduleMessageDialog());
    if (result == null || resourceManager.isDisposed || !mounted) return;
    final text = result['message'] as String;
    final time = result['time'] as DateTime;
    final delay = time.difference(DateTime.now());
    if (delay.isNegative) {
      _toast('Thời gian không hợp lệ');
      return;
    }
    final key = time.millisecondsSinceEpoch.toString();
    _scheduledContent[key] = text;
    _scheduled[key] = Timer(delay, () {
      if (!resourceManager.isDisposed && mounted) {
        final c = _scheduledContent[key];
        if (c != null) _onSend(c, TypeMessage.text);
        _scheduled.remove(key);
        _scheduledContent.remove(key);
      }
    });
    _toast('📅 Lên lịch lúc ${DateFormat('HH:mm dd/MM').format(time)}',
        isSuccess: true);
  }

  // ── Smart Reply (AI) ─────────────────────────────────────────────────────

  Future<void> _loadSmartReplies() async {
    if (resourceManager.isDisposed) return;
    final msgs = LocalDbService().getMessages(_groupChatId);
    if (msgs.isEmpty) return;

    final last = msgs.first;
    if (last['idFrom'] == _currentUserId || last['type'] != TypeMessage.text)
      return;

    final content = last['content'] as String? ?? '';
    if (content.isEmpty || content.startsWith('{"iv":')) return;

    if (mounted && !resourceManager.isDisposed) {
      setState(() => _isLoadingSmartReply = true);
    }

    try {
      final history = msgs
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

  // ── Pinned & Listen ───────────────────────────────────────────────────────

  void _loadPinned() {
    if (resourceManager.isDisposed) return;
    final sub = _messageProvider.getPinnedMessages(_groupChatId).listen((snap) {
      if (!mounted || resourceManager.isDisposed) return;
      setState(() => _pinned = snap.docs);
    }, onError: (e) => ErrorLogger.logError(e, null, context: 'LoadPinned'));
    resourceManager.addSubscription(sub);
  }

  void _listenIncoming() {
    if (resourceManager.isDisposed ||
        _groupChatId.isEmpty ||
        _currentUserId.isEmpty) return;
    final sub = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(_groupChatId)
        .collection(_groupChatId)
        .where(FirestoreConstants.idTo, isEqualTo: _currentUserId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snap) async {
      if (resourceManager.isDisposed || _isProcessingMsg) return;
      _isProcessingMsg = true;
      try {
        for (final change in snap.docChanges) {
          if (resourceManager.isDisposed) break;
          if (change.type != DocumentChangeType.added) continue;
          final id = change.doc.id;
          if (_processedIds.contains(id)) continue;
          _processedIds.add(id);
          if (_processedIds.length > 200) {
            _processedIds.removeAll(_processedIds.take(100).toList());
          }
          final data = change.doc.data();
          if (data != null) {
            final type = data[FirestoreConstants.type] as int? ?? 0;
            await _updateBubble('Tin nhắn mới', type, fromUser: false);
          }
          _showBubbleIfNeeded();
        }
      } finally {
        _isProcessingMsg = false;
      }
    }, onError: (_) => _isProcessingMsg = false);
    resourceManager.addSubscription(sub);
  }

  Future<void> _markRead() async {
    if (resourceManager.isDisposed) return;
    try {
      final unread = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(_groupChatId)
          .collection(_groupChatId)
          .where(FirestoreConstants.idTo, isEqualTo: _currentUserId)
          .where('isRead', isEqualTo: false)
          .get();
      if (unread.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference,
            {'isRead': true, 'readAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
      _presenceProvider?.markMessagesAsRead(
          conversationId: _groupChatId, userId: _currentUserId);
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'MarkRead');
    }
  }

  // ── Game & AI Features ───────────────────────────────────────────────────

  void _openGameCenter() {
    HapticFeedback.lightImpact();
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => GameCenterHubPage(
                  groupId: _groupChatId,
                  groupName: widget.arguments.peerNickname,
                  currentUserId: _currentUserId,
                  currentUserName:
                      _authProvider.userFirebaseId ?? _currentUserId,
                  currentUserAvatar: '',
                )));
  }

  void _showSummarySheet() {
    final msgs = LocalDbService()
        .getMessages(_groupChatId)
        .take(30)
        .map((m) {
          final sender = m['idFrom'] == _currentUserId
              ? 'Tôi'
              : widget.arguments.peerNickname;
          final content = m['content']?.toString() ?? '';
          if (content.startsWith('{"iv":') || content.startsWith('{'))
            return null;
          return '$sender: $content';
        })
        .whereType<String>()
        .toList()
        .reversed
        .toList();

    if (msgs.length < 3) {
      _toast('Cần ít nhất 3 tin nhắn để phân tích');
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
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      _toast('Nhập nội dung muốn viết lại vào ô chat trước');
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
          _inputController.text = rewritten;
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
            conversationId: _groupChatId,
            peerName: widget.arguments.peerNickname,
          ),
        ));
  }

  void _openWeeklyRecap() {
    HapticFeedback.lightImpact();
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeeklyRecapPage(userId: _currentUserId),
        ));
  }

  void _showRelationshipMemory() {
    HapticFeedback.lightImpact();
    final p = context.read<ThemeProvider>().palette;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(
            16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 32),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
                color: p.shadowStrong,
                blurRadius: 24,
                offset: const Offset(0, -4))
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                  color: p.divider, borderRadius: BorderRadius.circular(999)),
            ),
          ),
          RelationshipMemoryWidget(
            conversationId: _groupChatId,
            peerName: widget.arguments.peerNickname,
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  void _showIcebreakers() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => IcebreakerPanel(
        peerId: widget.arguments.peerId,
        peerName: widget.arguments.peerNickname,
        onSelect: (text) {
          _inputController.text = text;
          _focusNode.requestFocus();
        },
      ),
    );
  }

  void _showAI() {
    final msgs = LocalDbService().getMessages(_groupChatId);
    if (msgs.isEmpty) {
      _toast('Chưa đủ tin nhắn để phân tích');
      return;
    }
    final recent = msgs
        .take(15)
        .map((d) {
          final s = d['idFrom'] == _currentUserId
              ? 'Tôi'
              : widget.arguments.peerNickname;
          return '$s: ${d['content']}';
        })
        .toList()
        .reversed
        .toList();
    final p = context.read<ThemeProvider>().palette;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AIDialog(
            messages: recent,
            palette: p,
            primary: context.read<ThemeProvider>().primaryColor));
  }

  // ── Message Options ───────────────────────────────────────────────────────

  void _showMsgOptions(MessageChat msg, String msgId) {
    if (resourceManager.isDisposed) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EnhancedMessageOptionsDialog(
        isOwnMessage: msg.idFrom == _currentUserId,
        isPinned: msg.isPinned,
        isDeleted: msg.isDeleted,
        messageContent: msg.content,
        onEdit: () => _editMsg(msgId, msg.content),
        onDelete: () => _deleteMsg(msgId),
        onPin: () => _pinMsg(msgId, msg.isPinned),
        onCopy: () => _copyMsg(msg.content),
        onReply: () => _setReply(msg),
        onReminder: () => _setReminder(msg, msgId),
        onTranslate: () => _translate(msg.content),
      ),
    );
  }

  Future<void> _editMsg(String id, String current) async {
    showDialog(
        context: context,
        builder: (_) => EditMessageDialog(
            originalContent: current,
            onSave: (newContent) async {
              final ok = await _messageProvider.editMessage(
                  _groupChatId, id, newContent);
              if (ok) _toast('Đã chỉnh sửa', isSuccess: true);
            }));
  }

  Future<void> _deleteMsg(String id) async {
    final ok = await _confirm(
        title: 'Xoá tin nhắn',
        message: 'Bạn có chắc muốn xóa?',
        confirmLabel: 'Xoá',
        icon: Icons.delete_rounded,
        isDanger: true);
    if (ok == true && !resourceManager.isDisposed) {
      final res = await _messageProvider.deleteMessage(_groupChatId, id);
      if (res) _toast('Đã xoá', isSuccess: true);
    }
  }

  Future<void> _pinMsg(String id, bool isPinned) async {
    final ok =
        await _messageProvider.togglePinMessage(_groupChatId, id, isPinned);
    if (ok) _toast(isPinned ? 'Đã bỏ ghim' : '📌 Đã ghim', isSuccess: true);
  }

  void _copyMsg(String content) {
    Clipboard.setData(ClipboardData(text: content));
    _toast('📋 Đã sao chép', isSuccess: true);
  }

  void _setReply(MessageChat msg) {
    HapticFeedback.selectionClick();
    if (resourceManager.isDisposed || !mounted) return;
    setState(() => _replyingTo = msg);
    _replyAnim.forward();
    _focusNode.requestFocus();
  }

  void _showReactionPicker(String msgId) {
    showDialog(
        context: context,
        builder: (_) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: ReactionPicker(onEmojiSelected: (emoji) {
                _reactionProvider.toggleReaction(
                    _groupChatId, msgId, _currentUserId, emoji);
                Navigator.pop(context);
              }),
            ));
  }

  Future<void> _setReminder(MessageChat msg, String msgId) async {
    final time = await _pickReminderTime();
    if (time == null || resourceManager.isDisposed) return;
    final reminder = await _reminderProvider.scheduleReminder(
        userId: _currentUserId,
        messageId: msgId,
        conversationId: _groupChatId,
        reminderTime: time,
        message: msg.content);
    _toast(reminder != null ? '⏰ Đã đặt nhắc nhở' : 'Không thể đặt',
        isSuccess: reminder != null);
  }

  Future<DateTime?> _pickReminderTime() => showDialog<DateTime>(
      context: context, builder: (_) => _ReminderPickerDialog());

  void _showReminders() {
    if (resourceManager.isDisposed) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _RemindersPage(
                currentUserId: _currentUserId,
                reminderProvider: _reminderProvider)));
  }

  void _translate(String content) {
    showDialog(
        context: context,
        builder: (_) => TranslationDialog(originalMessage: content));
  }

  // ── Lock ──────────────────────────────────────────────────────────────────

  Future<void> _checkLock() async {
    if (resourceManager.isDisposed) return;
    final status = await _lockProvider.getConversationLockStatus(_groupChatId);
    if (status != null && status.isLocked) {
      if (!mounted || resourceManager.isDisposed) return;
      final ok = await _showPinVerify();
      if (ok != true && mounted) Navigator.pop(context);
    }
    if (mounted && !resourceManager.isDisposed)
      setState(() => _lockChecked = true);
  }

  Future<bool?> _showPinVerify() async {
    String? errorMsg;
    int remaining = 5;
    while (remaining > 0 && !resourceManager.isDisposed) {
      final pin = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PINInputDialog(
              title: 'Nhập mã PIN',
              onComplete: (p) => Navigator.pop(context, p),
              errorMessage: errorMsg,
              remainingAttempts: remaining));
      if (pin == null || resourceManager.isDisposed) return false;
      final result = await _lockProvider.verifyPIN(
          conversationId: _groupChatId, enteredPin: pin);
      if (result.success) return true;
      remaining = 5 - result.failedAttempts;
      errorMsg = result.message;
      if (remaining <= 0 || result.locked) {
        await _lockProvider.autoDeleteMessagesAfterFailedAttempts(
            conversationId: _groupChatId);
        _toast('Đã xóa tin nhắn do vi phạm bảo mật');
        return false;
      }
    }
    return false;
  }

  void _showLockOptions() async {
    final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _LockOptionsSheet());
    if (action == 'set_pin' && !resourceManager.isDisposed)
      _setPin();
    else if (action == 'remove' && !resourceManager.isDisposed) {
      await _lockProvider.removeConversationLock(_groupChatId);
      _toast('Đã xóa khoá', isSuccess: true);
    }
  }

  void _setPin() async {
    final pin = await showDialog<String>(
        context: context,
        builder: (_) => PINInputDialog(
            title: 'Đặt Mã PIN', onComplete: (p) => Navigator.pop(context, p)));
    if (pin == null) return;
    final confirm = await showDialog<String>(
        context: context,
        builder: (_) => PINInputDialog(
            title: 'Xác Nhận PIN',
            onComplete: (p) => Navigator.pop(context, p)));
    if (confirm == pin && !resourceManager.isDisposed) {
      final ok = await _lockProvider.setConversationPIN(
          conversationId: _groupChatId, pin: pin);
      _toast(ok ? 'Đã đặt mã PIN' : 'Lỗi đặt PIN', isSuccess: ok);
    } else if (confirm != null) {
      _toast('PIN không khớp');
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<void> _openSearch() async {
    if (resourceManager.isDisposed) return;
    final id = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => SearchMessagesPage(
                groupChatId: _groupChatId,
                peerName: widget.arguments.peerNickname,
                peerId: widget.arguments.peerId)));
    if (id != null && mounted && !resourceManager.isDisposed) {
      setState(() => _pendingScrollId = id);
      resourceManager.addDelayedTimer(const Duration(milliseconds: 400), () {
        if (!mounted || resourceManager.isDisposed) return;
        _scrollToMsg(id);
      });
    }
  }

  void _scrollToMsg(String id) {
    if (!_scrollController.hasClients) return;
    final all = LocalDbService().getMessages(_groupChatId);
    final idx = all.indexWhere((m) => m['messageId'] == id);
    if (idx == -1) {
      if (mounted && _limit <= all.length) {
        setState(() => _limit += _limitIncrement);
        resourceManager.addDelayedTimer(
            const Duration(milliseconds: 500), () => _scrollToMsg(id));
      }
      return;
    }
    final offset =
        (idx * 76.0).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(offset,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    if (mounted) setState(() => _pendingScrollId = null);
  }

  // ── Bubble ────────────────────────────────────────────────────────────────

  Future<void> _createBubble() async {
    if (_bubbleService == null) return;
    if (!_bubbleService!.isSupported) {
      _toast('Thiết bị không hỗ trợ');
      return;
    }
    final hasPermission = await _bubbleService!.hasOverlayPermission();
    if (!hasPermission) {
      final granted = await _bubbleService!.requestOverlayPermission();
      if (!granted) {
        _toast('Cần quyền hiển thị');
        return;
      }
    }
    final choice = await _showBubbleChoiceDialog();
    if (choice == null) return;
    if (choice == 'bubble') {
      final ok = await _bubbleService!.showChatBubble(
          userId: widget.arguments.peerId,
          userName: widget.arguments.peerNickname,
          avatarUrl: widget.arguments.peerAvatar);
      _toast(ok ? '💬 Chat bubble đã tạo' : '❌ Không thể tạo', isSuccess: ok);
    } else if (choice == 'minichat') {
      final ok = await _bubbleService!.showMiniChat(
          userId: widget.arguments.peerId,
          userName: widget.arguments.peerNickname,
          avatarUrl: widget.arguments.peerAvatar);
      _toast(ok ? '💬 Mini chat đã mở' : '⚠️ Không hỗ trợ', isSuccess: ok);
    }
  }

  Future<String?> _showBubbleChoiceDialog() {
    final p = context.read<ThemeProvider>().palette;
    final primary = context.read<ThemeProvider>().primaryColor;
    return showDialog<String>(
        context: context,
        builder: (ctx) => _ThemedDialog(
              title: 'Tạo Chat Bubble',
              icon: Icons.bubble_chart_rounded,
              iconColor: primary,
              palette: p,
              content: Text('Chọn cách hiển thị:',
                  style: TextStyle(color: p.textSecondary)),
              actions: [
                _ThemedDialogAction(
                    label: 'Bubble',
                    isPrimary: true,
                    palette: p,
                    primary: primary,
                    onTap: () => Navigator.pop(ctx, 'bubble')),
                if (_bubbleService!.currentImplementation ==
                    BubbleImplementation.windowManager)
                  _ThemedDialogAction(
                      label: 'Mini Chat',
                      palette: p,
                      primary: primary,
                      onTap: () => Navigator.pop(ctx, 'minichat')),
                _ThemedDialogAction(
                    label: 'Huỷ',
                    palette: p,
                    primary: primary,
                    onTap: () => Navigator.pop(ctx)),
              ],
            ));
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _onBack() {
    if (_isShowSticker || _showMenu) {
      if (mounted)
        setState(() {
          _isShowSticker = false;
          _showMenu = false;
        });
      _menuAnim.reverse();
    } else {
      _chatProvider.updateDataFirestore(FirestoreConstants.pathUserCollection,
          _currentUserId, {FirestoreConstants.chattingWith: null});
      Navigator.pop(context);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _toast(String msg, {bool isSuccess = false}) {
    final p = context.read<ThemeProvider>().palette;
    Fluttertoast.showToast(
        msg: msg,
        backgroundColor: isSuccess ? p.successColor : p.surface,
        textColor: isSuccess ? Colors.white : p.textPrimary,
        toastLength: Toast.LENGTH_SHORT);
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    IconData? icon,
    bool isDanger = false,
  }) {
    final p = context.read<ThemeProvider>().palette;
    final primary = context.read<ThemeProvider>().primaryColor;
    return showDialog<bool>(
        context: context,
        builder: (ctx) => _ThemedDialog(
              title: title,
              icon: icon ?? Icons.help_outline_rounded,
              iconColor: isDanger ? p.dangerColor : primary,
              palette: p,
              content: Text(message, style: TextStyle(color: p.textSecondary)),
              actions: [
                _ThemedDialogAction(
                    label: confirmLabel,
                    isPrimary: !isDanger,
                    isDanger: isDanger,
                    palette: p,
                    primary: primary,
                    onTap: () => Navigator.pop(ctx, true)),
                _ThemedDialogAction(
                    label: 'Huỷ',
                    palette: p,
                    primary: primary,
                    onTap: () => Navigator.pop(ctx, false)),
              ],
            ));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmtTimestamp(String ts) {
    final ms = int.tryParse(ts) ?? 0;
    if (ms == 0) return '';
    return DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: widget.isBubbleMode
          ? _buildBubbleMode(p, theme)
          : widget.isMiniChat
              ? _buildMiniMode(p, theme)
              : _buildFullMode(p, theme),
    );
  }

  Widget _buildBubbleMode(ThemePalette p, ThemeProvider theme) => Scaffold(
        backgroundColor: p.background,
        body: PopScope(
          canPop: false,
          onPopInvokedWithResult: (d, _) {
            if (!d) _bubbleChannel.invokeMethod('minimize');
          },
          child: Column(children: [
            _OverlayHeader(
                nickname: widget.arguments.peerNickname,
                avatar: widget.arguments.peerAvatar,
                peerId: widget.arguments.peerId,
                onMinimize: () => _bubbleChannel.invokeMethod('minimize'),
                onClose: () => _bubbleChannel.invokeMethod('close'),
                palette: p,
                theme: theme),
            Expanded(child: _buildBody(p, theme)),
          ]),
        ),
      );

  Widget _buildMiniMode(ThemePalette p, ThemeProvider theme) => Scaffold(
        backgroundColor: p.background,
        body: PopScope(
          canPop: false,
          onPopInvokedWithResult: (d, _) {
            if (!d) {
              _focusNode.unfocus();
              _miniChatChannel.invokeMethod('minimize');
            }
          },
          child: Column(children: [
            _OverlayHeader(
                nickname: widget.arguments.peerNickname,
                avatar: widget.arguments.peerAvatar,
                peerId: widget.arguments.peerId,
                onMinimize: () {
                  _focusNode.unfocus();
                  _miniChatChannel.invokeMethod('minimize');
                },
                onClose: () {
                  _focusNode.unfocus();
                  _miniChatChannel.invokeMethod('close');
                },
                palette: p,
                theme: theme),
            Expanded(child: _buildBody(p, theme)),
          ]),
        ),
      );

  Widget _buildFullMode(ThemePalette p, ThemeProvider theme) => Scaffold(
        backgroundColor: p.background,
        appBar: _buildAppBar(p, theme),
        body: SafeArea(
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (d, _) {
              if (!d) _onBack();
            },
            child: _buildBody(p, theme),
          ),
        ),
      );

  PreferredSizeWidget _buildAppBar(ThemePalette p, ThemeProvider theme) =>
      PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: FadeTransition(
          opacity: _appBarAnim,
          child: Container(
            decoration: BoxDecoration(
              color: p.appBarBackground,
              boxShadow: [
                BoxShadow(
                    color: p.shadow, blurRadius: 8, offset: const Offset(0, 2))
              ],
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leadingWidth: widget.isWebMode ? 0 : 48,
              leading: widget.isWebMode
                  ? null
                  : IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20, color: theme.primaryColor),
                      onPressed: _onBack),
              title: _AppBarTitle(
                  peerId: widget.arguments.peerId,
                  peerNickname: widget.arguments.peerNickname,
                  peerAvatar: widget.arguments.peerAvatar,
                  palette: p,
                  theme: theme,
                  onTap: () async {
                    final doc = await FirebaseFirestore.instance
                        .collection(FirestoreConstants.pathUserCollection)
                        .doc(widget.arguments.peerId)
                        .get();
                    if (doc.exists && mounted) {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => UserProfilePage(
                                  userChat: UserChat.fromDocument(doc))));
                    }
                  }),
              actions: [
                VideoCallIconButton(
                    peerId: widget.arguments.peerId,
                    peerName: widget.arguments.peerNickname,
                    peerAvatar: widget.arguments.peerAvatar),
                VoiceCallIconButton(
                    peerId: widget.arguments.peerId,
                    peerName: widget.arguments.peerNickname,
                    peerAvatar: widget.arguments.peerAvatar),
                SentimentIndicatorWidget(groupChatId: _groupChatId),
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'ai':
                        _showAI();
                        break;
                      case 'summarize':
                        _showSummarySheet();
                        break;
                      case 'tone':
                        _showToneRewriter();
                        break;
                      case 'insights':
                        _openInsightsPage();
                        break;
                      case 'weekly':
                        _openWeeklyRecap();
                        break;
                      case 'relationship':
                        _showRelationshipMemory();
                        break;
                      case 'icebreaker':
                        _showIcebreakers();
                        break;
                      case 'search':
                        _openSearch();
                        break;
                      case 'reminders':
                        _showReminders();
                        break;
                      case 'lock':
                        _showLockOptions();
                        break;
                      case 'bubble':
                        _createBubble();
                        break;
                      case 'game':
                        _openGameCenter();
                        break;
                      case 'theme':
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ThemeSettingsPage()));
                        break;
                    }
                  },
                  icon: Icon(Icons.more_vert_rounded,
                      size: 22, color: p.textSecondary),
                  color: p.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  itemBuilder: (_) {
                    final msgCount =
                        LocalDbService().getMessages(_groupChatId).length;
                    return [
                      _popItem('ai', Icons.auto_awesome_rounded, 'AI Assistant',
                          const Color(0xFF8B5CF6), p),
                      _popItem('game', Icons.sports_esports_rounded,
                          'Game Center', const Color(0xFF9C27B0), p),
                      const PopupMenuDivider(),
                      _popItem('summarize', Icons.summarize_rounded,
                          'Tóm tắt & Phân tích', const Color(0xFF0EA5E9), p),
                      _popItem('tone', Icons.edit_note_rounded,
                          'Viết lại tông giọng', const Color(0xFF8B5CF6), p),
                      _popItem('insights', Icons.psychology_rounded,
                          'AI Insights', const Color(0xFFF59E0B), p),
                      _popItem('relationship', Icons.favorite_outline_rounded,
                          'Mối quan hệ', const Color(0xFFEC4899), p),
                      _popItem('weekly', Icons.analytics_rounded,
                          'Weekly Recap', const Color(0xFF10B981), p),
                      if (msgCount < 3)
                        _popItem('icebreaker', Icons.waving_hand_rounded,
                            'Gợi ý mở đầu', const Color(0xFF10B981), p),
                      const PopupMenuDivider(),
                      _popItem('search', Icons.search_rounded, 'Tìm kiếm',
                          theme.primaryColor, p),
                      _popItem('reminders', Icons.alarm_rounded, 'Nhắc nhở',
                          p.warningColor, p),
                      const PopupMenuDivider(),
                      _popItem('lock', Icons.lock_rounded, 'Khoá chat',
                          p.infoColor, p),
                      _popItem('bubble', Icons.bubble_chart_rounded,
                          'Chat Bubble', p.successColor, p),
                      _popItem('theme', Icons.palette_rounded, 'Giao diện',
                          theme.primaryColor, p),
                    ];
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      );

  PopupMenuItem<String> _popItem(String value, IconData icon, String label,
          Color color, ThemePalette p) =>
      PopupMenuItem(
          value: value,
          child: Row(children: [
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 17)),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ]));

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody(ThemePalette p, ThemeProvider theme) {
    return ChatWallpaperWidget(
      wallpaper: theme.chatWallpaper,
      color: theme.primaryColor,
      opacity: theme.chatWallpaperOpacity,
      child: Stack(children: [
        Column(children: [
          const OfflineIndicator(),
          _buildPinnedBar(p, theme),
          _buildMsgList(p, theme),
          _buildTypingBar(p, theme),
          if (_isShowSticker && !widget.isMiniChat && !widget.isBubbleMode)
            _buildStickerPanel(p, theme),
          if (_showMenu && !widget.isMiniChat && !widget.isBubbleMode)
            _buildFeatureMenu(p, theme),
          _buildInput(p, theme),
        ]),
        if (_isLoading) const Positioned.fill(child: LoadingView()),
        if (_isLoadingMedia)
          Positioned.fill(child: _buildMediaOverlay(p, theme)),
      ]),
    );
  }

  Widget _buildPinnedBar(ThemePalette p, ThemeProvider theme) {
    if (_pinned.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: p.surface,
          border: Border(bottom: BorderSide(color: p.divider))),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        itemCount: _pinned.length,
        itemBuilder: (_, i) {
          final msg = MessageChat.fromDocument(_pinned[i]);
          return Container(
            constraints: const BoxConstraints(maxWidth: 200),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: p.pinnedBackground,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: theme.primaryColor.withValues(alpha: 0.25),
                  width: 0.8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.push_pin_rounded, size: 12, color: theme.primaryColor),
              const SizedBox(width: 5),
              Flexible(
                  child: Text(msg.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w600))),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildMsgList(ThemePalette p, ThemeProvider theme) {
    return Flexible(
      child: _groupChatId.isNotEmpty
          ? ValueListenableBuilder(
              valueListenable: LocalDbService().messagesBox.listenable(),
              builder: (_, Box box, __) {
                final all = LocalDbService().getMessages(_groupChatId);
                final display = all.take(_limit).toList();

                if (display.isEmpty) {
                  return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                            color: p.primaryContainer, shape: BoxShape.circle),
                        child: Icon(Icons.chat_bubble_outline_rounded,
                            size: 36, color: theme.primaryColor)),
                    const SizedBox(height: 16),
                    Text('Bắt đầu cuộc trò chuyện',
                        style: TextStyle(
                            color: p.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                    const SizedBox(height: 6),
                    Text('Hãy gửi tin nhắn đầu tiên! 👋',
                        style: TextStyle(color: p.textHint, fontSize: 13)),
                  ]));
                }

                prefetchLinkPreviews(display);

                return Stack(children: [
                  ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    itemCount: display.length,
                    itemBuilder: (_, i) =>
                        _buildMsgItem(i, display[i], display, p, theme),
                  ),
                  Positioned(
                      right: 12,
                      bottom: 12,
                      child: ScaleTransition(
                        scale: CurvedAnimation(
                            parent: _fabAnim, curve: Curves.elasticOut),
                        child: _ScrollFab(
                            onTap: _scrollToBottom, palette: p, theme: theme),
                      )),
                ]);
              })
          : Center(
              child: CircularProgressIndicator(
                  color: theme.primaryColor, strokeWidth: 2)),
    );
  }

  Widget _buildMsgItem(int index, Map<dynamic, dynamic> data,
      List<Map<dynamic, dynamic>> full, ThemePalette p, ThemeProvider theme) {
    final isHighlighted = _pendingScrollId == data['messageId'];
    final isPending = data['status'] == 'pending';
    final msg = MessageChat(
      idFrom: data['idFrom'] ?? '',
      idTo: data['idTo'] ?? '',
      timestamp: data['timestamp'] ?? '',
      content: data['content'] ?? '',
      type: data['type'] ?? 0,
      isRead: data['status'] == 'sent',
    );
    bool isLastInGroup = true;
    if (index > 0) isLastInGroup = full[index - 1]['idFrom'] != msg.idFrom;

    Widget? sep;
    if (index == full.length - 1 ||
        !_sameDay(
            DateTime.fromMillisecondsSinceEpoch(
                int.tryParse(msg.timestamp) ?? 0),
            DateTime.fromMillisecondsSinceEpoch(
                int.tryParse(full[index + 1]['timestamp'] ?? '0') ?? 0))) {
      sep = _DateDivider(
          date: DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(msg.timestamp) ?? 0),
          palette: p);
    }

    final bubble = _buildBubble(
        msgId: data['messageId'] ?? '',
        msg: msg,
        data: data,
        isLastInGroup: isLastInGroup,
        isHighlighted: isHighlighted,
        isPending: isPending,
        p: p,
        theme: theme);

    return Column(children: [
      SwipeToReplyWrapper(
          isMe: msg.idFrom == _currentUserId,
          onSwipe: () => _setReply(msg),
          child: bubble),
      if (sep != null) sep,
    ]);
  }

  Widget _buildBubble({
    required String msgId,
    required MessageChat msg,
    required Map<dynamic, dynamic> data,
    required bool isLastInGroup,
    bool isHighlighted = false,
    bool isPending = false,
    required ThemePalette p,
    required ThemeProvider theme,
  }) {
    final isMe = msg.idFrom == _currentUserId;

    Widget wrap(Widget child) {
      if (!isHighlighted) return child;
      return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16)),
          child: child);
    }

    if (data['isViewOnce'] ?? false) {
      return wrap(Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ViewOnceMessageWidget(
              groupChatId: _groupChatId,
              messageId: msgId,
              content: msg.content,
              type: msg.type,
              currentUserId: _currentUserId,
              isViewed: data['isViewed'] ?? false,
              provider: _viewOnceProvider)));
    }
    if (msg.type == 3 && _voiceProvider != null) {
      return wrap(Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: VoiceMessageWidget(
              voiceUrl: msg.content,
              isMyMessage: isMe,
              voiceProvider: _voiceProvider!)));
    }
    if (msg.type == TypeMessage.video) {
      return wrap(_buildVideoBubble(
          msgId: msgId,
          msg: msg,
          isMe: isMe,
          isLastInGroup: isLastInGroup,
          isPending: isPending,
          p: p,
          theme: theme));
    }
    if (msg.type == TypeMessage.image) {
      return wrap(_buildImageBubble(
          msgId: msgId,
          msg: msg,
          isMe: isMe,
          isLastInGroup: isLastInGroup,
          isPending: isPending,
          p: p,
          theme: theme));
    }
    if (msg.type == TypeMessage.sticker) {
      return wrap(Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
              onLongPress: () => _showMsgOptions(msg, msgId),
              child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Image.asset('images/${msg.content}.gif',
                      width: 90, height: 90, fit: BoxFit.cover)))));
    }
    if (msg.type == TypeMessage.geoLocked) {
      return wrap(Container(
        margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
            onLongPress: () => _showMsgOptions(msg, msgId),
            child: GeoLockedMessageWidget(content: msg.content, isMe: isMe)),
      ));
    }
    return wrap(_buildTextBubble(
        msgId: msgId,
        msg: msg,
        isMe: isMe,
        isLastInGroup: isLastInGroup,
        isPending: isPending,
        isScam: data['scamWarning'] ?? false,
        scamReason: data['scamReason'] ?? '',
        hasReminder: data['hasReminder'] ?? false,
        isHateful: data['isHateful'] ?? false,
        hateSpeechCategory: data['hateSpeechCategory'] ?? 'hate',
        p: p,
        theme: theme));
  }

  Widget _buildTextBubble({
    required String msgId,
    required MessageChat msg,
    required bool isMe,
    required bool isLastInGroup,
    required bool isPending,
    bool isScam = false,
    String scamReason = '',
    bool hasReminder = false,
    bool isHateful = false,
    String hateSpeechCategory = 'hate',
    required ThemePalette p,
    required ThemeProvider theme,
  }) {
    final location = _locationProvider?.parseLocationFromMessage(msg.content);
    final isAI = msg.idFrom == AppConstants.aiAssistantId;
    final fs = theme.fontSizeMultiplier;
    final hasUrl = !msg.isDeleted &&
        msg.type == TypeMessage.text &&
        location == null &&
        !isAI &&
        UrlDetector.containsUrl(msg.content);

    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe && isLastInGroup && theme.showAvatarsInChat) ...[
                _Avatar(
                    photoUrl: widget.arguments.peerAvatar,
                    radius: 16,
                    primary: theme.primaryColor),
                const SizedBox(width: 6),
              ] else if (!isMe) ...[
                SizedBox(width: theme.showAvatarsInChat ? 38 : 0)
              ],
              GestureDetector(
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  _showMsgOptions(msg, msgId);
                },
                onDoubleTap: () {
                  HapticFeedback.mediumImpact();
                  _showReactionPicker(msgId);
                },
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width *
                          (hasUrl ? 0.82 : theme.bubbleMaxWidthFactor)),
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
                      boxShadow: [
                        BoxShadow(
                            color: isMe
                                ? theme.primaryColor.withValues(alpha: 0.25)
                                : p.shadow,
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                      border: isMe
                          ? null
                          : Border.all(color: p.divider, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isMe && isScam)
                          _ScamWarning(reason: scamReason, palette: p),
                        if (!isMe && isHateful)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ToxicMessageBadge(
                              category: hateSpeechCategory,
                              showDetails: true,
                            ),
                          ),
                        if (!isMe && hasReminder)
                          _ReminderHint(onView: _showReminders, palette: p),
                        if (msg.isDeleted)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.block_rounded,
                                size: 13,
                                color: isMe ? Colors.white54 : p.textHint),
                            const SizedBox(width: 6),
                            Text('Tin nhắn đã xóa',
                                style: TextStyle(
                                    fontSize: 14 * fs,
                                    color: isMe ? Colors.white54 : p.textHint,
                                    fontStyle: FontStyle.italic)),
                          ])
                        else if (location != null)
                          _LocationContent(
                              location: location,
                              isMe: isMe,
                              palette: p,
                              theme: theme,
                              onOpen: () => _openMaps(location.mapsUrl))
                        else if (isAI)
                          MarkdownBody(
                              data: msg.content,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(
                                      fontSize: 15 * fs,
                                      color:
                                          isMe ? Colors.white : p.incomingText,
                                      height: 1.5)))
                        else if (hasUrl)
                          ChatMessageWithLinkPreview(
                            content: msg.content,
                            isMe: isMe,
                            textColor: isMe ? Colors.white : p.incomingText,
                            fontSize: 15 * fs,
                            primaryColor: theme.primaryColor,
                            showPreview: true,
                          )
                        else
                          Text(msg.content,
                              style: TextStyle(
                                  color: isMe ? Colors.white : p.incomingText,
                                  fontSize: 15 * fs,
                                  height: 1.45)),
                        if (isMe) ...[
                          const SizedBox(height: 3),
                          Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (msg.editedAt != null)
                                  Text('(đã sửa) ',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white
                                              .withValues(alpha: 0.6))),
                                Icon(
                                    isPending
                                        ? Icons.schedule_rounded
                                        : msg.isRead
                                            ? Icons.done_all_rounded
                                            : Icons.check_rounded,
                                    size: 13,
                                    color: isPending
                                        ? Colors.white38
                                        : msg.isRead
                                            ? Colors.white
                                            : Colors.white60),
                              ]),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (!msg.isDeleted)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  _QuickBtn(
                      icon: Icons.add_reaction_outlined,
                      onTap: () => _showReactionPicker(msgId),
                      palette: p),
                  if (!isMe)
                    _QuickBtn(
                        icon: Icons.alarm_add_rounded,
                        onTap: () => _setReminder(msg, msgId),
                        palette: p),
                ]),
            ],
          ),
          if (!isMe && msg.type == TypeMessage.text) ...[
            const SizedBox(height: 3),
            Padding(
                padding: const EdgeInsets.only(left: 44),
                child: _ScamScanWidget(
                    msgId: msgId,
                    content: msg.content,
                    result: _scamResults[msgId],
                    palette: p,
                    onScan: (result) {
                      if (mounted) setState(() => _scamResults[msgId] = result);
                    })),
          ],
          _ReactionRow(
              groupChatId: _groupChatId,
              msgId: msgId,
              currentUserId: _currentUserId,
              isMe: isMe,
              provider: _reactionProvider,
              onTap: (emoji) => _reactionProvider.toggleReaction(
                  _groupChatId, msgId, _currentUserId, emoji)),
          if (isLastInGroup || theme.showTimestampAlways)
            Padding(
                padding: EdgeInsets.only(
                    left: isMe ? 0 : (theme.showAvatarsInChat ? 44 : 4),
                    right: isMe ? 6 : 0,
                    top: 3),
                child: Text(_fmtTimestamp(msg.timestamp),
                    style: TextStyle(fontSize: 10.5, color: p.textHint))),
        ],
      ),
    );
  }

  Widget _buildImageBubble({
    required String msgId,
    required MessageChat msg,
    required bool isMe,
    required bool isLastInGroup,
    required bool isPending,
    required ThemePalette p,
    required ThemeProvider theme,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          if (!isPending)
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => FullPhotoPage(url: msg.content)));
        },
        onLongPress: () => _showMsgOptions(msg, msgId),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.62,
              height: 220,
              child: isPending
                  ? _MediaPlaceholder(
                      isLoading: true, palette: p, primary: theme.primaryColor)
                  : Image.network(msg.content,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, prog) => prog == null
                          ? child
                          : _MediaPlaceholder(
                              isLoading: true,
                              palette: p,
                              primary: theme.primaryColor,
                              progress: prog.expectedTotalBytes != null
                                  ? prog.cumulativeBytesLoaded /
                                      prog.expectedTotalBytes!
                                  : null),
                      errorBuilder: (_, __, ___) => _MediaPlaceholder(
                          isLoading: false,
                          palette: p,
                          primary: theme.primaryColor))),
        ),
      ),
    );
  }

  Widget _buildVideoBubble({
    required String msgId,
    required MessageChat msg,
    required bool isMe,
    required bool isLastInGroup,
    required bool isPending,
    required ThemePalette p,
    required ThemeProvider theme,
  }) {
    final parts = msg.content.split('|');
    final videoUrl = parts.isNotEmpty ? parts[0] : '';
    final thumbUrl = parts.length > 1 ? parts[1] : '';
    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          if (!isPending)
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => VideoPlayerPage(videoUrl: videoUrl)));
        },
        onLongPress: () => _showMsgOptions(msg, msgId),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.65,
          height: 200,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                    color: p.shadowStrong,
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ]),
          clipBehavior: Clip.hardEdge,
          child: Stack(fit: StackFit.expand, children: [
            if (thumbUrl.isNotEmpty && !isPending)
              Image.network(thumbUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1F2937)))
            else
              const ColoredBox(color: Color(0xFF1F2937)),
            if (isPending)
              const Center(
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
            else
              Center(
                  child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8)
                          ]),
                      child: const Icon(Icons.play_arrow_rounded,
                          size: 30, color: Color(0xFF1A1D2E)))),
            Positioned(
                bottom: 8,
                right: 10,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.videocam_rounded,
                          size: 11, color: Colors.white),
                      SizedBox(width: 3),
                      Text('Video',
                          style: TextStyle(fontSize: 10, color: Colors.white)),
                    ]))),
          ]),
        ),
      ),
    );
  }

  Widget _buildTypingBar(ThemePalette p, ThemeProvider theme) {
    if (_presenceProvider == null) return const SizedBox.shrink();
    return StreamBuilder<Map<String, TypingInfo>>(
      stream: _presenceProvider!.getTypingStatusStream(_groupChatId),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final isTyping = snap.data![widget.arguments.peerId]?.isTyping ?? false;
        if (!isTyping) return const SizedBox.shrink();
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: TypingIndicator(userName: widget.arguments.peerNickname));
      },
    );
  }

  Widget _buildStickerPanel(ThemePalette p, ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
          color: p.surface, border: Border(top: BorderSide(color: p.divider))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
              3,
              (row) => Padding(
                  padding: EdgeInsets.only(bottom: row < 2 ? 6 : 0),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                          3,
                          (col) => _StickerItem(
                              name: 'mimi${row * 3 + col + 1}',
                              onTap: () => _onSend('mimi${row * 3 + col + 1}',
                                  TypeMessage.sticker))))))),
    );
  }

  Widget _buildFeatureMenu(ThemePalette p, ThemeProvider theme) {
    final items = <_FeatureItem>[
      _FeatureItem(Icons.image_rounded, 'Ảnh', _pickImage, theme.primaryColor),
      _FeatureItem(
          Icons.videocam_rounded, 'Video', _pickVideo, const Color(0xFFFF6B9D)),
      _FeatureItem(Icons.add_location_alt_rounded, 'GeoLock',
          _sendGeoLockedMessage, const Color(0xFF7B1FA2)),
      _FeatureItem(
          Icons.visibility_off_rounded,
          'View Once',
          () => showDialog(
              context: context,
              builder: (_) =>
                  SendViewOnceDialog(onSend: (content, type, dur) async {
                    await _viewOnceProvider.sendViewOnceMessage(
                        groupChatId: _groupChatId,
                        currentUserId: _currentUserId,
                        peerId: widget.arguments.peerId,
                        content: content,
                        type: type);
                    unawaited(_loadSmartReplies());
                  })),
          const Color(0xFF8B5CF6)),
      _FeatureItem(
          Icons.timer_rounded,
          'Tự xoá',
          () => showDialog(
              context: context,
              builder: (_) => AutoDeleteSettingsDialog(
                  conversationId: _groupChatId, provider: _autoDeleteProvider)),
          p.warningColor),
      _FeatureItem(Icons.lock_rounded, 'Khoá', _showLockOptions, p.infoColor),
      _FeatureItem(
          Icons.location_on_rounded, 'Vị trí', _shareLocation, p.dangerColor),
      _FeatureItem(Icons.schedule_send_rounded, 'Lên lịch', _scheduleMessage,
          p.successColor),
      _FeatureItem(Icons.bubble_chart_rounded, 'Bubble', _createBubble,
          theme.primaryColor),
      _FeatureItem(Icons.sports_esports_rounded, 'Game', _openGameCenter,
          const Color(0xFF9C27B0)),
      _FeatureItem(Icons.waving_hand_rounded, 'Mở đầu', _showIcebreakers,
          const Color(0xFF10B981)),
    ];
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
              CurvedAnimation(parent: _menuAnim, curve: Curves.easeOutCubic)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 120),
        decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.divider)),
            boxShadow: [BoxShadow(color: p.shadow, blurRadius: 8)]),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
              children: items
                  .map((item) => GestureDetector(
                        onTap: () {
                          if (resourceManager.isDisposed) return;
                          if (item.label != 'GeoLock') {
                            setState(() => _showMenu = false);
                            _menuAnim.reverse();
                          }
                          item.onTap();
                        },
                        child: Container(
                            width: 72,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                          color:
                                              item.color.withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                              color: item.color
                                                  .withValues(alpha: 0.2),
                                              width: 0.8)),
                                      child: Icon(item.icon,
                                          color: item.color, size: 22)),
                                  const SizedBox(height: 5),
                                  Text(item.label,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: p.textSecondary,
                                          fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center),
                                ])),
                      ))
                  .toList()),
        ),
      ),
    );
  }

  Widget _buildRecBar(ThemePalette p, ThemeProvider theme) {
    if (!_isRecording) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: p.dangerColor.withValues(alpha: 0.05),
          border: Border(
              top: BorderSide(color: p.dangerColor.withValues(alpha: 0.2)))),
      child: Row(children: [
        _RecDot(color: p.dangerColor),
        const SizedBox(width: 10),
        Text('Đang ghi âm  $_recDuration',
            style: TextStyle(
                color: p.dangerColor,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
        const Spacer(),
        _IconBtn(
            icon: Icons.delete_outline_rounded,
            color: p.dangerColor,
            onTap: _cancelRec),
        const SizedBox(width: 6),
        _IconBtn(
            icon: Icons.send_rounded,
            color: theme.primaryColor,
            onTap: _stopRec),
      ]),
    );
  }

  Widget _buildInput(ThemePalette p, ThemeProvider theme) {
    final full = !widget.isBubbleMode && !widget.isMiniChat;
    final fs = theme.fontSizeMultiplier;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (full && (_smartReplies.isNotEmpty || _isLoadingSmartReply))
        _buildSmartReplyBar(p, theme),
      _buildRecBar(p, theme),
      Container(
        margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 10,
            left: 12,
            right: 12,
            top: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: _replyingTo == null
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border(
                            left: BorderSide(
                                color: theme.primaryColor, width: 3)),
                        boxShadow: [BoxShadow(color: p.shadow, blurRadius: 6)]),
                    child: Row(children: [
                      Icon(Icons.reply_rounded,
                          color: theme.primaryColor, size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('Trả lời: ${_replyingTo!.content}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500))),
                      GestureDetector(
                        onTap: () {
                          if (mounted) {
                            setState(() => _replyingTo = null);
                            _replyAnim.reverse();
                            _focusNode.requestFocus();
                          }
                        },
                        child: Icon(Icons.close_rounded,
                            size: 17, color: p.textHint),
                      ),
                    ])),
          ),
          Container(
            decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                      color: p.shadow,
                      blurRadius: 12,
                      offset: const Offset(0, 3))
                ],
                border: Border.all(color: p.inputBorder, width: 0.6)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (full)
                GestureDetector(
                  onTap: () {
                    if (resourceManager.isDisposed) return;
                    setState(() {
                      _showMenu = !_showMenu;
                      _isShowSticker = false;
                    });
                    if (_showMenu) {
                      _menuAnim.forward();
                      _focusNode.unfocus();
                    } else {
                      _menuAnim.reverse();
                    }
                  },
                  child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: AnimatedRotation(
                          turns: _showMenu ? 0.125 : 0,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          child: Icon(Icons.add_circle_rounded,
                              color:
                                  _showMenu ? theme.primaryColor : p.textHint,
                              size: 28))),
                ),
              if (full && !_showMenu)
                GestureDetector(
                    onTap: _pickImage,
                    child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.image_rounded,
                            color: p.textHint, size: 24))),
              if (full && !_showMenu)
                GestureDetector(
                    onTap: _toggleSticker,
                    child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.emoji_emotions_outlined,
                            color: _isShowSticker
                                ? theme.primaryColor
                                : p.textHint,
                            size: 24))),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      left: full ? 0 : 16, right: 6, top: 12, bottom: 12),
                  child: TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    style: TextStyle(
                        color: p.textPrimary, fontSize: 15 * fs, height: 1.45),
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    autofocus: widget.isMiniChat || widget.isBubbleMode,
                    onChanged: (t) {
                      _handleTyping(t);
                      if (t.isNotEmpty && _smartReplies.isNotEmpty && mounted) {
                        setState(() => _smartReplies = []);
                      }
                    },
                    onSubmitted: (_) {
                      if (!resourceManager.isDisposed)
                        _onSend(_inputController.text, TypeMessage.text);
                    },
                    decoration: InputDecoration.collapsed(
                        hintText: 'Nhắn tin...',
                        hintStyle:
                            TextStyle(color: p.textHint, fontSize: 15 * fs)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _inputController,
                  builder: (_, val, __) {
                    final hasText = val.text.trim().isNotEmpty;
                    return GestureDetector(
                      onTap: () {
                        if (hasText) {
                          _onSend(_inputController.text, TypeMessage.text);
                        } else if (full) {
                          _startRec();
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 44,
                        height: 44,
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
                                hasText
                                    ? Icons.send_rounded
                                    : Icons.mic_rounded,
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
      ),
    ]);
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
                  onReplySelected: (r) {
                    if (!resourceManager.isDisposed) {
                      _inputController.text = r;
                      setState(() => _smartReplies = []);
                      _focusNode.requestFocus();
                    }
                  }),
            ),
    );
  }

  Widget _buildMediaOverlay(ThemePalette p, ThemeProvider theme) => Container(
        color: Colors.black54,
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
            Text('Đang nén & tải lên...',
                style: TextStyle(
                    color: p.textPrimary, fontWeight: FontWeight.w600)),
          ]),
        )),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// PRIVATE SUB-WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({
    required this.peerId,
    required this.peerNickname,
    required this.peerAvatar,
    required this.palette,
    required this.theme,
    required this.onTap,
  });
  final String peerId, peerNickname, peerAvatar;
  final ThemePalette palette;
  final ThemeProvider theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Row(children: [
          AvatarWithStatus(
              userId: peerId,
              photoUrl: peerAvatar,
              size: 40,
              indicatorSize: 11),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(peerNickname,
                    style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3),
                    overflow: TextOverflow.ellipsis),
                UserStatusIndicator(userId: peerId, showText: true, size: 8),
              ])),
        ]),
      );
}

class _OverlayHeader extends StatelessWidget {
  const _OverlayHeader({
    required this.nickname,
    required this.avatar,
    required this.peerId,
    required this.onMinimize,
    required this.onClose,
    required this.palette,
    required this.theme,
  });
  final String nickname, avatar, peerId;
  final VoidCallback onMinimize, onClose;
  final ThemePalette palette;
  final ThemeProvider theme;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(bottom: BorderSide(color: palette.divider))),
        child: Row(children: [
          _Avatar(photoUrl: avatar, radius: 18, primary: theme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(nickname,
                    style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                UserStatusIndicator(
                    userId: peerId,
                    showText: true,
                    size: 7,
                    textColor: palette.textHint),
              ])),
          _IconBtn(
              icon: Icons.remove_rounded,
              color: palette.textHint,
              onTap: onMinimize,
              size: 22),
          const SizedBox(width: 2),
          _IconBtn(
              icon: Icons.close_rounded,
              color: palette.textHint,
              onTap: onClose,
              size: 22),
        ]),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar(
      {required this.photoUrl, required this.radius, required this.primary});
  final String photoUrl;
  final double radius;
  final Color primary;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: primary.withValues(alpha: 0.12),
        backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
        child: photoUrl.isEmpty
            ? Icon(Icons.person_rounded, size: radius, color: primary)
            : null,
      );
}

class _QuickBtn extends StatelessWidget {
  const _QuickBtn(
      {required this.icon, required this.onTap, required this.palette});
  final IconData icon;
  final VoidCallback onTap;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 16, color: palette.textHint)),
      );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(
      {required this.icon,
      required this.color,
      required this.onTap,
      this.size = 22});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, color: color, size: size)),
      );
}

class _ScrollFab extends StatelessWidget {
  const _ScrollFab(
      {required this.onTap, required this.palette, required this.theme});
  final VoidCallback onTap;
  final ThemePalette palette;
  final ThemeProvider theme;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: palette.surface,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 8)]),
            child: Icon(Icons.keyboard_arrow_down_rounded,
                color: palette.textSecondary, size: 22)),
      );
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date, required this.palette});
  final DateTime date;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (_same(date, now))
      label = 'Hôm nay';
    else if (_same(date, now.subtract(const Duration(days: 1))))
      label = 'Hôm qua';
    else
      label = DateFormat('dd/MM/yyyy').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        Expanded(child: Divider(color: palette.divider, height: 1)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: palette.surfaceVariant,
                    borderRadius: BorderRadius.circular(999)),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: palette.textHint,
                        fontWeight: FontWeight.w600)))),
        Expanded(child: Divider(color: palette.divider, height: 1)),
      ]),
    );
  }

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder(
      {required this.isLoading,
      required this.palette,
      required this.primary,
      this.progress});
  final bool isLoading;
  final ThemePalette palette;
  final Color primary;
  final double? progress;

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: palette.surfaceVariant,
      child: Center(
          child: isLoading
              ? CircularProgressIndicator(
                  value: progress, color: primary, strokeWidth: 2.5)
              : Icon(Icons.broken_image_rounded,
                  color: palette.textHint, size: 32)));
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

class _StickerItem extends StatelessWidget {
  const _StickerItem({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.all(6),
          child: Image.asset('images/$name.gif',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.error, size: 40))));
}

class _ScamWarning extends StatelessWidget {
  const _ScamWarning({required this.reason, required this.palette});
  final String reason;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: palette.dangerColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: palette.dangerColor.withValues(alpha: 0.3))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_rounded, color: palette.dangerColor, size: 14),
          const SizedBox(width: 6),
          Expanded(
              child: Text('CẢNH BÁO AI: $reason',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: palette.dangerColor,
                      fontWeight: FontWeight.w600))),
        ]),
      );
}

class _ReminderHint extends StatelessWidget {
  const _ReminderHint({required this.onView, required this.palette});
  final VoidCallback onView;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
            color: palette.infoColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.alarm_add_rounded, color: palette.infoColor, size: 13),
          const SizedBox(width: 6),
          Text('AI: Phát hiện công việc cần nhắc!',
              style: TextStyle(fontSize: 11, color: palette.infoColor)),
          const SizedBox(width: 8),
          GestureDetector(
              onTap: onView,
              child: Text('XEM',
                  style: TextStyle(
                      fontSize: 11,
                      color: palette.infoColor,
                      fontWeight: FontWeight.w700))),
        ]),
      );
}

class _LocationContent extends StatelessWidget {
  const _LocationContent(
      {required this.location,
      required this.isMe,
      required this.palette,
      required this.theme,
      required this.onOpen});
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
              color: isMe ? Colors.white : palette.dangerColor, size: 17),
          const SizedBox(width: 4),
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
                      ? Colors.white.withValues(alpha: 0.18)
                      : palette.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.3)
                          : theme.primaryColor.withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.map_rounded,
                    size: 13, color: isMe ? Colors.white : theme.primaryColor),
                const SizedBox(width: 4),
                Text('Xem trên Maps',
                    style: TextStyle(
                        fontSize: 12,
                        color: isMe ? Colors.white : theme.primaryColor,
                        fontWeight: FontWeight.w600)),
              ]),
            )),
      ]);
}

class _ScamScanWidget extends StatelessWidget {
  const _ScamScanWidget(
      {required this.msgId,
      required this.content,
      required this.result,
      required this.onScan,
      required this.palette});
  final String msgId, content;
  final dynamic result;
  final void Function(String) onScan;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    if (result != null && result != 'SAFE')
      return ScamWarningWidget(status: result as String);
    if (result == null) {
      return GestureDetector(
        onTap: () async {
          Fluttertoast.showToast(msg: 'AI đang quét...');
          final scamLevel = await AIBackendService().checkScam(content);
          final statusString = scamLevel.name.toUpperCase();
          onScan(statusString);
          if (statusString == 'SAFE') {
            Fluttertoast.showToast(
                msg: '✅ Tin nhắn an toàn',
                backgroundColor: palette.successColor);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: palette.successColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: palette.successColor.withValues(alpha: 0.3),
                  width: 0.8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shield_outlined, size: 13, color: palette.successColor),
            const SizedBox(width: 4),
            Text('Quét AI',
                style: TextStyle(
                    fontSize: 11,
                    color: palette.successColor,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow(
      {required this.groupChatId,
      required this.msgId,
      required this.currentUserId,
      required this.isMe,
      required this.provider,
      required this.onTap});
  final String groupChatId, msgId, currentUserId;
  final bool isMe;
  final ReactionProvider provider;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
        stream: provider.getReactions(groupChatId, msgId),
        builder: (_, snap) {
          if (!snap.hasData || snap.data!.docs.isEmpty)
            return const SizedBox.shrink();
          final reactions = <String, int>{};
          final myReactions = <String, bool>{};
          for (final doc in snap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final emoji = d['emoji'] as String, uid = d['userId'] as String;
            reactions[emoji] = (reactions[emoji] ?? 0) + 1;
            if (uid == currentUserId) myReactions[emoji] = true;
          }
          return Padding(
              padding: const EdgeInsets.only(top: 3),
              child: MessageReactionsDisplay(
                  reactions: reactions,
                  currentUserId: currentUserId,
                  userReactions: myReactions,
                  onReactionTap: onTap));
        },
      );
}

class _ThemedDialog extends StatelessWidget {
  const _ThemedDialog(
      {required this.title,
      required this.icon,
      required this.iconColor,
      required this.content,
      required this.actions,
      required this.palette});
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
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.1),
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
                  const SizedBox(height: 20),
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
  const _ThemedDialogAction(
      {required this.label,
      required this.onTap,
      required this.palette,
      required this.primary,
      this.isPrimary = false,
      this.isDanger = false});
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
    if (isDanger)
      return TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(foregroundColor: palette.dangerColor),
          child: Text(label));
    return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
        child: Text(label));
  }
}

class _LockOptionsSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.read<ThemeProvider>().palette;
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: p.divider, borderRadius: BorderRadius.circular(999))),
        ListTile(
            leading: Icon(Icons.lock_outline_rounded,
                color: context.read<ThemeProvider>().primaryColor),
            title: Text('Đặt mã PIN', style: TextStyle(color: p.textPrimary)),
            onTap: () => Navigator.pop(context, 'set_pin')),
        ListTile(
            leading: Icon(Icons.lock_open_rounded, color: p.dangerColor),
            title: Text('Xoá khoá', style: TextStyle(color: p.dangerColor)),
            onTap: () => Navigator.pop(context, 'remove')),
        ListTile(
            leading: Icon(Icons.close_rounded, color: p.textHint),
            title: Text('Huỷ', style: TextStyle(color: p.textPrimary)),
            onTap: () => Navigator.pop(context)),
      ]),
    );
  }
}

class _ReminderPickerDialog extends StatefulWidget {
  @override
  State<_ReminderPickerDialog> createState() => _ReminderPickerDialogState();
}

class _ReminderPickerDialogState extends State<_ReminderPickerDialog> {
  DateTime _selected = DateTime.now().add(const Duration(hours: 1));

  @override
  Widget build(BuildContext context) {
    final p = context.read<ThemeProvider>().palette;
    final primary = context.read<ThemeProvider>().primaryColor;
    return _ThemedDialog(
      title: 'Đặt Nhắc Nhở',
      icon: Icons.alarm_add_rounded,
      iconColor: primary,
      palette: p,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _PickerTile(
            icon: Icons.calendar_today_rounded,
            label: 'Ngày',
            value: DateFormat('dd/MM/yyyy').format(_selected),
            palette: p,
            primary: primary,
            onTap: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: _selected,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d != null && mounted)
                setState(() => _selected = DateTime(
                    d.year, d.month, d.day, _selected.hour, _selected.minute));
            }),
        const SizedBox(height: 8),
        _PickerTile(
            icon: Icons.access_time_rounded,
            label: 'Giờ',
            value: DateFormat('HH:mm').format(_selected),
            palette: p,
            primary: primary,
            onTap: () async {
              final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_selected));
              if (t != null && mounted)
                setState(() => _selected = DateTime(_selected.year,
                    _selected.month, _selected.day, t.hour, t.minute));
            }),
      ]),
      actions: [
        _ThemedDialogAction(
            label: 'Đặt nhắc',
            isPrimary: true,
            palette: p,
            primary: primary,
            onTap: () => Navigator.pop(context, _selected)),
        _ThemedDialogAction(
            label: 'Huỷ',
            palette: p,
            primary: primary,
            onTap: () => Navigator.pop(context)),
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onTap,
      required this.palette,
      required this.primary});
  final IconData icon;
  final String label, value;
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
            ])),
      );
}

class _RemindersPage extends StatelessWidget {
  const _RemindersPage(
      {required this.currentUserId, required this.reminderProvider});
  final String currentUserId;
  final ReminderProvider reminderProvider;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
            title: Text('Nhắc nhở',
                style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17)),
            backgroundColor: p.appBarBackground,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: theme.primaryColor),
              onPressed: () => Navigator.pop(context),
            )),
        body: StreamBuilder<List<MessageReminder>>(
          stream: reminderProvider.getUserRemindersStream(currentUserId),
          builder: (_, snap) {
            if (!snap.hasData)
              return Center(
                  child: CircularProgressIndicator(
                      color: theme.primaryColor, strokeWidth: 2));
            final reminders = snap.data!;
            if (reminders.isEmpty)
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.alarm_off_rounded, size: 60, color: p.textHint),
                const SizedBox(height: 14),
                Text('Chưa có nhắc nhở',
                    style: TextStyle(
                        color: p.textSecondary, fontWeight: FontWeight.w500)),
              ]));
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reminders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = reminders[i];
                return Container(
                  decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: p.shadow, blurRadius: 8)]),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.alarm_rounded,
                            color: theme.primaryColor)),
                    title: Text(r.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    subtitle: Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(r.reminderTime),
                        style: TextStyle(fontSize: 11, color: p.textHint)),
                    trailing: GestureDetector(
                        onTap: () => reminderProvider.deleteReminder(r.id),
                        child: Icon(Icons.delete_outline_rounded,
                            color: p.dangerColor)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AIDialog extends StatelessWidget {
  const _AIDialog(
      {required this.messages, required this.palette, required this.primary});
  final List<String> messages;
  final ThemePalette palette;
  final Color primary;

  @override
  Widget build(BuildContext context) => _ThemedDialog(
        title: 'AI Phân Tích',
        icon: Icons.auto_awesome_rounded,
        iconColor: const Color(0xFF8B5CF6),
        palette: palette,
        content: FutureBuilder<String?>(
          future: AIBackendService()
              .analyzeChatContext(messages, 'work', 'extract_tasks'),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                  height: 100,
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF8B5CF6), strokeWidth: 2)));
            }
            if (!snap.hasData) {
              return Text('Không thể kết nối AI lúc này.',
                  style: TextStyle(color: palette.textSecondary));
            }
            return SizedBox(
                height: 280,
                child: SingleChildScrollView(
                  child: MarkdownBody(
                      data: snap.data!,
                      styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                              color: palette.textPrimary, height: 1.6))),
                ));
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

class _FeatureItem {
  const _FeatureItem(this.icon, this.label, this.onTap, this.color);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
}

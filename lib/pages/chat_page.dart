// ignore_for_file: use_build_context_synchronously

import 'dart:async';
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

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _T {
  // Background
  static const bg = Color(0xFFF6F7FB);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF0F1F7);

  // Brand
  static const primary = Color(0xFF5A67D8);
  static const primaryLight = Color(0xFFEEF0FD);
  static const primaryDark = Color(0xFF4254C7);
  static const primaryGlow = Color(0x265A67D8);

  // Bubbles
  static const bubbleMe = Color(0xFF5A67D8);
  static const bubblePeer = Colors.white;
  static const bubbleMeText = Colors.white;
  static const bubblePeerText = Color(0xFF1A1D2E);

  // Text
  static const textPrimary = Color(0xFF1A1D2E);
  static const textSecondary = Color(0xFF6B7280);
  static const textMuted = Color(0xFFB0B7C3);

  // Status
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF3B82F6);

  // Borders
  static const border = Color(0xFFE8EAF0);
  static const borderLight = Color(0xFFF3F4F8);

  // Shadows
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get shadowPrimary => [
        BoxShadow(
          color: primary.withOpacity(0.35),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  // Radii
  static const r4 = Radius.circular(4);
  static const r8 = Radius.circular(8);
  static const r10 = Radius.circular(10);
  static const r12 = Radius.circular(12);
  static const r14 = Radius.circular(14);
  static const r16 = Radius.circular(16);
  static const r20 = Radius.circular(20);
  static const r24 = Radius.circular(24);
  static const r28 = Radius.circular(28);
  static const rFull = Radius.circular(999);

  // Typography
  static const fontDisplay = TextStyle(
    fontFamily: 'SF Pro Display',
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.4,
  );

  static const fontBody = TextStyle(
    fontFamily: 'SF Pro Text',
    fontSize: 15,
    color: textPrimary,
    height: 1.45,
  );

  static const fontCaption = TextStyle(
    fontSize: 11,
    color: textMuted,
    letterSpacing: 0.1,
  );

  // Durations
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 400);
}

// ─────────────────────────────────────────────────────────────────────────────
// ARGUMENTS
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// CHAT PAGE
// ─────────────────────────────────────────────────────────────────────────────

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
  // ── Identity ────────────────────────────────────────────────────────────────
  late final String _currentUserId;
  String _groupChatId = '';

  // ── Controllers ─────────────────────────────────────────────────────────────
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  late final FocusNode _focusNode;

  // ── Animation Controllers ────────────────────────────────────────────────────
  late final AnimationController _sendBtnAnim;
  late final AnimationController _fabAnim;
  late final AnimationController _menuAnim;
  late final AnimationController _replyAnim;
  late final AnimationController _appBarAnim;

  // ── Platform Channels ───────────────────────────────────────────────────────
  static const _miniChatChannel = MethodChannel('mini_chat_channel');
  static const _bubbleChannel = MethodChannel('bubble_chat_channel');

  // ── Providers ───────────────────────────────────────────────────────────────
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

  // ── Pagination ──────────────────────────────────────────────────────────────
  int _limit = 30;
  final int _limitIncrement = 20;

  // ── UI State ────────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _isShowSticker = false;
  bool _isLoadingMedia = false;
  bool _isTyping = false;
  bool _showMenu = false;
  bool _isRecording = false;
  bool _showScrollToBottom = false;
  bool _lockChecked = false;
  bool _isProcessingMsg = false;

  // ── Recording ───────────────────────────────────────────────────────────────
  String _recDuration = '0:00';
  int _recSeconds = 0;
  Timer? _recTimer;

  // ── Message State ───────────────────────────────────────────────────────────
  List<DocumentSnapshot> _pinned = [];
  List<SmartReply> _smartReplies = [];
  MessageChat? _replyingTo;
  String? _pendingScrollId;

  final Set<String> _processedIds = {};
  final Map<String, Timer> _scheduled = {};
  final Map<String, String> _scheduledContent = {};
  final Map<String, dynamic> _scamResults = {};

  final ImagePicker _picker = ImagePicker();

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _focusNode = FocusNode();

    _sendBtnAnim = AnimationController(
      vsync: this,
      duration: _T.fast,
    );
    _fabAnim = AnimationController(
      vsync: this,
      duration: _T.normal,
    );
    _menuAnim = AnimationController(
      vsync: this,
      duration: _T.normal,
    );
    _replyAnim = AnimationController(
      vsync: this,
      duration: _T.normal,
    );
    _appBarAnim = AnimationController(
      vsync: this,
      duration: _T.slow,
    )..forward();

    // Register with resource manager
    resourceManager
      ..addAnimationController(_sendBtnAnim)
      ..addAnimationController(_fabAnim)
      ..addAnimationController(_menuAnim)
      ..addAnimationController(_replyAnim)
      ..addAnimationController(_appBarAnim)
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
            isTyping: false,
          );
      }
    } catch (_) {}
    try {
      _voiceProvider?.dispose();
    } catch (_) {}
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INITIALIZATION
  // ─────────────────────────────────────────────────────────────────────────

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

    PushNotificationService.initialize().catchError((e) {
      debugPrint('⚠️ PushNotification: $e');
    });

    final sub = _bubbleService?.bubbleClickStream.listen((event) {
      if (event.userId == widget.arguments.peerId && mounted) {
        _toast('📨 ${widget.arguments.peerNickname}: ${event.message}',
            isSuccess: true);
      }
    });
    if (sub != null) resourceManager.addSubscription(sub);

    try {
      _voiceProvider = VoiceMessageProvider(
        firebaseStorage: _chatProvider.firebaseStorage,
      );
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
        MaterialPageRoute(builder: (_) => LoginPage()),
        (_) => false,
      );
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

    resourceManager.addDelayedTimer(
      const Duration(milliseconds: 500),
      () {
        if (!resourceManager.isDisposed && mounted) {
          _markRead();
          _loadSmartReplies();
        }
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SCROLL
  // ─────────────────────────────────────────────────────────────────────────

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
    _scrollController.animateTo(
      0,
      duration: _T.slow,
      curve: Curves.easeOutCubic,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INPUT HANDLERS
  // ─────────────────────────────────────────────────────────────────────────

  void _onInputChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    if (hasText) {
      _sendBtnAnim.forward();
    } else {
      _sendBtnAnim.reverse();
    }
  }

  void _onFocusChange() {
    if (resourceManager.isDisposed || !mounted) return;
    if (_focusNode.hasFocus) {
      if (mounted) {
        setState(() {
          _isShowSticker = false;
          _showMenu = false;
        });
      }
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

    resourceManager.addDelayedTimer(
      const Duration(seconds: 3),
      () {
        if (!resourceManager.isDisposed) {
          _isTyping = false;
          _presenceProvider?.setTypingStatus(
            conversationId: _groupChatId,
            userId: _currentUserId,
            isTyping: false,
          );
        }
      },
    );
  }

  void _showElderModeSuggestion() {
    if (resourceManager.isDisposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.accessibility_new_rounded,
                color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Gặp khó khi gõ? Thử giao diện lớn hơn nhé!',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 8),
        backgroundColor: _T.textPrimary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(_T.r16)),
        action: SnackBarAction(
          label: 'BẬT',
          textColor: _T.warning,
          onPressed: () {
            try {
              context.read<AppModeProvider>().setMode(AppMode.elder);
            } catch (_) {}
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PINNED MESSAGES
  // ─────────────────────────────────────────────────────────────────────────

  void _loadPinned() {
    if (resourceManager.isDisposed) return;
    final sub = _messageProvider.getPinnedMessages(_groupChatId).listen(
      (snap) {
        if (!mounted || resourceManager.isDisposed) return;
        setState(() => _pinned = snap.docs);
      },
      onError: (e) => ErrorLogger.logError(e, null, context: 'LoadPinned'),
    );
    resourceManager.addSubscription(sub);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INCOMING MESSAGE LISTENER
  // ─────────────────────────────────────────────────────────────────────────

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
        .listen(
      (snap) async {
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
      },
      onError: (_) => _isProcessingMsg = false,
    );
    resourceManager.addSubscription(sub);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MARK READ
  // ─────────────────────────────────────────────────────────────────────────

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
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      _presenceProvider?.markMessagesAsRead(
        conversationId: _groupChatId,
        userId: _currentUserId,
      );
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'MarkRead');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEND MESSAGE
  // ─────────────────────────────────────────────────────────────────────────

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
      await _chatProvider.sendMessage(
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
        conversationId: _groupChatId,
      );
    } catch (_) {}

    if (!resourceManager.isDisposed) _loadSmartReplies();

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: _T.normal,
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUBBLE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _updateBubble(
    String content,
    int type, {
    required bool fromUser,
  }) async {
    if (_bubbleService == null || resourceManager.isDisposed) return;
    if (!_bubbleService!.isBubbleActive(widget.arguments.peerId)) return;

    String msgType = 'text';
    String display = content;
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
        display = '🎤 Tin nhắn thoại';
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
        messageType: msgType,
      );
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
        avatarUrl: widget.arguments.peerAvatar,
      );
    }
  }

  Future<void> _createBubble() async {
    if (_bubbleService == null) return;
    if (!_bubbleService!.isSupported) {
      _toast('Thiết bị không hỗ trợ chat bubble');
      return;
    }
    final hasPermission = await _bubbleService!.hasOverlayPermission();
    if (!hasPermission) {
      final granted = await _bubbleService!.requestOverlayPermission();
      if (!granted) {
        _toast('Cần quyền hiển thị trên màn hình');
        return;
      }
    }

    final choice = await _showBubbleChoiceDialog();
    if (choice == null) return;

    if (choice == 'bubble') {
      final ok = await _bubbleService!.showChatBubble(
        userId: widget.arguments.peerId,
        userName: widget.arguments.peerNickname,
        avatarUrl: widget.arguments.peerAvatar,
      );
      _toast(ok ? '💬 Chat bubble đã tạo' : '❌ Không thể tạo bubble',
          isSuccess: ok);
    } else if (choice == 'minichat') {
      final ok = await _bubbleService!.showMiniChat(
        userId: widget.arguments.peerId,
        userName: widget.arguments.peerNickname,
        avatarUrl: widget.arguments.peerAvatar,
      );
      _toast(ok ? '💬 Mini chat đã mở' : '⚠️ Không hỗ trợ', isSuccess: ok);
    }
  }

  Future<String?> _showBubbleChoiceDialog() => showDialog<String>(
        context: context,
        builder: (ctx) => _ChatDialog(
          title: 'Tạo Chat Bubble',
          icon: Icons.bubble_chart_rounded,
          iconColor: _T.primary,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chọn cách hiển thị cuộc trò chuyện:',
                style: _T.fontBody.copyWith(color: _T.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                _bubbleService!.implementationInfo,
                style: _T.fontCaption,
              ),
            ],
          ),
          actions: [
            _ChatDialogAction(
              label: 'Chỉ Bubble',
              isPrimary: true,
              onTap: () => Navigator.pop(ctx, 'bubble'),
            ),
            if (_bubbleService!.currentImplementation ==
                BubbleImplementation.windowManager)
              _ChatDialogAction(
                label: 'Mini Chat',
                onTap: () => Navigator.pop(ctx, 'minichat'),
              ),
            _ChatDialogAction(
              label: 'Huỷ',
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // MEDIA
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    try {
      final f = await _picker.pickImage(source: ImageSource.gallery);
      if (f != null) await _sendMedia(File(f.path), isVideo: false);
    } catch (e) {
      _toast('Không thể chọn ảnh');
    }
  }

  Future<void> _pickVideo() async {
    HapticFeedback.lightImpact();
    try {
      final f = await _picker.pickVideo(source: ImageSource.gallery);
      if (f != null) await _sendMedia(File(f.path), isVideo: true);
    } catch (e) {
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
      icon: isVideo ? Icons.videocam_rounded : Icons.image_rounded,
    );
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
        },
      );
      if (!mounted || resourceManager.isDisposed) return;
      _toast(
        ok != false
            ? (isVideo ? '🎬 Video đã gửi' : '📷 Ảnh đã gửi')
            : 'Không thể gửi ${isVideo ? 'video' : 'ảnh'}',
        isSuccess: ok != false,
      );
      if (ok != false && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: _T.normal,
          curve: Curves.easeOutCubic,
        );
      }
    } catch (e) {
      ErrorLogger.logError(e, null, context: 'SendMedia');
      _toast('Lỗi gửi media');
    } finally {
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _isLoadingMedia = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STICKER
  // ─────────────────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────────────────
  // VOICE
  // ─────────────────────────────────────────────────────────────────────────

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
          final m = _recSeconds ~/ 60;
          final s = _recSeconds % 60;
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
      _toast('Gửi tin nhắn thoại thất bại');
    }
  }

  Future<void> _cancelRec() async {
    _recTimer?.cancel();
    await _voiceProvider?.cancelRecording();
    if (mounted) setState(() => _isRecording = false);
    HapticFeedback.heavyImpact();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOCATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _shareLocation() async {
    if (_locationProvider == null) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final ok = await _locationProvider!.requestLocationPermission();
      if (!ok) {
        _toast('📍 Cần quyền truy cập vị trí');
        return;
      }
      final data = await _locationProvider!.getCurrentLocationWithDetails();
      if (data != null && !resourceManager.isDisposed) {
        await _onSend(
          _locationProvider!.formatLocationMessage(data),
          TypeMessage.text,
        );
        _toast('📍 Đã chia sẻ vị trí', isSuccess: true);
      }
    } catch (_) {
      _toast('❌ Lỗi lấy vị trí');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openMaps(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SCHEDULE MESSAGE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _scheduleMessage() async {
    if (resourceManager.isDisposed) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScheduleMessageDialog(),
    );
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
    _toast(
      '📅 Đã lên lịch lúc ${DateFormat('HH:mm dd/MM').format(time)}',
      isSuccess: true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SMART REPLIES
  // ─────────────────────────────────────────────────────────────────────────

  void _loadSmartReplies() {
    if (resourceManager.isDisposed) return;
    final msgs = LocalDbService().getMessages(_groupChatId);
    if (msgs.isEmpty) return;
    final last = msgs.first;
    if (last['idFrom'] != _currentUserId && last['type'] == TypeMessage.text) {
      final text = last['content'] as String? ?? '';
      final replies = _smartReplyProvider.getRuleBasedReplies(text);
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _smartReplies = replies);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MESSAGE OPTIONS
  // ─────────────────────────────────────────────────────────────────────────

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
    if (resourceManager.isDisposed) return;
    showDialog(
      context: context,
      builder: (_) => EditMessageDialog(
        originalContent: current,
        onSave: (newContent) async {
          final ok =
              await _messageProvider.editMessage(_groupChatId, id, newContent);
          if (ok) _toast('Đã chỉnh sửa', isSuccess: true);
        },
      ),
    );
  }

  Future<void> _deleteMsg(String id) async {
    final ok = await _confirm(
      title: 'Xoá tin nhắn',
      message: 'Bạn có chắc muốn xóa tin nhắn này?',
      confirmLabel: 'Xoá',
      icon: Icons.delete_rounded,
      isDanger: true,
    );
    if (ok == true && !resourceManager.isDisposed) {
      final res = await _messageProvider.deleteMessage(_groupChatId, id);
      if (res) _toast('Đã xoá', isSuccess: true);
    }
  }

  Future<void> _pinMsg(String id, bool isPinned) async {
    final ok =
        await _messageProvider.togglePinMessage(_groupChatId, id, isPinned);
    if (ok) {
      _toast(isPinned ? 'Đã bỏ ghim' : '📌 Đã ghim', isSuccess: true);
    }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(_T.r24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: ReactionPicker(
          onEmojiSelected: (emoji) {
            _reactionProvider.toggleReaction(
              _groupChatId,
              msgId,
              _currentUserId,
              emoji,
            );
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REMINDER
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _setReminder(MessageChat msg, String msgId) async {
    final time = await _pickReminderTime();
    if (time == null || resourceManager.isDisposed) return;
    final reminder = await _reminderProvider.scheduleReminder(
      userId: _currentUserId,
      messageId: msgId,
      conversationId: _groupChatId,
      reminderTime: time,
      message: msg.content,
    );
    final ok = reminder != null;
    _toast(ok ? '⏰ Đã đặt nhắc nhở' : 'Không thể đặt nhắc nhở', isSuccess: ok);
  }

  Future<DateTime?> _pickReminderTime() => showDialog<DateTime>(
        context: context,
        builder: (_) => _ReminderPickerDialog(),
      );

  void _showReminders() {
    if (resourceManager.isDisposed) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RemindersPage(
          currentUserId: _currentUserId,
          reminderProvider: _reminderProvider,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRANSLATE
  // ─────────────────────────────────────────────────────────────────────────

  void _translate(String content) {
    showDialog(
      context: context,
      builder: (_) => TranslationDialog(originalMessage: content),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOCK
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkLock() async {
    if (resourceManager.isDisposed) return;
    final status = await _lockProvider.getConversationLockStatus(_groupChatId);
    if (status != null && status.isLocked) {
      if (!mounted || resourceManager.isDisposed) return;
      final ok = await _showPinVerify();
      if (ok != true && mounted) Navigator.pop(context);
    }
    if (mounted && !resourceManager.isDisposed) {
      setState(() => _lockChecked = true);
    }
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
          remainingAttempts: remaining,
        ),
      );
      if (pin == null || resourceManager.isDisposed) return false;
      final result = await _lockProvider.verifyPIN(
        conversationId: _groupChatId,
        enteredPin: pin,
      );
      if (result.success) return true;
      remaining = 5 - result.failedAttempts;
      errorMsg = result.message;
      if (remaining <= 0 || result.locked) {
        await _lockProvider.autoDeleteMessagesAfterFailedAttempts(
            conversationId: _groupChatId);
        _toast('Đã xóa tin nhắn do vi phạm bảo mật', isSuccess: false);
        return false;
      }
    }
    return false;
  }

  void _showLockOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LockOptionsSheet(),
    );
    if (action == 'set_pin' && !resourceManager.isDisposed) {
      _setPin();
    } else if (action == 'remove' && !resourceManager.isDisposed) {
      await _lockProvider.removeConversationLock(_groupChatId);
      _toast('Đã xóa khoá', isSuccess: true);
    }
  }

  void _setPin() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => PINInputDialog(
        title: 'Đặt Mã PIN Mới',
        onComplete: (p) => Navigator.pop(context, p),
      ),
    );
    if (pin == null) return;
    final confirm = await showDialog<String>(
      context: context,
      builder: (_) => PINInputDialog(
        title: 'Xác Nhận PIN',
        onComplete: (p) => Navigator.pop(context, p),
      ),
    );
    if (confirm == pin && !resourceManager.isDisposed) {
      final ok = await _lockProvider.setConversationPIN(
        conversationId: _groupChatId,
        pin: pin,
      );
      _toast(ok ? 'Đã đặt mã PIN' : 'Lỗi đặt PIN', isSuccess: ok);
    } else if (confirm != null) {
      _toast('PIN không khớp');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AI ANALYSIS
  // ─────────────────────────────────────────────────────────────────────────

  void _showAI() {
    final msgs = LocalDbService().getMessages(_groupChatId);
    if (msgs.isEmpty) {
      _toast('Chưa có đủ tin nhắn để phân tích');
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChatDialog(
        title: 'AI Phân Tích',
        icon: Icons.auto_awesome_rounded,
        iconColor: const Color(0xFF8B5CF6),
        content: FutureBuilder<String?>(
          future: AIBackendService()
              .analyzeChatContext(recent, 'work', 'extract_tasks'),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF8B5CF6), strokeWidth: 2),
                ),
              );
            }
            if (!snap.hasData) {
              return Text('Không thể kết nối AI lúc này.',
                  style: _T.fontBody.copyWith(color: _T.textSecondary));
            }
            return SizedBox(
              height: 280,
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: snap.data!,
                  styleSheet: MarkdownStyleSheet(
                    p: _T.fontBody.copyWith(height: 1.6),
                  ),
                ),
              ),
            );
          },
        ),
        actions: [
          _ChatDialogAction(
            label: 'Đóng',
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEARCH
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _openSearch() async {
    if (resourceManager.isDisposed) return;
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SearchMessagesPage(
          groupChatId: _groupChatId,
          peerName: widget.arguments.peerNickname,
          peerId: widget.arguments.peerId,
        ),
      ),
    );
    if (id != null && mounted && !resourceManager.isDisposed) {
      setState(() => _pendingScrollId = id);
      resourceManager.addDelayedTimer(
        const Duration(milliseconds: 400),
        () {
          if (!mounted || resourceManager.isDisposed) return;
          _scrollToMsg(id);
        },
      );
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
          const Duration(milliseconds: 500),
          () => _scrollToMsg(id),
        );
      }
      return;
    }
    final offset =
        (idx * 76.0).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      offset,
      duration: _T.slow,
      curve: Curves.easeInOut,
    );
    if (mounted) setState(() => _pendingScrollId = null);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BACK & NAVIGATION
  // ─────────────────────────────────────────────────────────────────────────

  void _onBack() {
    if (_isShowSticker || _showMenu) {
      if (mounted) {
        setState(() {
          _isShowSticker = false;
          _showMenu = false;
        });
        _menuAnim.reverse();
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

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  void _toast(String msg, {bool isSuccess = false}) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: isSuccess ? _T.success : _T.textPrimary,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    IconData? icon,
    bool isDanger = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => _ChatDialog(
          title: title,
          icon: icon ?? Icons.help_outline_rounded,
          iconColor: isDanger ? _T.danger : _T.primary,
          content: Text(message,
              style: _T.fontBody.copyWith(color: _T.textSecondary)),
          actions: [
            _ChatDialogAction(
              label: confirmLabel,
              isPrimary: !isDanger,
              isDanger: isDanger,
              onTap: () => Navigator.pop(ctx, true),
            ),
            _ChatDialogAction(
              label: 'Huỷ',
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      );

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmtTimestamp(String ts) {
    final ms = int.tryParse(ts) ?? 0;
    if (ms == 0) return '';
    return DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.isBubbleMode) return _buildBubbleMode();
    if (widget.isMiniChat) return _buildMiniMode();
    return _buildFullMode();
  }

  Widget _buildBubbleMode() => Scaffold(
        backgroundColor: _T.bg,
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
            ),
            Expanded(child: _buildBody()),
          ]),
        ),
      );

  Widget _buildMiniMode() => Scaffold(
        backgroundColor: _T.bg,
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
            ),
            Expanded(child: _buildBody()),
          ]),
        ),
      );

  Widget _buildFullMode() {
    return Scaffold(
      backgroundColor: _T.bg,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (d, _) {
            if (!d) _onBack();
          },
          child: _buildBody(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: FadeTransition(
          opacity: _appBarAnim,
          child: Container(
            decoration: BoxDecoration(
              color: _T.surface,
              boxShadow: _T.shadowSm,
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leadingWidth: widget.isWebMode ? 0 : 48,
              leading: widget.isWebMode
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                      ),
                      color: _T.primary,
                      onPressed: _onBack,
                    ),
              title: _AppBarTitle(
                peerId: widget.arguments.peerId,
                peerNickname: widget.arguments.peerNickname,
                peerAvatar: widget.arguments.peerAvatar,
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
                          userChat: UserChat.fromDocument(doc),
                        ),
                      ),
                    );
                  }
                },
              ),
              actions: [
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
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'ai':
                        _showAI();
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
                    }
                  },
                  icon: const Icon(Icons.more_vert_rounded, size: 22),
                  color: _T.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(_T.r16),
                  ),
                  itemBuilder: (_) => [
                    _popItem('ai', Icons.auto_awesome_rounded, 'AI Assistant',
                        const Color(0xFF8B5CF6)),
                    _popItem(
                        'search', Icons.search_rounded, 'Tìm kiếm', _T.primary),
                    _popItem('reminders', Icons.alarm_rounded, 'Nhắc nhở',
                        _T.warning),
                    const PopupMenuDivider(),
                    _popItem('lock', Icons.lock_rounded, 'Khoá chat', _T.info),
                    _popItem('bubble', Icons.bubble_chart_rounded,
                        'Chat Bubble', _T.success),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      );

  PopupMenuItem<String> _popItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.all(_T.r8),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 10),
            Text(label,
                style: _T.fontBody.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // BODY
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    return Stack(
      children: [
        // Chat background
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(color: _T.bg),
          ),
        ),
        Column(
          children: [
            const OfflineIndicator(),
            _buildPinnedBar(),
            _buildMsgList(),
            _buildTypingBar(),
            if (_isShowSticker && !widget.isMiniChat && !widget.isBubbleMode)
              _buildStickerPanel(),
            if (_showMenu && !widget.isMiniChat && !widget.isBubbleMode)
              _buildFeatureMenu(),
            _buildInput(),
          ],
        ),
        if (_isLoading) const Positioned.fill(child: LoadingView()),
        if (_isLoadingMedia) Positioned.fill(child: _buildMediaOverlay()),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PINNED BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPinnedBar() {
    if (_pinned.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: _T.surface,
        border: Border(bottom: BorderSide(color: _T.border)),
      ),
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
              color: _T.primaryLight,
              borderRadius: BorderRadius.all(_T.rFull),
              border:
                  Border.all(color: _T.primary.withOpacity(0.25), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.push_pin_rounded, size: 12, color: _T.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    msg.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: _T.primary,
                      fontWeight: FontWeight.w600,
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

  // ─────────────────────────────────────────────────────────────────────────
  // MESSAGE LIST
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMsgList() {
    return Flexible(
      child: _groupChatId.isNotEmpty
          ? ValueListenableBuilder(
              valueListenable: LocalDbService().messagesBox.listenable(),
              builder: (_, Box box, __) {
                final all = LocalDbService().getMessages(_groupChatId);
                final display = all.take(_limit).toList();

                if (display.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: _T.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 36,
                            color: _T.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Bắt đầu cuộc trò chuyện',
                          style: _T.fontBody.copyWith(
                              color: _T.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Hãy gửi tin nhắn đầu tiên! 👋',
                          style: _T.fontCaption,
                        ),
                      ],
                    ),
                  );
                }

                return Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      itemCount: display.length,
                      itemBuilder: (_, i) =>
                          _buildMsgItem(i, display[i], display),
                    ),
                    // Scroll to bottom FAB
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: ScaleTransition(
                        scale: CurvedAnimation(
                          parent: _fabAnim,
                          curve: Curves.elasticOut,
                        ),
                        child: _ScrollFab(onTap: _scrollToBottom),
                      ),
                    ),
                  ],
                );
              },
            )
          : const Center(
              child: CircularProgressIndicator(
                color: _T.primary,
                strokeWidth: 2,
              ),
            ),
    );
  }

  Widget _buildMsgItem(
    int index,
    Map<dynamic, dynamic> data,
    List<Map<dynamic, dynamic>> full,
  ) {
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
    if (index > 0) {
      isLastInGroup = full[index - 1]['idFrom'] != msg.idFrom;
    }

    Widget? sep;
    if (index == full.length - 1 ||
        !_sameDay(
          DateTime.fromMillisecondsSinceEpoch(int.tryParse(msg.timestamp) ?? 0),
          DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(full[index + 1]['timestamp'] ?? '0') ?? 0),
        )) {
      sep = _DateDivider(
        date: DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(msg.timestamp) ?? 0),
      );
    }

    final bubble = _buildBubble(
      msgId: data['messageId'] ?? '',
      msg: msg,
      data: data,
      isLastInGroup: isLastInGroup,
      isHighlighted: isHighlighted,
      isPending: isPending,
    );

    return Column(
      children: [
        SwipeToReplyWrapper(
          isMe: msg.idFrom == _currentUserId,
          onSwipe: () => _setReply(msg),
          child: bubble,
        ),
        if (sep != null) sep,
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUBBLE BUILDER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBubble({
    required String msgId,
    required MessageChat msg,
    required Map<dynamic, dynamic> data,
    required bool isLastInGroup,
    bool isHighlighted = false,
    bool isPending = false,
  }) {
    final isMe = msg.idFrom == _currentUserId;
    final isViewOnce = data['isViewOnce'] ?? false;
    final isScam = data['scamWarning'] ?? false;
    final scamReason = data['scamReason'] ?? '';
    final hasReminder = data['hasReminder'] ?? false;

    Widget wrap(Widget child) {
      if (!isHighlighted) return child;
      return AnimatedContainer(
        duration: _T.slow,
        decoration: BoxDecoration(
          color: _T.primary.withOpacity(0.06),
          borderRadius: BorderRadius.all(_T.r16),
        ),
        child: child,
      );
    }

    // View Once
    if (isViewOnce) {
      return wrap(_BubbleRow(
        isMe: isMe,
        margin: const EdgeInsets.only(bottom: 6),
        child: ViewOnceMessageWidget(
          groupChatId: _groupChatId,
          messageId: msgId,
          content: msg.content,
          type: msg.type,
          currentUserId: _currentUserId,
          isViewed: data['isViewed'] ?? false,
          provider: _viewOnceProvider,
        ),
      ));
    }

    // Voice
    if (msg.type == 3 && _voiceProvider != null) {
      return wrap(_BubbleRow(
        isMe: isMe,
        margin: const EdgeInsets.only(bottom: 6),
        child: VoiceMessageWidget(
          voiceUrl: msg.content,
          isMyMessage: isMe,
          voiceProvider: _voiceProvider!,
        ),
      ));
    }

    // Video
    if (msg.type == TypeMessage.video) {
      return wrap(_buildVideoBubble(
        msgId: msgId,
        msg: msg,
        isMe: isMe,
        isLastInGroup: isLastInGroup,
        isPending: isPending,
      ));
    }

    // Image
    if (msg.type == TypeMessage.image) {
      return wrap(_buildImageBubble(
        msgId: msgId,
        msg: msg,
        isMe: isMe,
        isLastInGroup: isLastInGroup,
        isPending: isPending,
      ));
    }

    // Sticker
    if (msg.type == TypeMessage.sticker) {
      return wrap(_BubbleRow(
        isMe: isMe,
        margin: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onLongPress: () => _showMsgOptions(msg, msgId),
          child: Image.asset(
            'images/${msg.content}.gif',
            width: 90,
            height: 90,
            fit: BoxFit.cover,
          ),
        ),
      ));
    }

    // Text (default)
    return wrap(_buildTextBubble(
      msgId: msgId,
      msg: msg,
      isMe: isMe,
      isLastInGroup: isLastInGroup,
      isPending: isPending,
      isScam: isScam,
      scamReason: scamReason,
      hasReminder: hasReminder,
    ));
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
  }) {
    final tailR = isLastInGroup ? 4.0 : 20.0;
    final location = _locationProvider?.parseLocationFromMessage(msg.content);
    final isAI = msg.idFrom == AppConstants.aiAssistantId;

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
              // Peer avatar
              if (!isMe && isLastInGroup) ...[
                _Avatar(photoUrl: widget.arguments.peerAvatar, radius: 16),
                const SizedBox(width: 6),
              ] else if (!isMe) ...[
                const SizedBox(width: 38),
              ],

              // Bubble
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
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? const LinearGradient(
                              colors: [
                                Color(0xFF667EEA),
                                Color(0xFF5A67D8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isMe ? null : _T.bubblePeer,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMe ? 20 : tailR),
                        bottomRight: Radius.circular(isMe ? tailR : 20),
                      ),
                      boxShadow: isMe ? _T.shadowPrimary : _T.shadowSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isMe && isScam) _ScamWarning(reason: scamReason),
                        if (!isMe && hasReminder)
                          _ReminderHint(onView: _showReminders),
                        if (msg.isDeleted)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.block_rounded,
                                size: 13,
                                color: isMe ? Colors.white54 : _T.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Tin nhắn đã xóa',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isMe ? Colors.white54 : _T.textMuted,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          )
                        else if (location != null)
                          _LocationContent(
                            location: location,
                            isMe: isMe,
                            onOpen: () => _openMaps(location.mapsUrl),
                          )
                        else if (isAI)
                          MarkdownBody(
                            data: msg.content,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                  fontSize: 15,
                                  color: _T.textPrimary,
                                  height: 1.5),
                            ),
                          )
                        else
                          Text(
                            msg.content,
                            style: TextStyle(
                              color: isMe ? Colors.white : _T.bubblePeerText,
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        if (isMe) ...[
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (msg.editedAt != null)
                                Text(
                                  '(đã sửa) ',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
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
                                        : Colors.white60,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Quick actions
              if (!msg.isDeleted)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QuickBtn(
                      icon: Icons.add_reaction_outlined,
                      onTap: () => _showReactionPicker(msgId),
                    ),
                    if (!isMe)
                      _QuickBtn(
                        icon: Icons.alarm_add_rounded,
                        onTap: () => _setReminder(msg, msgId),
                      ),
                  ],
                ),
            ],
          ),

          // Scam scan
          if (!isMe && msg.type == TypeMessage.text) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: _ScamScanWidget(
                msgId: msgId,
                content: msg.content,
                result: _scamResults[msgId],
                onScan: (result) {
                  if (mounted) setState(() => _scamResults[msgId] = result);
                },
              ),
            ),
          ],

          // Reactions
          _ReactionRow(
            groupChatId: _groupChatId,
            msgId: msgId,
            currentUserId: _currentUserId,
            isMe: isMe,
            provider: _reactionProvider,
            onTap: (emoji) => _reactionProvider.toggleReaction(
              _groupChatId,
              msgId,
              _currentUserId,
              emoji,
            ),
          ),

          // Timestamp
          if (isLastInGroup)
            Padding(
              padding: EdgeInsets.only(
                left: isMe ? 0 : 44,
                right: isMe ? 6 : 0,
                top: 3,
              ),
              child: Text(
                _fmtTimestamp(msg.timestamp),
                style: _T.fontCaption,
              ),
            ),
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
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: _BubbleRow(
        isMe: isMe,
        child: GestureDetector(
          onTap: () {
            if (!isPending) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => FullPhotoPage(url: msg.content)),
              );
            }
          },
          onLongPress: () => _showMsgOptions(msg, msgId),
          child: ClipRRect(
            borderRadius: BorderRadius.all(_T.r20),
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.62,
              height: 220,
              child: isPending
                  ? _MediaPlaceholder(isLoading: true)
                  : Image.network(
                      msg.content,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, prog) => prog == null
                          ? child
                          : _MediaPlaceholder(
                              isLoading: true,
                              progress: prog.expectedTotalBytes != null
                                  ? prog.cumulativeBytesLoaded /
                                      prog.expectedTotalBytes!
                                  : null,
                            ),
                      errorBuilder: (_, __, ___) =>
                          const _MediaPlaceholder(isLoading: false),
                    ),
            ),
          ),
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
  }) {
    final parts = msg.content.split('|');
    final videoUrl = parts.isNotEmpty ? parts[0] : '';
    final thumbUrl = parts.length > 1 ? parts[1] : '';

    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
      child: _BubbleRow(
        isMe: isMe,
        child: GestureDetector(
          onTap: () {
            if (!isPending) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => VideoPlayerPage(videoUrl: videoUrl)),
              );
            }
          },
          onLongPress: () => _showMsgOptions(msg, msgId),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.65,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(_T.r20),
              color: Colors.black,
              boxShadow: _T.shadowMd,
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbUrl.isNotEmpty && !isPending)
                  Image.network(thumbUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Colors.black54)),
                if (!thumbUrl.isNotEmpty || isPending)
                  const ColoredBox(color: Color(0xFF1F2937)),
                if (isPending)
                  const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                else
                  Center(
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        shape: BoxShape.circle,
                        boxShadow: _T.shadowMd,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 30,
                        color: _T.textPrimary,
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.all(_T.r8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_rounded,
                            size: 11, color: Colors.white),
                        SizedBox(width: 3),
                        Text('Video',
                            style:
                                TextStyle(fontSize: 10, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TYPING INDICATOR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTypingBar() {
    if (_presenceProvider == null) return const SizedBox.shrink();
    return StreamBuilder<Map<String, TypingInfo>>(
      stream: _presenceProvider!.getTypingStatusStream(_groupChatId),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final isTyping = snap.data![widget.arguments.peerId]?.isTyping ?? false;
        if (!isTyping) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: TypingIndicator(userName: widget.arguments.peerNickname),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STICKER PANEL
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStickerPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _T.surface,
        border: Border(top: BorderSide(color: _T.border)),
        boxShadow: _T.shadowSm,
      ),
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
                  onTap: () => _onSend(
                    'mimi${row * 3 + col + 1}',
                    TypeMessage.sticker,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FEATURE MENU
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFeatureMenu() {
    final items = <_FeatureItem>[
      _FeatureItem(Icons.image_rounded, 'Ảnh', _pickImage, _T.primary),
      _FeatureItem(
          Icons.videocam_rounded, 'Video', _pickVideo, const Color(0xFFFF6B9D)),
      _FeatureItem(
          Icons.visibility_off_rounded,
          'View Once',
          () => showDialog(
                context: context,
                builder: (_) => SendViewOnceDialog(
                  onSend: (content, type, dur) async {
                    await _viewOnceProvider.sendViewOnceMessage(
                      groupChatId: _groupChatId,
                      currentUserId: _currentUserId,
                      peerId: widget.arguments.peerId,
                      content: content,
                      type: type,
                    );
                    _loadSmartReplies();
                  },
                ),
              ),
          const Color(0xFF8B5CF6)),
      _FeatureItem(
          Icons.timer_rounded,
          'Tự xoá',
          () => showDialog(
                context: context,
                builder: (_) => AutoDeleteSettingsDialog(
                  conversationId: _groupChatId,
                  provider: _autoDeleteProvider,
                ),
              ),
          _T.warning),
      _FeatureItem(Icons.lock_rounded, 'Khoá', _showLockOptions, _T.info),
      _FeatureItem(
          Icons.location_on_rounded, 'Vị trí', _shareLocation, _T.danger),
      _FeatureItem(Icons.schedule_send_rounded, 'Lên lịch', _scheduleMessage,
          _T.success),
      _FeatureItem(
          Icons.bubble_chart_rounded, 'Bubble', _createBubble, _T.primary),
    ];

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _menuAnim, curve: Curves.easeOutCubic)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 120),
        decoration: BoxDecoration(
          color: _T.surface,
          border: Border(top: BorderSide(color: _T.border)),
          boxShadow: _T.shadowSm,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: items
                .map((item) => GestureDetector(
                      onTap: () {
                        if (resourceManager.isDisposed) return;
                        setState(() => _showMenu = false);
                        _menuAnim.reverse();
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
                                color: item.color.withOpacity(0.1),
                                borderRadius: BorderRadius.all(_T.r14),
                                border: Border.all(
                                    color: item.color.withOpacity(0.2),
                                    width: 0.8),
                              ),
                              child:
                                  Icon(item.icon, color: item.color, size: 22),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.label,
                              style: _T.fontCaption.copyWith(
                                color: _T.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RECORDING BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRecBar() {
    if (!_isRecording) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _T.danger.withOpacity(0.05),
        border: Border(top: BorderSide(color: _T.danger.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          _RecDot(),
          const SizedBox(width: 10),
          Text(
            'Đang ghi âm  $_recDuration',
            style: TextStyle(
              color: _T.danger,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          _IconBtn(
            icon: Icons.delete_outline_rounded,
            color: _T.danger,
            onTap: _cancelRec,
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.send_rounded,
            color: _T.primary,
            onTap: _stopRec,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INPUT
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildInput() {
    final full = !widget.isBubbleMode && !widget.isMiniChat;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Smart replies
        if (_smartReplies.isNotEmpty && full)
          SizedBox(
            height: 44,
            child: SingleChildScrollView(
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
                },
              ),
            ),
          ),

        _buildRecBar(),

        Container(
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 10,
            left: 12,
            right: 12,
            top: 6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reply preview
              AnimatedSize(
                duration: _T.normal,
                curve: Curves.easeOutCubic,
                child: _replyingTo == null
                    ? const SizedBox.shrink()
                    : Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: _T.surface,
                          borderRadius: BorderRadius.all(_T.r16),
                          border: Border(
                            left: BorderSide(color: _T.primary, width: 3),
                          ),
                          boxShadow: _T.shadowSm,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.reply_rounded,
                                color: _T.primary, size: 17),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Trả lời: ${_replyingTo!.content}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _T.fontCaption.copyWith(
                                  color: _T.textSecondary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                if (mounted) {
                                  setState(() => _replyingTo = null);
                                  _replyAnim.reverse();
                                  _focusNode.requestFocus();
                                }
                              },
                              child: const Icon(Icons.close_rounded,
                                  size: 17, color: _T.textMuted),
                            ),
                          ],
                        ),
                      ),
              ),

              // Input row
              Container(
                decoration: BoxDecoration(
                  color: _T.surface,
                  borderRadius: BorderRadius.all(_T.r28),
                  boxShadow: _T.shadowMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Add / Menu
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
                            duration: _T.normal,
                            curve: Curves.easeOutBack,
                            child: Icon(
                              Icons.add_circle_rounded,
                              color: _showMenu ? _T.primary : _T.textMuted,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    // Image quick
                    if (full && !_showMenu)
                      GestureDetector(
                        onTap: _pickImage,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.image_rounded,
                              color: _T.textMuted, size: 24),
                        ),
                      ),
                    // Sticker
                    if (full && !_showMenu)
                      GestureDetector(
                        onTap: _toggleSticker,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.emoji_emotions_outlined,
                            color: _isShowSticker ? _T.primary : _T.textMuted,
                            size: 24,
                          ),
                        ),
                      ),
                    // TextField
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: full ? 0 : 16,
                          right: 6,
                          top: 12,
                          bottom: 12,
                        ),
                        child: TextField(
                          controller: _inputController,
                          focusNode: _focusNode,
                          style: _T.fontBody,
                          maxLines: null,
                          textInputAction: TextInputAction.newline,
                          autofocus: widget.isMiniChat || widget.isBubbleMode,
                          onChanged: (t) {
                            _handleTyping(t);
                            if (t.isNotEmpty &&
                                _smartReplies.isNotEmpty &&
                                mounted) {
                              setState(() => _smartReplies = []);
                            }
                          },
                          onSubmitted: (_) {
                            if (!resourceManager.isDisposed) {
                              _onSend(
                                _inputController.text,
                                TypeMessage.text,
                              );
                            }
                          },
                          decoration: InputDecoration.collapsed(
                            hintText: 'Nhắn tin...',
                            hintStyle: _T.fontBody.copyWith(
                              color: _T.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Send / Mic
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _inputController,
                        builder: (_, val, __) {
                          final hasText = val.text.trim().isNotEmpty;
                          return GestureDetector(
                            onTap: () {
                              if (hasText) {
                                _onSend(
                                  _inputController.text,
                                  TypeMessage.text,
                                );
                              } else if (full) {
                                _startRec();
                              }
                            },
                            child: AnimatedContainer(
                              duration: _T.fast,
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: hasText
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF667EEA),
                                          Color(0xFF5A67D8),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: hasText ? null : _T.surfaceAlt,
                                shape: BoxShape.circle,
                                boxShadow: hasText ? _T.shadowPrimary : null,
                              ),
                              child: AnimatedSwitcher(
                                duration: _T.fast,
                                child: Icon(
                                  hasText
                                      ? Icons.send_rounded
                                      : Icons.mic_rounded,
                                  key: ValueKey(hasText),
                                  color: hasText ? Colors.white : _T.textMuted,
                                  size: 20,
                                ),
                              ),
                            ),
                          );
                        },
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

  // ─────────────────────────────────────────────────────────────────────────
  // MEDIA OVERLAY
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMediaOverlay() => Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: _T.surface,
              borderRadius: BorderRadius.all(_T.r20),
              boxShadow: _T.shadowMd,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: _T.primary,
                  strokeWidth: 2.5,
                ),
                const SizedBox(height: 16),
                Text(
                  'Đang nén & tải lên...',
                  style: _T.fontBody.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({
    required this.peerId,
    required this.peerNickname,
    required this.peerAvatar,
    required this.onTap,
  });
  final String peerId, peerNickname, peerAvatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          AvatarWithStatus(
            userId: peerId,
            photoUrl: peerAvatar,
            size: 40,
            indicatorSize: 11,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  peerNickname,
                  style: _T.fontDisplay.copyWith(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                UserStatusIndicator(
                  userId: peerId,
                  showText: true,
                  size: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayHeader extends StatelessWidget {
  const _OverlayHeader({
    required this.nickname,
    required this.avatar,
    required this.peerId,
    required this.onMinimize,
    required this.onClose,
  });
  final String nickname, avatar, peerId;
  final VoidCallback onMinimize, onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: const BorderRadius.vertical(top: _T.r28),
        border: Border(bottom: BorderSide(color: _T.border)),
      ),
      child: Row(
        children: [
          _Avatar(photoUrl: avatar, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nickname,
                    style: _T.fontDisplay.copyWith(fontSize: 15),
                    overflow: TextOverflow.ellipsis),
                UserStatusIndicator(
                  userId: peerId,
                  showText: true,
                  size: 7,
                  textColor: _T.textMuted,
                ),
              ],
            ),
          ),
          _IconBtn(
            icon: Icons.remove_rounded,
            color: _T.textMuted,
            onTap: onMinimize,
            size: 22,
          ),
          const SizedBox(width: 2),
          _IconBtn(
            icon: Icons.close_rounded,
            color: _T.textMuted,
            onTap: onClose,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _BubbleRow extends StatelessWidget {
  const _BubbleRow({
    required this.isMe,
    required this.child,
    this.margin,
  });
  final bool isMe;
  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.radius});
  final String photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: _T.primaryLight,
        backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
        child: photoUrl.isEmpty
            ? Icon(Icons.person_rounded, size: radius, color: _T.primary)
            : null,
      );
}

class _QuickBtn extends StatelessWidget {
  const _QuickBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: _T.textMuted),
        ),
      );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: color, size: size),
        ),
      );
}

class _ScrollFab extends StatelessWidget {
  const _ScrollFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _T.surface,
            shape: BoxShape.circle,
            boxShadow: _T.shadowMd,
          ),
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _T.textSecondary,
            size: 22,
          ),
        ),
      );
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (_sameDay(date, now)) {
      label = 'Hôm nay';
    } else if (_sameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Hôm qua';
    } else {
      label = DateFormat('dd/MM/yyyy').format(date);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: _T.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _T.surfaceAlt,
                borderRadius: BorderRadius.all(_T.rFull),
              ),
              child: Text(
                label,
                style: _T.fontCaption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: _T.border, height: 1)),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.isLoading, this.progress});
  final bool isLoading;
  final double? progress;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: _T.surfaceAlt,
        child: Center(
          child: isLoading
              ? CircularProgressIndicator(
                  value: progress,
                  color: _T.primary,
                  strokeWidth: 2.5,
                )
              : const Icon(Icons.broken_image_rounded,
                  color: _T.textMuted, size: 32),
        ),
      );
}

class _RecDot extends StatefulWidget {
  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

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
          decoration: const BoxDecoration(
            color: _T.danger,
            shape: BoxShape.circle,
          ),
        ),
      );
}

class _StickerItem extends StatelessWidget {
  const _StickerItem({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Image.asset(
            'images/$name.gif',
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.error, size: 40),
          ),
        ),
      );
}

class _ScamWarning extends StatelessWidget {
  const _ScamWarning({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _T.danger.withOpacity(0.08),
          borderRadius: const BorderRadius.all(_T.r10),
          border: Border.all(color: _T.danger.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_rounded, color: _T.danger, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'CẢNH BÁO AI: $reason',
                style: TextStyle(
                  fontSize: 11.5,
                  color: _T.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

class _ReminderHint extends StatelessWidget {
  const _ReminderHint({required this.onView});
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _T.info.withOpacity(0.08),
          borderRadius: const BorderRadius.all(_T.r10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm_add_rounded, color: _T.info, size: 13),
            const SizedBox(width: 6),
            const Text(
              'AI: Phát hiện công việc cần nhắc!',
              style: TextStyle(fontSize: 11, color: _T.info),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onView,
              child: Text(
                'XEM',
                style: TextStyle(
                  fontSize: 11,
                  color: _T.info,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

class _LocationContent extends StatelessWidget {
  const _LocationContent({
    required this.location,
    required this.isMe,
    required this.onOpen,
  });
  final dynamic location;
  final bool isMe;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_rounded,
                color: isMe ? Colors.white : _T.danger,
                size: 17,
              ),
              const SizedBox(width: 4),
              Text(
                'Vị trí',
                style: TextStyle(
                  color: isMe ? Colors.white : _T.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            location.address,
            style: TextStyle(
              color: isMe ? Colors.white70 : _T.textSecondary,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.18) : _T.primaryLight,
                borderRadius: const BorderRadius.all(_T.r10),
                border: Border.all(
                  color: isMe
                      ? Colors.white.withOpacity(0.3)
                      : _T.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_rounded,
                      size: 13, color: isMe ? Colors.white : _T.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Xem trên Maps',
                    style: TextStyle(
                      fontSize: 12,
                      color: isMe ? Colors.white : _T.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _ScamScanWidget extends StatelessWidget {
  const _ScamScanWidget({
    required this.msgId,
    required this.content,
    required this.result,
    required this.onScan,
  });
  final String msgId, content;
  final dynamic result;
  final void Function(String) onScan;

  @override
  Widget build(BuildContext context) {
    if (result != null && result != 'SAFE') {
      return ScamWarningWidget(status: result as String);
    }
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
              backgroundColor: _T.success,
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _T.success.withOpacity(0.08),
            borderRadius: const BorderRadius.all(_T.r10),
            border: Border.all(color: _T.success.withOpacity(0.3), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 13, color: _T.success),
              const SizedBox(width: 4),
              Text(
                'Quét AI',
                style: TextStyle(
                  fontSize: 11,
                  color: _T.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ReactionRow extends StatelessWidget {
  const _ReactionRow({
    required this.groupChatId,
    required this.msgId,
    required this.currentUserId,
    required this.isMe,
    required this.provider,
    required this.onTap,
  });
  final String groupChatId, msgId, currentUserId;
  final bool isMe;
  final ReactionProvider provider;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
        stream: provider.getReactions(groupChatId, msgId),
        builder: (_, snap) {
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const SizedBox.shrink();
          }
          final reactions = <String, int>{};
          final myReactions = <String, bool>{};
          for (final doc in snap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final emoji = d['emoji'] as String;
            final uid = d['userId'] as String;
            reactions[emoji] = (reactions[emoji] ?? 0) + 1;
            if (uid == currentUserId) myReactions[emoji] = true;
          }
          return Padding(
            padding: const EdgeInsets.only(top: 3),
            child: MessageReactionsDisplay(
              reactions: reactions,
              currentUserId: currentUserId,
              userReactions: myReactions,
              onReactionTap: onTap,
            ),
          );
        },
      );
}

// Modern Dialog
class _ChatDialog extends StatelessWidget {
  const _ChatDialog({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.content,
    required this.actions,
  });
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Dialog(
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_T.r24)),
        elevation: 0,
        backgroundColor: _T.surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: const BorderRadius.all(_T.r12),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: _T.fontDisplay),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              content,
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions
                    .map((a) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: a,
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      );
}

class _ChatDialogAction extends StatelessWidget {
  const _ChatDialogAction({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.isDanger = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool isPrimary, isDanger;

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: _T.primary,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(_T.r12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        child: Text(label),
      );
    }
    if (isDanger) {
      return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: _T.danger,
        ),
        child: Text(label),
      );
    }
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _T.textSecondary,
      ),
      child: Text(label),
    );
  }
}

class _LockOptionsSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(bottom: 16),
        decoration: const BoxDecoration(
          color: _T.surface,
          borderRadius: BorderRadius.vertical(top: _T.r28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _T.border,
                borderRadius: BorderRadius.all(_T.rFull),
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.lock_outline_rounded, color: _T.primary),
              title: const Text('Đặt mã PIN'),
              onTap: () => Navigator.pop(context, 'set_pin'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_open_rounded, color: _T.danger),
              title: const Text('Xoá khoá', style: TextStyle(color: _T.danger)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded, color: _T.textMuted),
              title: const Text('Huỷ'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      );
}

class _ReminderPickerDialog extends StatefulWidget {
  @override
  State<_ReminderPickerDialog> createState() => _ReminderPickerDialogState();
}

class _ReminderPickerDialogState extends State<_ReminderPickerDialog> {
  DateTime _selected = DateTime.now().add(const Duration(hours: 1));

  @override
  Widget build(BuildContext context) => _ChatDialog(
        title: 'Đặt Nhắc Nhở',
        icon: Icons.alarm_add_rounded,
        iconColor: _T.primary,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PickerTile(
              icon: Icons.calendar_today_rounded,
              label: 'Ngày',
              value: DateFormat('dd/MM/yyyy').format(_selected),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _selected,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null && mounted) {
                  setState(() => _selected = DateTime(d.year, d.month, d.day,
                      _selected.hour, _selected.minute));
                }
              },
            ),
            const SizedBox(height: 8),
            _PickerTile(
              icon: Icons.access_time_rounded,
              label: 'Giờ',
              value: DateFormat('HH:mm').format(_selected),
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_selected),
                );
                if (t != null && mounted) {
                  setState(() => _selected = DateTime(_selected.year,
                      _selected.month, _selected.day, t.hour, t.minute));
                }
              },
            ),
          ],
        ),
        actions: [
          _ChatDialogAction(
            label: 'Đặt nhắc',
            isPrimary: true,
            onTap: () => Navigator.pop(context, _selected),
          ),
          _ChatDialogAction(
            label: 'Huỷ',
            onTap: () => Navigator.pop(context),
          ),
        ],
      );
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label, value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _T.surfaceAlt,
            borderRadius: const BorderRadius.all(_T.r12),
            border: Border.all(color: _T.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: _T.primary, size: 20),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: _T.fontCaption),
                  Text(
                    value,
                    style: _T.fontBody.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  color: _T.textMuted, size: 20),
            ],
          ),
        ),
      );
}

class _RemindersPage extends StatelessWidget {
  const _RemindersPage({
    required this.currentUserId,
    required this.reminderProvider,
  });
  final String currentUserId;
  final ReminderProvider reminderProvider;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _T.bg,
        appBar: AppBar(
          title: Text('Nhắc nhở', style: _T.fontDisplay.copyWith(fontSize: 17)),
          backgroundColor: _T.surface,
          foregroundColor: _T.textPrimary,
          elevation: 0,
          shadowColor: Colors.black12,
        ),
        body: StreamBuilder<List<MessageReminder>>(
          stream: reminderProvider.getUserRemindersStream(currentUserId),
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                    color: _T.primary, strokeWidth: 2),
              );
            }
            final reminders = snap.data!;
            if (reminders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.alarm_off_rounded,
                        size: 60, color: _T.textMuted),
                    const SizedBox(height: 14),
                    Text('Chưa có nhắc nhở',
                        style: _T.fontBody.copyWith(
                          color: _T.textSecondary,
                          fontWeight: FontWeight.w500,
                        )),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reminders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = reminders[i];
                return Container(
                  decoration: BoxDecoration(
                    color: _T.surface,
                    borderRadius: const BorderRadius.all(_T.r16),
                    boxShadow: _T.shadowSm,
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _T.primaryLight,
                        borderRadius: const BorderRadius.all(_T.r12),
                      ),
                      child: const Icon(Icons.alarm_rounded, color: _T.primary),
                    ),
                    title: Text(
                      r.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _T.fontBody.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(r.reminderTime),
                      style: _T.fontCaption,
                    ),
                    trailing: GestureDetector(
                      onTap: () => reminderProvider.deleteReminder(r.id),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: _T.danger),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}

// Private data class
class _FeatureItem {
  const _FeatureItem(this.icon, this.label, this.onTap, this.color);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
}

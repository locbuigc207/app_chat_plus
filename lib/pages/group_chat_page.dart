// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

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

// ═══════════════════════════════════════════════════════════════════════════
// GROUP CHAT PAGE — 2026 UI/UX ARCHITECTURE + AI REMINDERS + GROUP CALLS
// ─────────────────────────────────────────────────────────────────────────
// FIXES & OPTIMISATIONS APPLIED:
//   FIX-1  : preferredSize height 72→86 (chip row was cut off)
//   FIX-2  : Chip row SizedBox height 16→30 (actual chip height ≈24px)
//   FIX-3  : Typing-status text wrapped in Flexible → no overflow with long names
//   FIX-4  : SentimentIndicatorWidget constrained to SizedBox(height:26)
//   FIX-5  : AI context bar uses AnimatedSize instead of SizeTransition+setState
//   FIX-6  : _buildAIContextBar SizeTransition removed (parent AnimatedSize handles it)
//   FIX-7  : FilePicker.platform.pickFiles (correct API)
//   FIX-8  : Removed unused _reactionCooldown Map
//   FIX-9  : Removed dead dart:math import placeholder (added only where used)
//   PERF-1 : _processMessages result cached with key, recomputed only on data change
//   PERF-2 : prefetchLinkPreviews moved to _readLocal, NOT called per-build
//   PERF-3 : addAutomaticKeepAlives: false in ListView.builder (saves RAM)
//   PERF-4 : cacheExtent: 800 for smoother fling scrolling
//   PERF-5 : RepaintBoundary wrapping every message item
//   PERF-6 : Empty-state TweenAnimationBuilder given const ValueKey
//   UX-1   : _showMoreBottomSheet constrains maxHeight to 0.72 of screen
// ═══════════════════════════════════════════════════════════════════════════

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
  // ── Core state ────────────────────────────────────────────────────────────
  late String _currentUserId;
  String get _currentUserName => _memberNames[_currentUserId] ?? 'Bạn';
  int _limit = 30;
  static const int _limitIncrement = 20;

  bool _isLoading = false;
  bool _isLoadingMedia = false;
  bool _isShowSticker = false;
  bool _showFeaturesMenu = false;
  bool _isRecording = false;
  bool _showScrollToBottom = false;
  bool _isLoadingSmartReply = false;
  bool _showAIPanel = false;
  bool _showAIContextBar = true;

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

  EnhancedSmartReplyResult? _smartReplyResult;
  List<SmartReplyItem> _swipeRichItems = [];
  final Map<String, dynamic> _scamResults = {};
  final Set<String> _processedMsgIds = {};

  String? _pendingScrollToMessageId;
  bool _isShowingSwipeCards = false;
  List<String> _swipeReplies = [];

  // PERF-1: cache _processMessages output
  List<dynamic>? _cachedGrouped;
  String? _processCacheKey;

  // ── AutoPilot ─────────────────────────────────────────────────────────────
  AutoPilotProvider? _autoPilotProvider;
  StreamSubscription? _autoPilotMsgSub;
  String _lastAutoPilotRepliedMsgId = '';

  // ── Bubble ────────────────────────────────────────────────────────────────
  UnifiedBubbleService? _bubbleService;
  BubbleContext _bubbleCtx = const BubbleContext();
  StreamSubscription<BubbleContext>? _bubbleCtxSub;

  // ── Reminder ──────────────────────────────────────────────────────────────
  List<ExtractedReminder> _pendingExtracted = [];
  bool _showExtractPanel = false;
  bool _isExtractingRem = false;
  int _activeReminderCount = 0;
  late final Stream<List<EnhancedReminder>> _convoReminderStream;

  // ── Animation controllers ─────────────────────────────────────────────────
  late final AnimationController _appBarAnim;
  late final AnimationController _fabAnim;
  late final AnimationController _menuAnim;
  late final AnimationController _replyAnim;
  late final AnimationController _aiPanelAnim;
  late final AnimationController _aiContextBarAnim;
  late final AnimationController _inputFocusAnim;

  // ── Providers ─────────────────────────────────────────────────────────────
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

  // ══════════════════════════════════════════════════════════════════════════
  // INIT
  // ══════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _chatInputController = MentionTextEditingController();
    _listScrollController = ScrollController();
    _focusNode = FocusNode();

    _appBarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _menuAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _replyAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _aiPanelAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _aiContextBarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _inputFocusAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    resourceManager
      ..addAnimationController(_appBarAnim)
      ..addAnimationController(_fabAnim)
      ..addAnimationController(_menuAnim)
      ..addAnimationController(_replyAnim)
      ..addAnimationController(_aiPanelAnim)
      ..addAnimationController(_aiContextBarAnim)
      ..addAnimationController(_inputFocusAnim);

    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChange);
    resourceManager.addDisposer(
      () => _focusNode.removeListener(_onFocusChange),
    );
    _listScrollController.addListener(_scrollListener);
    resourceManager.addDisposer(
      () => _listScrollController.removeListener(_scrollListener),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!resourceManager.isDisposed && mounted) {
        _initializeProviders(context);
        MethodChannel(
          'bubble_chat_channel',
        ).invokeMethod('flutterReady').catchError((_) {});
        MethodChannel(
          'mini_chat_channel',
        ).invokeMethod('flutterReady').catchError((_) {});
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
      _voiceProvider = VoiceMessageProvider(
        firebaseStorage: _chatProvider.firebaseStorage,
      );
    } catch (_) {}

    _autoPilotProvider = context.read<AutoPilotProvider>();
    unawaited(
      _autoPilotProvider!.loadConfig(
        groupChatId,
        _authProvider.userFirebaseId ?? '',
      ),
    );
    _startGroupAutoPilotListener();

    try {
      _bubbleService = context.read<UnifiedBubbleService>();
    } catch (_) {
      _bubbleService = UnifiedBubbleService();
    }

    _bubbleCtxSub = ContextualBubbleService.instance
        .contextStream(groupChatId)
        .listen((ctx) {
          if (mounted && !resourceManager.isDisposed)
            setState(() => _bubbleCtx = ctx);
        });

    _readLocal();
    _loadPinnedMessages();
    _loadMemberNames();
    _startToxicityMonitor();
    _listenActiveGroupCall();
    BubbleLifecycleObserver.instance.onChatOpened(groupChatId);
    _initReminderStream();
    _convoReminderStream = _reminderProvider.getConversationRemindersStream(
      groupChatId,
    );
    _reminderProvider.checkAndHandleExpired(_currentUserId).catchError((_) {});
  }

  void _listenActiveGroupCall() {
    if (resourceManager.isDisposed) return;
    final sub = GroupCallService.instance
        .activeCallForGroup(groupChatId)
        .listen((call) {
          if (!mounted || resourceManager.isDisposed) return;
          if (call != null && call.isCalling) HapticFeedback.vibrate();
        });
    resourceManager.addSubscription(sub);
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
    final sub = _chatProvider.listenToFirebaseChanges(
      groupChatId,
      _currentUserId,
      groupChatId,
    );
    resourceManager.addSubscription(sub);
    _markMessagesAsRead();
    _listenIncomingGroupMessages();
    // PERF-2: prefetch only once here, NOT in build
    resourceManager.addDelayedTimer(const Duration(milliseconds: 500), () {
      if (!resourceManager.isDisposed && mounted) {
        unawaited(_loadSmartReplies());
        final msgs = LocalDbService().getMessages(groupChatId);
        prefetchLinkPreviews(msgs.take(30).toList());
      }
    });
  }

  void _initReminderStream() {
    final sub = _reminderProvider.getActiveReminderCount(_currentUserId).listen(
      (c) {
        if (mounted) setState(() => _activeReminderCount = c);
      },
    );
    resourceManager.addSubscription(sub);
  }

  Future<void> _analyzeForReminders(String content, String senderId) async {
    if (senderId == _currentUserId) return;
    if (content.isEmpty || content.length < 10) return;
    if (content.startsWith('{"iv":') || content.startsWith('{')) return;
    if (_isExtractingRem) return;
    setState(() => _isExtractingRem = true);
    try {
      final ctx = LocalDbService()
          .getMessages(groupChatId)
          .take(4)
          .map((m) => m['content']?.toString() ?? '')
          .where((c) => c.isNotEmpty && !c.startsWith('{"iv":'))
          .toList()
          .reversed
          .join('\n');
      final result = await AIBackendService().extractReminderWithPriority(
        message: content,
        conversationContext: ctx,
      );
      if (!result.hasReminder || result.isEmpty || !mounted) return;
      setState(() {
        _pendingExtracted = result.reminders;
        _showExtractPanel = true;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isExtractingRem = false);
    }
  }

  Future<void> _acceptExtracted(ExtractedReminder item) async {
    var time = item.parsedReminderTime;
    if (time.isBefore(DateTime.now()))
      time = DateTime.now().add(const Duration(hours: 1));
    final r = await context.read<ReminderProvider>().scheduleReminder(
      userId: _currentUserId,
      messageId: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: groupChatId,
      reminderTime: time,
      message: item.task,
      priority: item.priority,
      category: item.category,
      deadline: item.deadline,
      isAutoGenerated: true,
    );
    if (!mounted) return;
    if (r != null) {
      _showToast('⏰ Đã thêm nhắc nhở: ${item.priority.emoji}', isSuccess: true);
      setState(() {
        _pendingExtracted.remove(item);
        if (_pendingExtracted.isEmpty) _showExtractPanel = false;
      });
    } else {
      _showToast('❌ Không thể thêm nhắc nhở', isSuccess: false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AUTOPILOT
  // ══════════════════════════════════════════════════════════════════════════
  void _startGroupAutoPilotListener() {
    if (_autoPilotProvider == null || resourceManager.isDisposed) return;
    final sub = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) async {
          if (snap.docs.isEmpty || resourceManager.isDisposed) return;
          if (!(_autoPilotProvider?.isActiveForConversation(groupChatId) ??
              false))
            return;
          final data = snap.docs.first.data();
          final idFrom = data['idFrom'] as String? ?? '';
          final content = data['content'] as String? ?? '';
          final msgId = snap.docs.first.id;
          if (idFrom == _currentUserId || idFrom == 'AI_BOT') return;
          if (msgId == _lastAutoPilotRepliedMsgId) return;
          if (content.startsWith('{"iv":') || content.trim().length < 2) return;
          _lastAutoPilotRepliedMsgId = msgId;
          final ctxMsgs = LocalDbService()
              .getMessages(groupChatId)
              .take(4)
              .map((m) => m['content']?.toString() ?? '')
              .where((c) => c.isNotEmpty && !c.startsWith('{"iv":'))
              .toList()
              .reversed
              .toList();
          final reply = await _autoPilotProvider!.generateReply(
            conversationId: groupChatId,
            incomingMessage: content,
            senderId: idFrom,
            currentUserId: _currentUserId,
            contextMessages: ctxMsgs,
          );
          if (reply != null && !resourceManager.isDisposed && mounted) {
            final delay = Duration(
              milliseconds: (800 + reply.length * 25).clamp(800, 2500),
            );
            await Future.delayed(delay);
            if (!resourceManager.isDisposed) await _onSendMessage(reply, 0);
          }
        });
    resourceManager.addSubscription(sub);
    _autoPilotMsgSub = sub;
  }

  void _showAutoPilotSheet() => AutoPilotConfigSheet.show(
    context,
    conversationId: groupChatId,
    currentUserId: _currentUserId,
    isGroup: true,
  );

  // ══════════════════════════════════════════════════════════════════════════
  // BUBBLE
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _updateGroupBubble(
    String content,
    int type, {
    required bool fromUser,
    String? senderId,
  }) async {
    if (_bubbleService == null) return;
    if (!BubbleSettingsService().isEnabled) return;
    if (BubbleSettingsService().settings.autoHideWhenChatOpen && !fromUser)
      return;
    if (!_bubbleService!.isBubbleActive(groupChatId)) return;
    final senderLabel = fromUser
        ? (_memberNames[_currentUserId] ?? 'Bạn')
        : (senderId != null
              ? (_memberNames[senderId] ?? widget.group.groupName)
              : widget.group.groupName);
    final preview = switch (type) {
      TypeMessage.image => '📷 Hình ảnh',
      TypeMessage.video => '🎬 Video',
      3 => '🎤 Tin nhắn thoại',
      TypeMessage.geoLocked => '📍 Vị trí',
      TypeMessage.sticker => '😊 Sticker',
      TypeMessage.document => '📎 Tệp đính kèm',
      TypeMessage.poll => '📊 Bình chọn',
      _ => content.length > 55 ? '${content.substring(0, 55)}…' : content,
    };
    try {
      await _bubbleService!.sendMessage(
        userId: groupChatId,
        userName: widget.group.groupName,
        message: fromUser ? 'Bạn: $preview' : '$senderLabel: $preview',
        avatarUrl: widget.group.groupPhotoUrl,
        messageType: switch (type) {
          TypeMessage.image => 'image',
          3 => 'voice',
          TypeMessage.video => 'video',
          _ => 'text',
        },
      );
    } catch (e) {
      debugPrint('❌ GroupBubble update: $e');
    }
  }

  Future<void> _createGroupBubble() async {
    if (_bubbleService == null) return;
    if (!_bubbleService!.isSupported) {
      _showToast('Thiết bị không hỗ trợ chat bubble');
      return;
    }
    if (!BubbleSettingsService().isEnabled) {
      final confirm = await _showConfirmDialog(
        title: 'Bong bóng chat đang tắt',
        message: 'Mở Cài đặt → Bong bóng chat để bật?',
        confirmLabel: 'Mở cài đặt',
      );
      if (confirm == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BubbleSettingsPage()),
        );
      }
      return;
    }
    final ctx = ContextualBubbleService.instance.getContext(groupChatId);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx2) {
        final p = context.read<ThemeProvider>().palette;
        final primary = context.read<ThemeProvider>().primaryColor;
        return _ThemedDialog(
          title: 'Chat Bubble Nhóm',
          icon: Icons.bubble_chart_rounded,
          iconColor: primary,
          palette: p,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hiện bong bóng cho nhóm\n"${widget.group.groupName}"',
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (ctx.mode != BubbleMode.normal) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Mode: ${ctx.mode.name} ${_modeEmoji(ctx.mode)}',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            _ThemedDialogAction(
              label: 'Tạo Bubble',
              isPrimary: true,
              palette: p,
              primary: primary,
              onTap: () => Navigator.pop(ctx2, 'bubble'),
            ),
            _ThemedDialogAction(
              label: 'Huỷ',
              palette: p,
              primary: primary,
              onTap: () => Navigator.pop(ctx2),
            ),
          ],
        );
      },
    );
    if (choice != 'bubble' || resourceManager.isDisposed) return;
    final ok = await _bubbleService!.showChatBubble(
      userId: groupChatId,
      userName: widget.group.groupName,
      avatarUrl: widget.group.groupPhotoUrl,
    );
    if (ok) {
      _showToast('🫧 Bubble nhóm đã tạo (${ctx.mode.name})', isSuccess: true);
    } else {
      _showToast('❌ Không thể tạo bubble');
    }
  }

  void _listenIncomingGroupMessages() {
    if (resourceManager.isDisposed) return;
    final sub = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .snapshots()
        .listen((snap) async {
          if (resourceManager.isDisposed) return;
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final msgId = change.doc.id;
            if (_processedMsgIds.contains(msgId)) continue;
            final data = change.doc.data() as Map<String, dynamic>? ?? {};
            final isRead = data['isRead'] as bool? ?? false;
            if (isRead) continue;
            _processedMsgIds.add(msgId);
            if (_processedMsgIds.length > 200)
              _processedMsgIds.remove(_processedMsgIds.first);
            final idFrom = data['idFrom'] as String? ?? '';
            if (idFrom == _currentUserId || idFrom.isEmpty) continue;
            final content = data['content'] as String? ?? '';
            final type = data['type'] as int? ?? 0;
            ContextualBubbleService.instance.updateContext(
              conversationId: groupChatId,
              message: content,
            );
            final settings = BubbleSettingsService();
            if (settings.settings.soundEnabled) {
              final bCtx = ContextualBubbleService.instance.getContext(
                groupChatId,
              );
              await BubbleSoundService().playReceive(bCtx.mode);
            }
            await _updateGroupBubble(
              content,
              type,
              fromUser: false,
              senderId: idFrom,
            );
            if (settings.isEnabled &&
                WidgetsBinding.instance.lifecycleState !=
                    AppLifecycleState.resumed) {
              await _bubbleService?.showChatBubble(
                userId: groupChatId,
                userName: widget.group.groupName,
                avatarUrl: widget.group.groupPhotoUrl,
              );
            }
          }
        });
    resourceManager.addSubscription(sub);
  }

  String _modeEmoji(BubbleMode mode) => switch (mode) {
    BubbleMode.work => '💼',
    BubbleMode.media => '🎵',
    BubbleMode.location => '📍',
    BubbleMode.secure => '🔒',
    BubbleMode.shared => '🎨',
    _ => '💬',
  };

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      BubbleLifecycleObserver.instance.didChangeAppLifecycleState(state);

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
      show ? _fabAnim.forward() : _fabAnim.reverse();
    }
  }

  void _onFocusChange() {
    if (resourceManager.isDisposed || !mounted) return;
    if (_focusNode.hasFocus) {
      setState(() {
        _isShowSticker = false;
        _showFeaturesMenu = false;
        _showAIPanel = true;
      });
      _aiPanelAnim.forward();
      _inputFocusAnim.forward();
    } else {
      setState(() => _showAIPanel = false);
      _aiPanelAnim.reverse();
      _inputFocusAnim.reverse();
    }
  }

  @override
  void dispose() {
    _autoPilotMsgSub?.cancel();
    _bubbleCtxSub?.cancel();
    try {
      context.read<InsightsProvider>().cancelWatcher();
    } catch (_) {}
    _recordingTimer?.cancel();
    _scheduledMessages.forEach((_, t) => t.cancel());
    _scheduledMessages.clear();
    _scheduledMessageContents.clear();
    try {
      _presenceProvider?.setTypingStatus(
        conversationId: groupChatId,
        userId: _currentUserId,
        isTyping: false,
      );
      _voiceProvider?.dispose();
    } catch (_) {}
    _chatInputController.dispose();
    _listScrollController.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    BubbleLifecycleObserver.instance.onChatClosed(groupChatId);
    try {
      GroupCallService.instance.dispose();
    } catch (_) {}
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AI FEATURES
  // ══════════════════════════════════════════════════════════════════════════
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
      _showToast('Cần ít nhất 3 tin nhắn');
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
    try {
      context.read<InsightsProvider>().loadDashboard(
        conversationId: groupChatId,
        userId: _currentUserId,
      );
    } catch (_) {}
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInsightsPage(
          conversationId: groupChatId,
          userId: _currentUserId,
          peerName: widget.group.groupName,
        ),
      ),
    );
  }

  void _openWeeklyRecap() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => WeeklyRecapPage(
          userId: _currentUserId,
          conversationId: groupChatId,
          peerName: widget.group.groupName,
          conversationType: RecapConversationType.group,
        ),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
        fullscreenDialog: true,
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
                    content.startsWith('{'))
                  return null;
                return ToxicityInput(id: c.doc.id, text: content);
              })
              .whereType<ToxicityInput>()
              .toList();
          if (newMsgs.isNotEmpty) {
            try {
              final results = await AIBackendService().analyzeToxicityBatch(
                newMsgs,
              );
              for (final r in results) {
                if (!r.isToxic || r.confidence <= 0.72 || r.id == null)
                  continue;
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
                    })
                    .catchError((_) {});
              }
            } catch (e) {
              debugPrint('⚠️ ToxicMonitor: $e');
            }
          }
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final data = change.doc.data() as Map<String, dynamic>? ?? {};
            final content = data['content'] as String? ?? '';
            final idFrom = data['idFrom'] as String? ?? '';
            if (idFrom == _currentUserId || idFrom == 'AI_BOT') continue;
            if (content.isNotEmpty && content.length > 10)
              unawaited(_analyzeForReminders(content, idFrom));
          }
        });
    resourceManager.addSubscription(sub);
  }

  void _openRemindersPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemindersListPage(
          currentUserId: _currentUserId,
          conversationId: groupChatId,
          peerName: widget.group.groupName,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MEMBERS
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _loadMemberNames() async {
    try {
      final docs = await Future.wait(
        widget.group.memberIds.map(
          (uid) => FirebaseFirestore.instance
              .collection(FirestoreConstants.pathUserCollection)
              .doc(uid)
              .get(),
        ),
      );
      final names = <String, String>{};
      for (int i = 0; i < widget.group.memberIds.length; i++) {
        final uid = widget.group.memberIds[i];
        final doc = docs[i];
        if (doc.exists) {
          names[uid] =
              doc.get(FirestoreConstants.nickname) as String? ?? 'User';
          final photoUrl =
              doc.get(FirestoreConstants.photoUrl) as String? ?? '';
          if (photoUrl.isNotEmpty) _avatarUrlCache[uid] = photoUrl;
        }
      }
      if (mounted && !resourceManager.isDisposed)
        setState(() => _memberNames = names);
    } catch (e) {
      debugPrint('Error loading member names: $e');
    }
  }

  String _getSenderName(String senderId) =>
      senderId == _currentUserId ? 'Bạn' : (_memberNames[senderId] ?? 'User');

  void _loadPinnedMessages() {
    if (resourceManager.isDisposed) return;
    final sub = _messageProvider.getPinnedMessages(groupChatId).listen((snap) {
      if (!mounted || resourceManager.isDisposed) return;
      setState(() => _pinnedMessages = snap.docs);
    });
    resourceManager.addSubscription(sub);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INPUT HANDLERS
  // ══════════════════════════════════════════════════════════════════════════
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
          .where(
            (e) =>
                e.key != _currentUserId &&
                e.value.toLowerCase().contains(query),
          )
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
    if (text.isNotEmpty && _smartReplyResult != null && mounted)
      setState(() => _smartReplyResult = null);
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
    _chatInputController.selection = TextSelection.collapsed(
      offset: atIdx + name.length + 2,
    );
    if (mounted) setState(() => _showMentionSuggestions = false);
  }

  void _handleTyping(String text) => _presenceProvider?.setTypingStatus(
    conversationId: groupChatId,
    userId: _currentUserId,
    isTyping: text.isNotEmpty,
  );

  void _showAdaptiveUISuggestion() {
    if (resourceManager.isDisposed || !mounted) return;
    final p = context.read<ThemeProvider>().palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.accessibility_new, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('Khó gõ? Bật Elder Mode để font lớn hơn!')),
          ],
        ),
        duration: const Duration(seconds: 7),
        backgroundColor: p.surface,
        action: SnackBarAction(
          label: 'BẬT',
          textColor: p.warningColor,
          onPressed: () {
            try {
              context.read<AppModeProvider>().setMode(AppMode.elder);
            } catch (_) {}
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MARK READ / SEND / SMART REPLY
  // ══════════════════════════════════════════════════════════════════════════
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
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      BubbleManager.of(context)?.clearUnread(groupChatId);
    } catch (_) {}
  }

  // [SỬA LỖI P1]: Sử dụng hàm helper _buildGroupPreview() để tạo preview tĩnh sạch,
  // đồng thời đồng bộ mốc thời gian _messageTimestamp giữa hệ thống UI hiển thị và SyncManager.
  String _buildGroupPreview(String content, int type) {
    if (type == TypeMessage.image) return '📷 Hình ảnh';
    if (type == TypeMessage.video) return '🎬 Video';
    if (type == TypeMessage.sticker) return '😊 Sticker';
    if (type == TypeMessage.poll) return '📊 Bình chọn';
    if (type == TypeMessage.geoLocked) return '📍 Tin nhắn địa điểm';
    if (type == 3) return '🎤 Tin nhắn thoại';

    final lines = content.split('\n');
    final actual = lines.length > 1 ? lines.last : content;
    return actual.length > 60 ? '${actual.substring(0, 60)}…' : actual;
  }

  Future<void> _onSendMessage(String content, int type) async {
    if (resourceManager.isDisposed) return;
    if (content.trim().isEmpty && type == TypeMessage.text) {
      _showToast('Không có nội dung');
      return;
    }
    HapticFeedback.mediumImpact();

    // Khóa cứng dấu thời gian đồng bộ để cả ChatProvider và SyncManager dùng chung một mốc thời gian
    final String _messageTimestamp = DateTime.now().millisecondsSinceEpoch
        .toString();

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
        _smartReplyResult = null;
        _showMentionSuggestions = false;
      });
      _replyAnim.reverse();
    }

    try {
      await _chatProvider.sendMessage(
        finalContent,
        type,
        groupChatId,
        _currentUserId,
        groupChatId,
      );

      // Thực hiện lưu trữ đồng bộ lên Firestore với preview đã được làm sạch và timestamp đồng bộ
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(groupChatId)
          .set({
            FirestoreConstants.isGroup: true,
            FirestoreConstants.participants: widget.group.memberIds,
            FirestoreConstants.lastMessage: _buildGroupPreview(
              finalContent,
              type,
            ),
            FirestoreConstants.lastMessageTime: _messageTimestamp,
            FirestoreConstants.lastMessageType: type,
          }, SetOptions(merge: true));

      await _autoDeleteProvider.scheduleMessageDeletion(
        groupChatId: groupChatId,
        messageId: _messageTimestamp,
        conversationId: groupChatId,
      );

      ContextualBubbleService.instance.updateContext(
        conversationId: groupChatId,
        message: finalContent,
      );
      await _updateGroupBubble(finalContent, type, fromUser: true);
    } catch (_) {
      _showToast('Gửi thất bại');
    }

    if (_listScrollController.hasClients && !resourceManager.isDisposed) {
      _listScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    if (!resourceManager.isDisposed) unawaited(_loadSmartReplies());
  }

  Future<void> _loadSmartReplies() async {
    if (resourceManager.isDisposed) return;
    final messages = LocalDbService().getMessages(groupChatId);
    if (messages.isEmpty) return;
    final last = messages.first;
    if (last['idFrom'] == _currentUserId ||
        (last['type'] as int?) != TypeMessage.text)
      return;
    final content = last['content'] as String? ?? '';
    if (content.isEmpty || content.startsWith('{"iv":')) return;
    if (mounted && !resourceManager.isDisposed)
      setState(() => _isLoadingSmartReply = true);
    try {
      final history = messages
          .take(6)
          .map((m) => m['content']?.toString() ?? '')
          .where((c) => c.isNotEmpty && !c.startsWith('{"iv":'))
          .toList()
          .reversed
          .toList();
      final result = await _smartReplyProvider.getEnhancedSmartReplies(
        lastMessage: content,
        recentMessages: history,
        closenessLevel: 3,
        relationshipType: 'friend',
        language: 'vi',
      );
      if (mounted && !resourceManager.isDisposed) {
        setState(() {
          _smartReplyResult = result;
          _isLoadingSmartReply = false;
        });
      }
    } catch (e) {
      if (mounted && !resourceManager.isDisposed) {
        final fb = _smartReplyProvider.getRuleBasedReplies(
          messages.first['content']?.toString() ?? '',
        );
        setState(() {
          _smartReplyResult = EnhancedSmartReplyResult.fromLegacy(fb);
          _isLoadingSmartReply = false;
        });
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MEDIA / VOICE / LOCATION / GAME
  // ══════════════════════════════════════════════════════════════════════════
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
          _listScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        _showToast(
          isVideo ? '🎬 Video đã gửi' : '📷 Ảnh đã gửi',
          isSuccess: true,
        );
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
      // FIX-7: FilePicker.platform (API đúng)
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;
        final fileSize = result.files.single.size;
        if (mounted) setState(() => _isLoadingMedia = true);
        final fileUrl = await _chatProvider.uploadFileAndGetUrl(
          file,
          groupChatId,
        );
        if (fileUrl != null && mounted) {
          final content = jsonEncode({
            'url': fileUrl,
            'name': fileName,
            'size': fileSize,
          });
          await _onSendMessage(content, TypeMessage.document);
        }
      }
    } catch (_) {
      _showToast('Lỗi chọn file');
    } finally {
      if (mounted) setState(() => _isLoadingMedia = false);
    }
  }

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
    final uploadResult = await _voiceProvider!.uploadVoiceMessage(
      path,
      fileName,
    );
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
          _locationProvider!.formatLocationMessage(data),
          TypeMessage.text,
        );
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
      await _onSendMessage(jsonEncode(result.toJson()), TypeMessage.geoLocked);
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
      ),
    );
  }

  Future<void> _triggerZeroTypeSwipe() async {
    if (resourceManager.isDisposed) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final messages = LocalDbService().getMessages(groupChatId);
      final lastMsg = messages.isNotEmpty
          ? (messages.first['content']?.toString() ?? 'Hello')
          : 'Hello';
      final r = await AIBackendService().generateSwipeRepliesEnhanced(
        incomingMessage: lastMsg,
        contextMessages: '',
        replyStyle: 'genz',
        includeStickerCards: true,
      );
      if (mounted && !resourceManager.isDisposed) {
        final items = <SmartReplyItem>[
          for (final text in r.replies) SmartReplyItem.text(text: text),
          for (final id in r.stickerCards) SmartReplyItem.sticker(id),
        ];
        setState(() {
          _swipeReplies = r.replies;
          _swipeRichItems = items;
          _isShowingSwipeCards = true;
        });
      }
    } catch (_) {
      _showToast('AI không khả dụng');
    } finally {
      if (mounted && !resourceManager.isDisposed)
        setState(() => _isLoading = false);
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
        messages: recent.reversed.toList(),
        palette: p,
        primary: primary,
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ══════════════════════════════════════════════════════════════════════════
  // MESSAGE OPTIONS / EDIT / DELETE / PIN / REPLY / REMINDER
  // ══════════════════════════════════════════════════════════════════════════
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
      ),
    );
  }

  Future<void> _editMessage(String messageId, String current) async {
    showDialog(
      context: context,
      builder: (_) => EditMessageDialog(
        originalContent: current,
        onSave: (newContent) async {
          String encryptedContent = newContent;
          try {
            encryptedContent = await EncryptionService().encryptPayload(
              newContent,
              groupChatId,
              widget.group.memberIds,
              _currentUserId,
            );
          } catch (e) {
            _showToast('Lỗi mã hóa, không thể sửa');
            return;
          }
          final ok = await _messageProvider.editMessage(
            groupChatId,
            messageId,
            encryptedContent,
          );
          if (ok) {
            try {
              final localKey = '${groupChatId}_$messageId';
              final existingRaw = LocalDbService().messagesBox.get(localKey);
              if (existingRaw != null) {
                final existing = Map<String, dynamic>.from(existingRaw as Map);
                existing['content'] = newContent;
                existing['isEdited'] = true;
                await LocalDbService().saveMessage(
                  groupChatId,
                  messageId,
                  existing,
                );
              }
            } catch (_) {}
            _showToast('Đã chỉnh sửa', isSuccess: true);
          }
        },
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirm = await _showConfirmDialog(
      title: 'Xoá tin nhắn',
      message: 'Xóa tin nhắn này cho tất cả?',
      confirmLabel: 'Xoá',
      isDangerous: true,
    );
    if (confirm == true) {
      final ok = await _messageProvider.deleteMessage(groupChatId, messageId);
      if (ok) _showToast('Đã xoá', isSuccess: true);
    }
  }

  Future<void> _togglePin(String messageId, bool current) async {
    final ok = await _messageProvider.togglePinMessage(
      groupChatId,
      messageId,
      current,
    );
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
    final p = context.read<ThemeProvider>().palette;
    final theme = context.read<ThemeProvider>();
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) =>
          ReminderSetSheet(message: message.content, palette: p, theme: theme),
    );
    if (result == null || !mounted) return;
    final r = await context.read<ReminderProvider>().scheduleReminder(
      userId: _currentUserId,
      messageId: messageId,
      conversationId: groupChatId,
      reminderTime: result['time'] as DateTime,
      message: message.content.length > 100
          ? '${message.content.substring(0, 100)}…'
          : message.content,
      priority: result['priority'] as ReminderPriority,
      category: result['category'] as ReminderCategory,
      repeat: result['repeat'] as ReminderRepeat,
    );
    if (!mounted) return;
    _showToast(
      r != null
          ? '⏰ Đã đặt nhắc nhở ${(result['priority'] as ReminderPriority).emoji}'
          : '❌ Không thể đặt nhắc nhở',
      isSuccess: r != null,
    );
  }

  Future<void> _translateMessage(String content) async => showDialog(
    context: context,
    builder: (_) => TranslationDialog(originalMessage: content),
  );

  Future<void> _scheduleMessage() async {
    if (resourceManager.isDisposed) return;
    final result = await showDialog<ScheduleMessageResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ScheduleMessageDialog(),
    );
    if (result == null || resourceManager.isDisposed || !mounted) return;
    final delay = result.scheduledTime.difference(DateTime.now());
    if (delay.isNegative) {
      _showToast('Thời gian không hợp lệ');
      return;
    }
    final key = result.scheduledTime.millisecondsSinceEpoch.toString();
    _scheduledMessageContents[key] = result.message;
    _scheduledMessages[key] = Timer(delay, () {
      if (!resourceManager.isDisposed && mounted) {
        final c = _scheduledMessageContents[key];
        if (c != null) _onSendMessage(c, TypeMessage.text);
        _scheduledMessages.remove(key);
        _scheduledMessageContents.remove(key);
      }
    });
    _showToast(
      '📅 Lên lịch lúc ${DateFormat('HH:mm').format(result.scheduledTime)}',
      isSuccess: true,
    );
  }

  void _sendViewOnce() => showDialog(
    context: context,
    builder: (_) => SendViewOnceDialog(
      onSend: (content, type, _) async =>
          await _viewOnceProvider.sendViewOnceMessage(
            groupChatId: groupChatId,
            currentUserId: _currentUserId,
            peerId: groupChatId,
            content: content,
            type: type,
          ),
    ),
  );

  void _showReactionPicker(String messageId) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: ReactionPicker(
          onEmojiSelected: (emoji) {
            _reactionProvider.toggleReaction(
              groupChatId,
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
      conversationId: groupChatId,
      userId: _currentUserId,
      isTyping: false,
    );
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
        const Duration(milliseconds: 400),
        () => _scrollToMessage(matchedId),
      );
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
          const Duration(milliseconds: 500),
          () => _scrollToMessage(id),
        );
      }
      return;
    }
    final offset = (index * 72.0).clamp(
      0.0,
      _listScrollController.position.maxScrollExtent,
    );
    _listScrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _pendingScrollToMessageId = null);
  }

  Future<void> _clearHistory() async {
    final confirm = await _showConfirmDialog(
      title: 'Xoá lịch sử',
      message: 'Xóa toàn bộ tin nhắn trong nhóm?',
      confirmLabel: 'Xoá',
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
      isDangerous: true,
    );
    if (confirm != true) return;
    try {
      final newMembers = widget.group.memberIds
          .where((id) => id != _currentUserId)
          .toList();
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(groupChatId)
          .update({FirestoreConstants.memberIds: newMembers});
      await _onSendMessage(
        '${_memberNames[_currentUserId] ?? 'User'} đã rời nhóm',
        TypeMessage.text,
      );
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
          memberNames: _memberNames,
        ),
      ),
    );
  }

  // UX-1: bottom sheet chiều cao giới hạn
  void _showMoreBottomSheet() {
    HapticFeedback.lightImpact();
    final theme = context.read<ThemeProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      builder: (_) => _MoreBottomSheet(
        palette: theme.palette,
        primary: theme.primaryColor,
        bubbleCtx: _bubbleCtx,
        activeReminderCount: _activeReminderCount,
        onSelected: _onMenuSelected,
      ),
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'autopilot':
        _showAutoPilotSheet();
        break;
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
      case 'group_call_history':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupCallHistoryPage(
              groupId: groupChatId,
              groupName: widget.group.groupName,
              currentUserId: _currentUserId,
            ),
          ),
        );
        break;
      case 'info':
        _openGroupInfo();
        break;
      case 'media':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupMediaPage(
              groupId: groupChatId,
              groupName: widget.group.groupName,
            ),
          ),
        );
        break;
      case 'search':
        _openSearch();
        break;
      case 'reminders':
        _openRemindersPage();
        break;
      case 'autodelete':
        showDialog(
          context: context,
          builder: (_) => AutoDeleteSettingsDialog(
            conversationId: groupChatId,
            provider: _autoDeleteProvider,
          ),
        );
        break;
      case 'clear':
        _clearHistory();
        break;
      case 'leave':
        _leaveGroup();
        break;
      case 'bubble':
        _createGroupBubble();
        break;
      case 'settings_bubble':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BubbleSettingsPage()),
        );
        break;
      case 'theme':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ThemeSettingsPage()),
        );
        break;
    }
  }

  void _showToast(String msg, {bool isSuccess = false}) {
    final p = context.read<ThemeProvider>().palette;
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: isSuccess ? p.successColor : p.surface,
      textColor: isSuccess ? Colors.white : p.textPrimary,
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDangerous = false,
  }) {
    final p = context.read<ThemeProvider>().palette;
    final primary = context.read<ThemeProvider>().primaryColor;
    return showDialog<bool>(
      context: context,
      builder: (_) => _ThemedDialog(
        title: title,
        palette: p,
        icon: isDangerous ? Icons.warning_rounded : Icons.help_outline_rounded,
        iconColor: isDangerous ? p.dangerColor : primary,
        content: Text(
          message,
          style: TextStyle(color: p.textSecondary, fontSize: 14.5, height: 1.5),
        ),
        actions: [
          _ThemedDialogAction(
            label: 'Huỷ',
            palette: p,
            primary: primary,
            onTap: () => Navigator.pop(context, false),
          ),
          _ThemedDialogAction(
            label: confirmLabel,
            isPrimary: !isDangerous,
            isDanger: isDangerous,
            palette: p,
            primary: primary,
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
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
            child: Column(
              children: [
                ActiveGroupCallBanner(
                  groupId: groupChatId,
                  currentUserId: _currentUserId,
                  currentUserName: _currentUserName,
                  memberIds: widget.group.memberIds,
                  groupName: widget.group.groupName,
                ),
                if (_showMentionSuggestions) _buildMentionSuggestions(p, theme),
                Expanded(child: _buildChatContent(p, theme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // APP BAR
  // FIX-1: preferredSize 72→86 (56 toolbar + 30 chip row)
  // ══════════════════════════════════════════════════════════════════════════
  PreferredSizeWidget _buildAppBar(ThemePalette p, ThemeProvider theme) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(86),
      child: FadeTransition(
        opacity: _appBarAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _appBarColorFromMode(p),
            boxShadow: [
              BoxShadow(
                color: p.shadow.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                toolbarHeight: 56,
                leading: _buildBackButton(theme),
                titleSpacing: 0,
                title: _buildAppBarTitle(p, theme),
                actions: _buildAppBarActions(p, theme),
              ),
              _buildAppBarChips(p, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton(ThemeProvider theme) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: _onBackPress,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: theme.primaryColor,
          size: 20,
        ),
      ),
    ),
  );

  Widget _buildAppBarTitle(ThemePalette p, ThemeProvider theme) {
    return GestureDetector(
      onTap: _openGroupInfo,
      child: Row(
        children: [
          Hero(
            tag: 'group_avatar_${widget.group.id}',
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [theme.primaryLightColor, theme.primaryColor],
                ),
                border: Border.all(
                  color: theme.primaryColor.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.22),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipOval(
                child: widget.group.groupPhotoUrl.isNotEmpty
                    ? Image.network(
                        widget.group.groupPhotoUrl,
                        fit: BoxFit.cover,
                      )
                    : const Icon(
                        Icons.group_rounded,
                        size: 22,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.group.groupName,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_bubbleCtx.mode != BubbleMode.normal)
                      _BubbleModeBadge(mode: _bubbleCtx.mode),
                  ],
                ),
                _buildOnlineStatus(p, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineStatus(ThemePalette p, ThemeProvider theme) {
    if (_presenceProvider == null) {
      return Text(
        '${widget.group.memberIds.length} thành viên',
        style: TextStyle(color: p.textSecondary, fontSize: 11.5),
      );
    }
    return StreamBuilder<Map<String, TypingInfo>>(
      stream: _presenceProvider!.getTypingStatusStream(groupChatId),
      builder: (_, snap) {
        final typing = snap.hasData
            ? snap.data!.entries
                  .where((e) => e.key != _currentUserId && e.value.isTyping)
                  .map((e) => _getSenderName(e.key))
                  .toList()
            : <String>[];
        if (typing.isNotEmpty) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Row(
              key: const ValueKey('typing'),
              children: [
                _TypingDots(color: theme.primaryColor),
                const SizedBox(width: 5),
                // FIX-3: Flexible prevents overflow with long names
                Flexible(
                  child: Text(
                    typing.length == 1
                        ? '${typing.first} đang nhập…'
                        : '${typing.length} người đang nhập…',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.primaryColor,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            key: const ValueKey('members'),
            '${widget.group.memberIds.length} thành viên',
            style: TextStyle(color: p.textSecondary, fontSize: 11.5),
          ),
        );
      },
    );
  }

  List<Widget> _buildAppBarActions(ThemePalette p, ThemeProvider theme) {
    return [
      if (_autoPilotProvider != null)
        AutoPilotAppBarButton(
          conversationId: groupChatId,
          currentUserId: _currentUserId,
          isGroup: true,
        ),
      _AppBarIconBtn(
        icon: Icons.search_rounded,
        color: p.textSecondary,
        onTap: _openSearch,
      ),
      _AppBarIconBtn(
        icon: Icons.alarm_rounded,
        color: theme.primaryColor,
        onTap: _openRemindersPage,
        badgeCount: _activeReminderCount,
        appBarBackground: p.appBarBackground,
      ),
      GroupVideoCallButton(
        groupId: groupChatId,
        groupName: widget.group.groupName,
        memberIds: widget.group.memberIds,
        groupAvatarUrl: widget.group.groupPhotoUrl,
      ),
      _AppBarIconBtn(
        icon: Icons.more_vert_rounded,
        color: p.textSecondary,
        onTap: _showMoreBottomSheet,
      ),
      const SizedBox(width: 4),
    ];
  }

  // FIX-2: chip row height 16→30
  Widget _buildAppBarChips(ThemePalette p, ThemeProvider theme) {
    return SizedBox(
      height: 30,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 56),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _HeaderChip(
              icon: Icons.auto_awesome,
              label: 'AI tóm tắt',
              color: const Color(0xFF8B5CF6),
              onTap: _showSummaryAnalysis,
            ),
            const SizedBox(width: 6),
            _HeaderChip(
              icon: Icons.people_alt_rounded,
              label: '${widget.group.memberIds.length}',
              color: theme.primaryColor,
              onTap: _openGroupInfo,
            ),
            const SizedBox(width: 6),
            _HeaderChip(
              icon: Icons.alarm_rounded,
              label: _activeReminderCount > 0
                  ? 'Nhắc nhở ($_activeReminderCount)'
                  : 'Nhắc nhở',
              color: theme.primaryColor,
              onTap: _openRemindersPage,
            ),
            const SizedBox(width: 6),
            _HeaderChip(
              icon: Icons.insights_rounded,
              label: 'Insights',
              color: const Color(0xFFF59E0B),
              onTap: _openInsightsPage,
            ),
            const SizedBox(width: 6),
            _HeaderChip(
              icon: Icons.analytics_rounded,
              label: 'Recap',
              color: const Color(0xFF10B981),
              onTap: _openWeeklyRecap,
            ),
            const SizedBox(width: 6),
            _HeaderChip(
              icon: Icons.history_rounded,
              label: 'Lịch sử gọi',
              color: const Color(0xFF3B82F6),
              onTap: () => _onMenuSelected('group_call_history'),
            ),
            const SizedBox(width: 6),
            // FIX-4: constrain SentimentIndicatorWidget height
            SizedBox(
              height: 26,
              child: SentimentIndicatorWidget(groupChatId: groupChatId),
            ),
          ],
        ),
      ),
    );
  }

  Color _appBarColorFromMode(ThemePalette p) => switch (_bubbleCtx.mode) {
    BubbleMode.work => const Color(0xFF162032),
    BubbleMode.secure => const Color(0xFF0A0E1A),
    BubbleMode.media => const Color(0xFF880E4F),
    BubbleMode.location => const Color(0xFF1B5E20),
    BubbleMode.shared => const Color(0xFF311B92),
    _ => p.appBarBackground,
  };

  // ══════════════════════════════════════════════════════════════════════════
  // CHAT CONTENT
  // ══════════════════════════════════════════════════════════════════════════
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
          final diff =
              (int.parse(prev['timestamp'] ?? '0') -
                      int.parse(msg['timestamp'] ?? '0'))
                  .abs();
          if (msg['idFrom'] == prev['idFrom'] && diff <= 10000) {
            mediaGroup.add(msg);
          } else {
            grouped.add(
              mediaGroup.length == 1
                  ? mediaGroup.first
                  : {'isMediaGroup': true, 'messages': List.from(mediaGroup)},
            );
            mediaGroup
              ..clear()
              ..add(msg);
          }
        }
      } else {
        if (mediaGroup.isNotEmpty) {
          grouped.add(
            mediaGroup.length == 1
                ? mediaGroup.first
                : {'isMediaGroup': true, 'messages': List.from(mediaGroup)},
          );
          mediaGroup.clear();
        }
        grouped.add(msg);
      }
    }
    if (mediaGroup.isNotEmpty) {
      grouped.add(
        mediaGroup.length == 1
            ? mediaGroup.first
            : {'isMediaGroup': true, 'messages': List.from(mediaGroup)},
      );
    }
    return grouped;
  }

  Widget _buildChatContent(ThemePalette p, ThemeProvider theme) {
    return ChatWallpaperWidget(
      wallpaper: theme.chatWallpaper,
      color: theme.primaryColor,
      opacity: theme.chatWallpaperOpacity,
      child: Stack(
        children: [
          Column(
            children: [
              const OfflineIndicator(),
              if (_activeReminderCount > 0)
                StreamBuilder<List<EnhancedReminder>>(
                  stream: _convoReminderStream,
                  builder: (_, snap) {
                    final list = (snap.data ?? []).take(3).toList();
                    if (list.isEmpty) return const SizedBox.shrink();
                    return InlinePendingRemindersBar(
                      reminders: list,
                      palette: p,
                      primaryColor: theme.primaryColor,
                      onViewAll: _openRemindersPage,
                    );
                  },
                ),
              if (_showExtractPanel && _pendingExtracted.isNotEmpty)
                AiReminderSuggestionPanel(
                  extracted: _pendingExtracted,
                  palette: p,
                  primaryColor: theme.primaryColor,
                  onAccept: _acceptExtracted,
                  onDismissAll: () => setState(() {
                    _showExtractPanel = false;
                    _pendingExtracted = [];
                  }),
                ),
              GroupCallStatusBanner(
                groupId: groupChatId,
                currentUserId: _currentUserId,
                currentUserName: _memberNames[_currentUserId] ?? 'Bạn',
                currentUserAvatar: _avatarUrlCache[_currentUserId] ?? '',
              ),
              if (_pinnedMessages.isNotEmpty) _buildPinnedBanner(p, theme),
              // FIX-5: AnimatedSize instead of SizeTransition+setState
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: _showAIContextBar
                    ? _buildAIContextBar(p, theme)
                    : const SizedBox.shrink(),
              ),
              _buildListMessage(p, theme),
              _buildTypingIndicator(p, theme),
              if (_isShowSticker) _buildStickers(p, theme),
              if (_showFeaturesMenu) _buildFeaturesMenu(p, theme),
              if (_showAIPanel) _buildAIActionPanel(p, theme),
              if (!_isShowingSwipeCards) _buildInput(p, theme),
            ],
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: Center(
                  child: CircularProgressIndicator(
                    color: theme.primaryColor,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            ),
          if (_isLoadingMedia)
            Positioned.fill(child: _buildMediaOverlay(p, theme)),
          if (_isShowingSwipeCards)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SwipeReplyCards(
                replies: _swipeReplies,
                richItems: _swipeRichItems.isNotEmpty ? _swipeRichItems : null,
                onSend: (payload, msgType) async {
                  await _onSendMessage(payload, msgType);
                  if (mounted)
                    setState(() {
                      _isShowingSwipeCards = false;
                      _swipeRichItems = [];
                    });
                },
                onCancel: () {
                  if (mounted)
                    setState(() {
                      _isShowingSwipeCards = false;
                      _swipeRichItems = [];
                    });
                },
              ),
            ),
          Positioned(
            right: 12,
            bottom: _isShowingSwipeCards ? 200 : 90,
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: _fabAnim,
                curve: Curves.elasticOut,
              ),
              child: GestureDetector(
                onTap: () => _listScrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                ),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: p.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: p.shadow,
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: p.textSecondary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PINNED BANNER
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPinnedBanner(ThemePalette p, ThemeProvider theme) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.96),
        border: Border(
          bottom: BorderSide(
            color: p.divider.withValues(alpha: 0.5),
            width: .8,
          ),
        ),
        boxShadow: [
          BoxShadow(color: p.shadow.withValues(alpha: 0.06), blurRadius: 4),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 28,
            margin: const EdgeInsets.only(left: 12, right: 8),
            decoration: BoxDecoration(
              color: theme.primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Icon(Icons.push_pin_rounded, size: 14, color: theme.primaryColor),
          const SizedBox(width: 6),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pinnedMessages.length,
              itemBuilder: (_, i) {
                final message = MessageChat.fromDocument(_pinnedMessages[i]);
                return GestureDetector(
                  onTap: () => _scrollToMessage(_pinnedMessages[i].id),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    margin: const EdgeInsets.only(right: 10),
                    child: Text(
                      message.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _pinnedMessages = []),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.close_rounded, size: 16, color: p.textHint),
            ),
          ),
        ],
      ),
    );
  }

  // FIX-5/6: No SizeTransition inside; parent AnimatedSize handles open/close animation
  Widget _buildAIContextBar(ThemePalette p, ThemeProvider theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.primaryColor.withValues(alpha: 0.18),
                width: .8,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFF8B5CF6), theme.primaryColor],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AI Nhận biết',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        'Đang theo dõi ngữ cảnh nhóm...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _showSummaryAnalysis,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Xem',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.primaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // FIX-6: simple setState, AnimatedSize handles animation
                GestureDetector(
                  onTap: () => setState(() => _showAIContextBar = false),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: p.textHint,
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

  Widget _buildAIActionPanel(ThemePalette p, ThemeProvider theme) {
    final actions = [
      _AIAction(
        Icons.edit_note_rounded,
        'Viết lại',
        _showToneRewriter,
        const Color(0xFF8B5CF6),
      ),
      _AIAction(Icons.translate_rounded, 'Dịch', () {
        final t = _chatInputController.text.trim();
        if (t.isNotEmpty) _translateMessage(t);
      }, const Color(0xFF0EA5E9)),
      _AIAction(
        Icons.summarize_rounded,
        'Tóm tắt',
        _showSummaryAnalysis,
        const Color(0xFF10B981),
      ),
      _AIAction(
        Icons.reply_rounded,
        'Gợi ý',
        _triggerZeroTypeSwipe,
        const Color(0xFFF59E0B),
      ),
      _AIAction(
        Icons.smart_toy_rounded,
        'AutoPilot',
        _showAutoPilotSheet,
        const Color(0xFFEC4899),
      ),
      _AIAction(
        Icons.alarm_add_rounded,
        'Nhắc nhở',
        _openRemindersPage,
        const Color(0xFF6366F1),
      ),
    ];
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
            CurvedAnimation(parent: _aiPanelAnim, curve: Curves.easeOutBack),
          ),
      child: Container(
        height: 44,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: actions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final a = actions[i];
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                a.onTap();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: a.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: a.color.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.icon, size: 14, color: a.color),
                    const SizedBox(width: 5),
                    Text(
                      a.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: a.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
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
          boxShadow: [BoxShadow(color: p.shadowStrong, blurRadius: 16)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: theme.primaryColor,
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 16),
            Text(
              'Đang tải lên...',
              style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // MESSAGE LIST  (PERF-1..7 applied)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildListMessage(ThemePalette p, ThemeProvider theme) {
    return Flexible(
      child: groupChatId.isNotEmpty
          ? ValueListenableBuilder(
              valueListenable: LocalDbService().messagesBox.listenable(),
              builder: (context, Box box, _) {
                final all = LocalDbService().getMessages(groupChatId);
                final display = all.take(_limit).toList();

                // PERF-1: cache grouped result
                final cacheKey =
                    '${display.length}_${display.isEmpty ? '' : display.first['timestamp']}';
                if (_processCacheKey != cacheKey || _cachedGrouped == null) {
                  _cachedGrouped = _processMessages(display);
                  _processCacheKey = cacheKey;
                }
                final grouped = _cachedGrouped!;

                if (grouped.isEmpty) return _buildEmptyState(p, theme);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  itemCount: grouped.length,
                  reverse: true,
                  controller: _listScrollController,
                  cacheExtent: 800, // PERF-4: smooth fling
                  addAutomaticKeepAlives: false, // PERF-3: save RAM
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemBuilder: (_, index) {
                    final item = grouped[index];
                    Widget child;
                    if (item is Map && item['isMediaGroup'] == true) {
                      child = _buildMediaGroup(
                        List<Map<dynamic, dynamic>>.from(item['messages']),
                        p,
                        theme,
                      );
                    } else {
                      child = _buildItemMessage(
                        index,
                        item as Map<dynamic, dynamic>,
                        display,
                        p,
                        theme,
                      );
                    }
                    return RepaintBoundary(child: child); // PERF-5
                  },
                );
              },
            )
          : Center(
              child: CircularProgressIndicator(
                color: theme.primaryColor,
                strokeWidth: 2,
              ),
            ),
    );
  }

  Widget _buildEmptyState(ThemePalette p, ThemeProvider theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            key: const ValueKey('empty_anim'), // PERF-6: stable key
            tween: Tween(begin: 0.7, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.primaryLightColor, theme.primaryColor],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Chưa có tin nhắn',
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hãy chào cả nhóm! 👋',
            style: TextStyle(color: p.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            children: [
              _QuickStartChip(
                '👋 Xin chào!',
                () => _onSendMessage('Xin chào! 👋', TypeMessage.text),
                theme.primaryColor,
                p,
              ),
              _QuickStartChip(
                '📍 Chia sẻ vị trí',
                _shareLocation,
                const Color(0xFF10B981),
                p,
              ),
              _QuickStartChip(
                '🎮 Chơi game',
                _openGameCenter,
                const Color(0xFF8B5CF6),
                p,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MESSAGE BUILDERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildMediaGroup(
    List<Map<dynamic, dynamic>> messages,
    ThemePalette p,
    ThemeProvider theme,
  ) {
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
      isRead: first['status'] == 'sent',
    );
    return SwipeToReplyWrapper(
      isMe: isMe,
      onSwipe: () => _setReply(representative, msgId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMe) _buildSenderName(first['idFrom'] as String? ?? '', p),
            Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  _buildGroupAvatar(first['idFrom'] as String? ?? '', theme),
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
                                    ),
                                  )
                                : Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          FullPhotoPage(url: thumbUrl),
                                    ),
                                  );
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                thumbUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Container(color: p.surfaceVariant),
                              ),
                              if (isVideo)
                                const Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
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
            _buildTimestamp(first['timestamp'] ?? '', isMe, p, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildItemMessage(
    int index,
    Map<dynamic, dynamic> localData,
    List<Map<dynamic, dynamic>> fullList,
    ThemePalette p,
    ThemeProvider theme,
  ) {
    final isHighlighted = _pendingScrollToMessageId == localData['messageId'];
    final isPending = localData['status'] == 'pending';
    final msg = MessageChat(
      idFrom: localData['idFrom'] ?? '',
      idTo: localData['idTo'] ?? '',
      timestamp: localData['timestamp'] ?? '',
      content: localData['content'] ?? '',
      type: localData['type'] ?? 0,
      isRead: localData['status'] == 'sent',
      matchId: localData['matchId'] as String?,
      gameType: localData['gameType'] as String?,
      matchStatus: localData['matchStatus'] as String?,
    );
    bool isLastInGroup = true;
    if (index > 0) isLastInGroup = fullList[index - 1]['idFrom'] != msg.idFrom;
    final isMe = msg.idFrom == _currentUserId;
    final messageId = localData['messageId'] ?? '';

    Widget? sep;
    if (index == fullList.length - 1 ||
        !_sameDay(
          DateTime.fromMillisecondsSinceEpoch(int.tryParse(msg.timestamp) ?? 0),
          DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(fullList[index + 1]['timestamp'] ?? '0') ?? 0,
          ),
        )) {
      sep = _DateDivider(
        date: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(msg.timestamp) ?? 0,
        ),
        palette: p,
      );
    }

    Widget? special = _buildSpecialMessage(
      msg,
      messageId,
      isMe,
      isLastInGroup,
      localData,
      p,
      theme,
    );
    if (special != null) {
      return Column(
        children: [
          SwipeToReplyWrapper(
            isMe: isMe,
            onSwipe: () => _setReply(msg, messageId),
            child: special,
          ),
          if (sep != null) sep,
        ],
      );
    }

    Widget bubble;
    if (msg.type == 3 && _voiceProvider != null) {
      bubble = _buildVoiceMessage(msg, isMe, p, theme);
    } else if (msg.type == TypeMessage.image) {
      bubble = _buildImageMessage(
        messageId,
        msg,
        isMe,
        isLastInGroup,
        isPending,
        p,
        theme,
      );
    } else if (msg.type == TypeMessage.video) {
      bubble = _buildVideoMessage(
        messageId,
        msg,
        isMe,
        isLastInGroup,
        isPending,
        p,
        theme,
      );
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
        theme: theme,
      );
    }
    return Column(
      children: [
        SwipeToReplyWrapper(
          isMe: isMe,
          onSwipe: () => _setReply(msg, messageId),
          child: bubble,
        ),
        if (sep != null) sep,
      ],
    );
  }

  Widget? _buildSpecialMessage(
    MessageChat msg,
    String messageId,
    bool isMe,
    bool isLastInGroup,
    Map<dynamic, dynamic> localData,
    ThemePalette p,
    ThemeProvider theme,
  ) {
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
        ],
      ),
    );

    if (msg.type == TypeMessage.gameInvite ||
        msg.type == TypeMessage.gameLive) {
      return wrapRow(
        GameInviteCardBubble(
          message: msg,
          currentUserId: _currentUserId,
          currentUserName: _memberNames[_currentUserId] ?? 'Bạn',
          currentUserAvatar: _avatarUrlCache[_currentUserId] ?? '',
          groupId: groupChatId,
        ),
      );
    }
    if (msg.type == TypeMessage.gameResult) {
      return wrapRow(
        GameResultCardBubble(
          message: msg,
          currentUserId: _currentUserId,
          currentUserName: _memberNames[_currentUserId] ?? 'Bạn',
          currentUserAvatar: _avatarUrlCache[_currentUserId] ?? '',
          groupId: groupChatId,
        ),
      );
    }
    if (localData['isViewOnce'] ?? false) {
      return wrapRow(
        ViewOnceMessageWidget(
          groupChatId: groupChatId,
          messageId: messageId,
          content: msg.content,
          type: msg.type,
          currentUserId: _currentUserId,
          isViewed: localData['isViewed'] ?? false,
          provider: _viewOnceProvider,
        ),
      );
    }
    if (msg.type == TypeMessage.geoLocked) {
      return Container(
        margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMe && isLastInGroup) _buildSenderName(msg.idFrom, p),
            Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  isLastInGroup
                      ? _buildGroupAvatar(msg.idFrom, theme)
                      : const SizedBox(width: 36),
                GestureDetector(
                  onLongPress: () => _showMessageOptions(msg, messageId),
                  child: GeoLockedMessageWidget(
                    content: msg.content,
                    isMe: isMe,
                  ),
                ),
              ],
            ),
            _buildTimestamp(msg.timestamp, isMe, p, theme),
          ],
        ),
      );
    }
    if (msg.type == 7)
      return wrapRow(
        TicTacToeMessageWidget(
          content: msg.content,
          messageId: messageId,
          groupId: groupChatId,
          currentUserId: _currentUserId,
        ),
      );
    if (msg.type == 8)
      return wrapRow(BlowMessageWidget(secretText: msg.content));
    if (msg.type == 9)
      return wrapRow(ShakeMessageWidget(secretText: msg.content));
    if (msg.type == TypeMessage.poll) {
      String pollContent = localData['content'] as String? ?? msg.content;
      final rawOptions = localData['options'];
      if (rawOptions != null) {
        try {
          final pollMap = jsonDecode(pollContent) as Map<String, dynamic>;
          pollMap['options'] = rawOptions;
          pollContent = jsonEncode(pollMap);
        } catch (_) {}
      }
      return wrapRow(
        PollMessageWidget(
          content: pollContent,
          messageId: messageId,
          currentUserId: _currentUserId,
          onVote: (mId, optionId) => _chatProvider.votePoll(
            groupChatId: groupChatId,
            messageId: messageId,
            optionId: optionId,
            userId: _currentUserId,
          ),
        ),
      );
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * .7,
                ),
                decoration: BoxDecoration(
                  color: isMe ? p.outgoingBubble : p.incomingBubble,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.divider, width: .8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.insert_drive_file_rounded,
                        color: theme.primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileData['name'] as String? ?? 'File',
                            style: TextStyle(
                              color: isMe ? Colors.white : p.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${((fileData['size'] as num? ?? 0) / 1024).toStringAsFixed(1)} KB',
                            style: TextStyle(
                              color: isMe ? Colors.white70 : p.textSecondary,
                              fontSize: 12,
                            ),
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
    if (msg.type == GroupCallMessageTypes.groupCallInvite ||
        msg.type == GroupCallMessageTypes.groupCallEnded ||
        msg.type == GroupCallMessageTypes.groupCallMissed) {
      try {
        final content = jsonDecode(msg.content) as Map<String, dynamic>;
        if (GroupCallMessageHelper.isGroupCallMessage(content)) {
          return Container(
            margin: EdgeInsets.only(bottom: isLastInGroup ? 12 : 4),
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe && isLastInGroup && theme.showAvatarsInChat)
                  _buildGroupAvatar(msg.idFrom, theme)
                else if (!isMe && theme.showAvatarsInChat)
                  const SizedBox(width: 36),
                GroupCallInviteBubble(
                  callId: GroupCallMessageHelper.getCallId(content),
                  callType: GroupCallMessageHelper.getCallType(content),
                  initiatorName: content['initiatorName'] ?? '',
                  groupName: widget.group.groupName,
                  groupAvatarUrl: widget.group.groupPhotoUrl,
                  createdAt: DateTime.fromMillisecondsSinceEpoch(
                    int.tryParse(msg.timestamp) ?? 0,
                  ),
                  isSentByMe: isMe,
                  currentUserId: _currentUserId,
                  currentUserName: _memberNames[_currentUserId] ?? 'Bạn',
                  currentUserAvatar: _avatarUrlCache[_currentUserId] ?? '',
                ),
              ],
            ),
          );
        }
      } catch (e) {
        debugPrint('⚠️ GroupCallBubble parse: $e');
      }
    }
    return null;
  }

  Widget _buildSenderName(String senderId, ThemePalette p) {
    if (senderId == _currentUserId) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 40, bottom: 3),
      child: Text(
        _getSenderName(senderId),
        style: TextStyle(
          color: p.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
          colors: [theme.primaryLightColor, theme.primaryColor],
        ),
        image: photoUrl.isNotEmpty
            ? DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: photoUrl.isEmpty
          ? Center(
              child: Text(
                name.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            )
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
    final hasUrl =
        !msg.isDeleted &&
        msg.type == TypeMessage.text &&
        location == null &&
        UrlDetector.containsUrl(msg.content);
    Widget bubble = Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 10 : 3),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!isMe && isLastInGroup && theme.showAvatarsInChat)
            _buildSenderName(msg.idFrom, p),
          Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
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
                      maxWidth:
                          MediaQuery.of(context).size.width *
                          (hasUrl ? 0.84 : theme.bubbleMaxWidthFactor),
                    ),
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
                                ? theme.primaryColor.withValues(alpha: 0.18)
                                : p.shadow.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe && isScamWarning)
                            _GroupScamBanner(reason: scamReason, palette: p),
                          if (!isMe && isToxic)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: ToxicMessageBadge(
                                category: toxicCategory,
                                showDetails: true,
                              ),
                            ),
                          if (!isMe && hasReminder)
                            _GroupReminderBanner(
                              msg: msg,
                              messageId: messageId,
                              onSet: _setReminder,
                              palette: p,
                              theme: theme,
                            ),
                          if (msg.isDeleted)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.block_rounded,
                                  size: 14,
                                  color: isMe
                                      ? Colors.white38
                                      : p.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Tin nhắn đã xóa',
                                  style: TextStyle(
                                    color: isMe
                                        ? Colors.white38
                                        : p.textSecondary,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 14 * fs,
                                  ),
                                ),
                              ],
                            )
                          else if (location != null)
                            _GroupLocationContent(
                              location: location,
                              isMe: isMe,
                              palette: p,
                              theme: theme,
                              onOpen: () =>
                                  _openLocationInMaps(location.mapsUrl),
                            )
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.content,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : p.incomingText,
                                    fontSize: 15 * fs,
                                    height: 1.35,
                                  ),
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
                                        color: msg.isRead
                                            ? Colors.white
                                            : Colors.white38,
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
              ),
            ],
          ),
          if (!isMe && msg.type == TypeMessage.text) ...[
            if (_scamResults[messageId] != null &&
                _scamResults[messageId] != 'SAFE')
              Padding(
                padding: EdgeInsets.only(
                  left: theme.showAvatarsInChat ? 42 : 4,
                ),
                child: ScamWarningWidget(status: _scamResults[messageId]!),
              ),
            if (_scamResults[messageId] == null && !isScamWarning)
              Padding(
                padding: EdgeInsets.only(
                  left: theme.showAvatarsInChat ? 42 : 4,
                  top: 3,
                ),
                child: GestureDetector(
                  onTap: () async {
                    _showToast('🛡 Đang quét...');
                    final status = await AIBackendService().checkScam(
                      msg.content,
                    );
                    if (mounted)
                      setState(
                        () =>
                            _scamResults[messageId] = status.name.toUpperCase(),
                      );
                    if (status.name.toUpperCase() == 'SAFE')
                      _showToast('✅ Tin nhắn an toàn', isSuccess: true);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 13,
                        color: p.successColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Quét AI',
                        style: TextStyle(fontSize: 11.5, color: p.successColor),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          _buildReactions(messageId, isMe, p, theme),
          _buildTimestamp(msg.timestamp, isMe, p, theme),
        ],
      ),
    );
    if (!isHighlighted) return bubble;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: bubble,
    );
  }

  Widget _buildImageMessage(
    String messageId,
    MessageChat msg,
    bool isMe,
    bool isLastInGroup,
    bool isPending,
    ThemePalette p,
    ThemeProvider theme,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 10 : 3),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!isMe && isLastInGroup && theme.showAvatarsInChat)
            _buildSenderName(msg.idFrom, p),
          Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
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
                        builder: (_) => FullPhotoPage(url: msg.content),
                      ),
                    );
                  }
                },
                onLongPress: () => _showMessageOptions(msg, messageId),
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
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : Image.network(
                            msg.content,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, prog) => prog == null
                                ? child
                                : Container(
                                    color: p.surfaceVariant,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: theme.primaryColor,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                            errorBuilder: (_, __, ___) => Container(
                              color: p.surfaceVariant,
                              child: Icon(
                                Icons.broken_image_rounded,
                                color: p.textHint,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          _buildReactions(messageId, isMe, p, theme),
          _buildTimestamp(msg.timestamp, isMe, p, theme),
        ],
      ),
    );
  }

  Widget _buildVideoMessage(
    String messageId,
    MessageChat msg,
    bool isMe,
    bool isLastInGroup,
    bool isPending,
    ThemePalette p,
    ThemeProvider theme,
  ) {
    final parts = msg.content.split('|');
    final videoUrl = parts.isNotEmpty ? parts[0] : '';
    final thumbUrl = parts.length > 1 ? parts[1] : '';
    return Container(
      margin: EdgeInsets.only(bottom: isLastInGroup ? 10 : 3),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          if (!isPending)
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerPage(videoUrl: videoUrl),
              ),
            );
        },
        onLongPress: () => _showMessageOptions(msg, messageId),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * .62,
            height: 195,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbUrl.isNotEmpty)
                  Image.network(
                    thumbUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: Colors.black),
                  )
                else
                  const ColoredBox(color: Colors.black),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: .6),
                      ],
                    ),
                  ),
                ),
                if (isPending)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                else
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.videocam_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'Video',
                          style: TextStyle(fontSize: 10, color: Colors.white),
                        ),
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

  Widget _buildVoiceMessage(
    MessageChat msg,
    bool isMe,
    ThemePalette p,
    ThemeProvider theme,
  ) {
    return Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!isMe) _buildSenderName(msg.idFrom, p),
        Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) _buildGroupAvatar(msg.idFrom, theme),
            const SizedBox(width: 4),
            VoiceMessageWidget(
              voiceUrl: msg.content,
              isMyMessage: isMe,
              voiceProvider: _voiceProvider!,
            ),
          ],
        ),
        _buildTimestamp(msg.timestamp, isMe, p, theme),
      ],
    );
  }

  Widget _buildStickerMessage(
    MessageChat msg,
    bool isMe,
    String messageId,
    ThemePalette p,
    ThemeProvider theme,
  ) {
    return Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!isMe) _buildSenderName(msg.idFrom, p),
        Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!isMe) _buildGroupAvatar(msg.idFrom, theme),
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
                  color: p.surfaceVariant,
                  child: Icon(Icons.error_rounded, color: p.textHint),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReactions(
    String messageId,
    bool isMe,
    ThemePalette p,
    ThemeProvider theme,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: _reactionProvider.getReactions(groupChatId, messageId),
      builder: (_, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty)
          return const SizedBox.shrink();
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
          padding: EdgeInsets.only(
            left: isMe ? 0 : (theme.showAvatarsInChat ? 42 : 4),
            top: 2,
          ),
          child: MessageReactionsDisplay(
            reactions: reactions,
            currentUserId: _currentUserId,
            userReactions: userReactions,
            onReactionTap: (emoji) => _reactionProvider.toggleReaction(
              groupChatId,
              messageId,
              _currentUserId,
              emoji,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimestamp(
    String ts,
    bool isMe,
    ThemePalette p,
    ThemeProvider theme,
  ) {
    String label = '';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
      label = DateTime.now().difference(dt).inDays == 0
          ? DateFormat('HH:mm').format(dt)
          : DateFormat('dd/MM HH:mm').format(dt);
    } catch (_) {}
    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 0 : (theme.showAvatarsInChat ? 44 : 4),
        right: isMe ? 4 : 0,
        bottom: 2,
      ),
      child: Text(label, style: TextStyle(fontSize: 10.5, color: p.textHint)),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TYPING INDICATOR / MENTIONS / STICKERS / FEATURES MENU
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTypingIndicator(ThemePalette p, ThemeProvider theme) {
    if (_presenceProvider == null) return const SizedBox.shrink();
    return StreamBuilder<Map<String, TypingInfo>>(
      stream: _presenceProvider!.getTypingStatusStream(groupChatId),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final typing = snap.data!.entries
            .where((e) => e.key != _currentUserId && e.value.isTyping)
            .toList();
        if (typing.isEmpty) return const SizedBox.shrink();
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                const BubbleTypingIndicator.chat(),
                const SizedBox(width: 8),
                Text(
                  typing.length == 1
                      ? '${_getSenderName(typing.first.key)} đang nhập…'
                      : '${typing.length} người đang nhập…',
                  style: TextStyle(
                    fontSize: 12,
                    color: p.textHint,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        );
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
            offset: const Offset(0, 4),
          ),
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
          if (userId.isEmpty || name.isEmpty) return const SizedBox.shrink();
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
              child: Text(
                name.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              '@$name',
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => _insertMention(userId, name),
          );
        },
      ),
    );
  }

  Widget _buildStickers(ThemePalette p, ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.divider, width: .8)),
      ),
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
                  'mimi${row * 3 + col + 1}',
                  TypeMessage.sticker,
                ),
                child: Image.asset(
                  'images/mimi${row * 3 + col + 1}.gif',
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturesMenu(ThemePalette p, ThemeProvider theme) {
    final items = [
      _GFeatureItem(
        Icons.image_rounded,
        'Ảnh',
        _onPickImage,
        theme.primaryColor,
      ),
      _GFeatureItem(
        Icons.videocam_rounded,
        'Video',
        _onPickVideo,
        const Color(0xFFFF6B9D),
      ),
      _GFeatureItem(
        Icons.add_location_alt_rounded,
        'GeoLock',
        _sendGeoLockedMessage,
        p.dangerColor,
      ),
      _GFeatureItem(Icons.games_rounded, 'Caro', () {
        setState(() => _showFeaturesMenu = false);
        _onSendMessage(
          jsonEncode({
            'board': List.filled(9, ''),
            'turn': '',
            'winner': '',
            'playerX': '',
            'playerO': '',
          }),
          7,
        );
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
          builder: (_) => CreatePollDialog(
            onCreate:
                (
                  question,
                  options, {
                  bool isMultipleChoice = false,
                  bool isAnonymous = false,
                  DateTime? expiresAt,
                }) {
                  final opts = options
                      .asMap()
                      .entries
                      .map(
                        (e) => {
                          'id': e.key.toString(),
                          'text': e.value,
                          'votes': <String>[],
                        },
                      )
                      .toList();
                  _onSendMessage(
                    jsonEncode({
                      'question': question,
                      'options': opts,
                      'isMultipleChoice': isMultipleChoice,
                      'isAnonymous': isAnonymous,
                      if (expiresAt != null)
                        'expiresAt': expiresAt.toIso8601String(),
                    }),
                    TypeMessage.poll,
                  );
                },
          ),
        );
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
            conversationId: groupChatId,
            provider: _autoDeleteProvider,
          ),
        );
      }, p.textSecondary),
      _GFeatureItem(Icons.location_on_rounded, 'Vị trí', () {
        setState(() => _showFeaturesMenu = false);
        _shareLocation();
      }, p.dangerColor),
      _GFeatureItem(Icons.schedule_send_rounded, 'Lên lịch', () {
        setState(() => _showFeaturesMenu = false);
        _scheduleMessage();
      }, const Color(0xFF43C6AC)),
      _GFeatureItem(Icons.bubble_chart_rounded, 'Bubble', () {
        setState(() => _showFeaturesMenu = false);
        _createGroupBubble();
      }, theme.primaryColor),
      _GFeatureItem(Icons.video_call_rounded, 'Gọi nhóm', () async {
        setState(() => _showFeaturesMenu = false);
        _menuAnim.reverse();
        final provider = context.read<GroupCallProvider>();
        final call = await provider.startCall(
          groupId: groupChatId,
          groupName: widget.group.groupName,
          groupAvatarUrl: widget.group.groupPhotoUrl,
          memberIds: widget.group.memberIds,
          callType: GroupCallType.video,
        );
        if (call != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupCallPage(
                call: call,
                isInitiator: true,
                currentUserId: _currentUserId,
                currentUserName: _memberNames[_currentUserId] ?? 'Bạn',
                currentUserAvatar: _avatarUrlCache[_currentUserId] ?? '',
              ),
            ),
          );
        }
      }, const Color(0xFF3B82F6)),
      _GFeatureItem(Icons.alarm_add_rounded, 'Nhắc nhở', () {
        setState(() => _showFeaturesMenu = false);
        _openRemindersPage();
      }, const Color(0xFF6366F1)),
      _GFeatureItem(Icons.sports_esports_rounded, 'Game', () {
        setState(() => _showFeaturesMenu = false);
        _openGameCenter();
      }, const Color(0xFF9C27B0)),
    ];
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _menuAnim, curve: Curves.easeOutCubic)),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: p.surface.withValues(alpha: 0.97),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(
                top: BorderSide(
                  color: p.divider.withValues(alpha: 0.6),
                  width: .8,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: p.shadow.withValues(alpha: 0.12),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: p.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      children: items
                          .map((item) => _FeatureMenuTile(item: item, p: p))
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INPUT — 2026 unified bar  [+] [emoji] [TextField] [✨AI] [🎤/Send]
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildInput(ThemePalette p, ThemeProvider theme) {
    final fs = theme.fontSizeMultiplier;
    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        left: 10,
        right: 10,
        top: 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_autoPilotProvider != null)
            AutoPilotInputStatusBar(
              conversationId: groupChatId,
              currentUserId: _currentUserId,
              isGroup: true,
            ),
          // Smart Reply Bar
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _buildSmartReplyBar(p, theme),
          ),
          // Reply preview
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
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
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border(
                          left: BorderSide(color: theme.primaryColor, width: 3),
                        ),
                        boxShadow: [BoxShadow(color: p.shadow, blurRadius: 6)],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Trả lời $_replyingToSenderName',
                                  style: TextStyle(
                                    color: theme.primaryColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _replyingTo!.content,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: p.textSecondary,
                                  ),
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
                              _replyAnim.reverse();
                            },
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: p.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          // Recording indicator
          if (_isRecording)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.dangerColor.withValues(alpha: .4)),
              ),
              child: Row(
                children: [
                  _RecDot(color: p.dangerColor),
                  const SizedBox(width: 8),
                  Text(
                    'Đang ghi âm  $_recordingDuration',
                    style: TextStyle(
                      color: p.dangerColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _cancelRecording,
                    child: Icon(
                      Icons.delete_rounded,
                      color: p.dangerColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _stopRecording,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // ── Unified Input Bar ──────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: _focusNode.hasFocus
                    ? theme.primaryColor.withValues(alpha: 0.4)
                    : p.inputBorder,
                width: _focusNode.hasFocus ? 1.2 : .7,
              ),
              boxShadow: [
                BoxShadow(
                  color: _focusNode.hasFocus
                      ? theme.primaryColor.withValues(alpha: 0.10)
                      : p.shadow,
                  blurRadius: _focusNode.hasFocus ? 16 : 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // [+] Attachment
                _InputIconBtn(
                  icon: _showFeaturesMenu
                      ? Icons.close_rounded
                      : Icons.add_rounded,
                  color: _showFeaturesMenu ? p.dangerColor : theme.primaryColor,
                  onTap: _toggleFeaturesMenu,
                  rotate: _showFeaturesMenu,
                ),
                // Sticker
                if (!_showFeaturesMenu)
                  _InputIconBtn(
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    color: _isShowSticker ? theme.primaryColor : p.textHint,
                    onTap: _getSticker,
                  ),
                // TextField
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.only(
                      right: 4,
                      top: 11,
                      bottom: 11,
                    ),
                    child: TextField(
                      controller: _chatInputController,
                      focusNode: _focusNode,
                      style: TextStyle(fontSize: 15 * fs, color: p.textPrimary),
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      onTapOutside: (_) => Utilities.closeKeyboard(),
                      decoration: InputDecoration.collapsed(
                        hintText: 'Nhắn tin... (@đề cập)',
                        hintStyle: TextStyle(
                          color: p.textHint,
                          fontSize: 15 * fs,
                        ),
                      ),
                      onChanged: _handleTextChange,
                    ),
                  ),
                ),
                // AI Magic button
                _InputIconBtn(
                  icon: Icons.auto_awesome,
                  color: const Color(0xFF8B5CF6),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _showAIPanel = !_showAIPanel);
                    _showAIPanel
                        ? _aiPanelAnim.forward()
                        : _aiPanelAnim.reverse();
                  },
                ),
                // Mic / Send morphing button
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _chatInputController,
                    builder: (_, val, __) {
                      final hasText = val.text.trim().isNotEmpty;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          if (hasText) {
                            _onSendMessage(
                              _chatInputController.text,
                              TypeMessage.text,
                            );
                          } else {
                            _startRecording();
                          }
                        },
                        onLongPress: !hasText
                            ? () {
                                HapticFeedback.mediumImpact();
                                _triggerZeroTypeSwipe();
                              }
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
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
                                      color: theme.primaryColor.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : null,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
                            child: Icon(
                              hasText ? Icons.send_rounded : Icons.mic_rounded,
                              key: ValueKey(hasText),
                              color: hasText ? Colors.white : p.textHint,
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
    );
  }

  Widget _buildSmartReplyBar(ThemePalette p, ThemeProvider theme) {
    final result = _smartReplyResult;
    final show = _isLoadingSmartReply || (result != null && result.isNotEmpty);
    if (!show) return const SizedBox.shrink();
    return SmartReplyTray(
      items: result?.merged ?? const [],
      isLoading: _isLoadingSmartReply,
      onDismiss: () {
        if (mounted && !resourceManager.isDisposed)
          setState(() => _smartReplyResult = null);
      },
      onSelect: (payload, msgType) {
        if (resourceManager.isDisposed) return;
        if (msgType == TypeMessage.sticker) {
          _onSendMessage(payload, TypeMessage.sticker);
          if (mounted) setState(() => _smartReplyResult = null);
        } else {
          _chatInputController.text = payload;
          _focusNode.requestFocus();
          if (mounted) setState(() => _smartReplyResult = null);
        }
      },
    );
  }
} // end GroupChatPageState
// ═══════════════════════════════════════════════════════════════════════════
// PRIVATE SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

// ── AppBar icon button with optional badge ───────────────────────────────
class _AppBarIconBtn extends StatelessWidget {
  const _AppBarIconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
    this.appBarBackground,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int badgeCount;
  final Color? appBarBackground;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: color, size: 22),
            if (badgeCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: appBarBackground ?? Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
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

// ── Chip in appbar row ────────────────────────────────────────────────────
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.20), width: .7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Bubble mode badge ─────────────────────────────────────────────────────
class _BubbleModeBadge extends StatelessWidget {
  const _BubbleModeBadge({required this.mode});
  final BubbleMode mode;
  String get _emoji => switch (mode) {
    BubbleMode.work => '💼',
    BubbleMode.media => '🎵',
    BubbleMode.location => '📍',
    BubbleMode.secure => '🔒',
    BubbleMode.shared => '🎨',
    _ => '💬',
  };
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 5),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(_emoji, style: const TextStyle(fontSize: 11)),
  );
}

// ── Typing dots animation ─────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 12,
    child: AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(3, (i) {
          final offset = i / 3;
          final v = ((_ctrl.value - offset) % 1.0).clamp(0.0, 1.0);
          final scale = (v < 0.5 ? (1.0 + v) : (2.0 - v)).clamp(1.0, 1.5);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.7 + v * 0.3),
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    ),
  );
}

// ── More Bottom Sheet ─────────────────────────────────────────────────────
class _MoreBottomSheet extends StatelessWidget {
  const _MoreBottomSheet({
    required this.palette,
    required this.primary,
    required this.bubbleCtx,
    required this.onSelected,
    this.activeReminderCount = 0,
  });
  final ThemePalette palette;
  final Color primary;
  final BubbleContext bubbleCtx;
  final int activeReminderCount;
  final void Function(String) onSelected;

  static const _sections = [
    [
      _SheetItem(
        'autopilot',
        Icons.smart_toy_rounded,
        'AutoPilot',
        Color(0xFF8B5CF6),
        'Tự động trả lời',
      ),
      _SheetItem(
        'ai_assistant',
        Icons.auto_awesome,
        'AI Assistant',
        Color(0xFF8B5CF6),
        'Phân tích nhóm',
      ),
      _SheetItem(
        'summarize',
        Icons.summarize_rounded,
        'Tóm tắt',
        Color(0xFF0EA5E9),
        'AI tóm tắt chat',
      ),
      _SheetItem(
        'tone_rewriter',
        Icons.edit_note_rounded,
        'Viết lại',
        Color(0xFF8B5CF6),
        'Đổi tông giọng',
      ),
    ],
    [
      _SheetItem(
        'insights',
        Icons.psychology_rounded,
        'Insights',
        Color(0xFFF59E0B),
        'Phân tích hành vi',
      ),
      _SheetItem(
        'weekly',
        Icons.analytics_rounded,
        'Recap',
        Color(0xFF10B981),
        'Báo cáo tuần',
      ),
      _SheetItem(
        'reminders',
        Icons.alarm_rounded,
        'Nhắc nhở',
        Color(0xFF6366F1),
        'Quản lý nhắc nhở',
      ),
      _SheetItem(
        'bubble',
        Icons.bubble_chart_rounded,
        'Bubble',
        Color(0xFF10B981),
        'Chat bubble',
      ),
    ],
    [
      _SheetItem(
        'media',
        Icons.perm_media_rounded,
        'Media',
        Color(0xFF43C6AC),
        'Ảnh & Tệp',
      ),
      _SheetItem(
        'group_call_history',
        Icons.history_rounded,
        'Lịch sử gọi',
        Color(0xFF3B82F6),
        'Cuộc gọi nhóm',
      ),
      _SheetItem(
        'info',
        Icons.info_outline_rounded,
        'Thông tin',
        null,
        'Thành viên nhóm',
      ),
      _SheetItem(
        'autodelete',
        Icons.timer_rounded,
        'Tự xoá',
        null,
        'Cài đặt tự xoá',
      ),
    ],
    [
      _SheetItem(
        'theme',
        Icons.palette_rounded,
        'Giao diện',
        null,
        'Đổi chủ đề màu',
      ),
      _SheetItem(
        'settings_bubble',
        Icons.settings_rounded,
        'Cài đặt',
        null,
        'Cài đặt bubble',
      ),
      _SheetItem(
        'clear',
        Icons.delete_sweep_rounded,
        'Xoá lịch sử',
        null,
        'Xoá tất cả',
        isDanger: true,
      ),
      _SheetItem(
        'leave',
        Icons.exit_to_app_rounded,
        'Rời nhóm',
        null,
        'Rời khỏi nhóm',
        isDanger: true,
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: palette.shadowStrong.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: palette.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Tính năng',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (activeReminderCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '⏰ $activeReminderCount',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (bubbleCtx.mode != BubbleMode.normal)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${bubbleCtx.mode.name} ${_modeEmoji(bubbleCtx.mode)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _sections
                    .map(
                      (section) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GridView.count(
                          crossAxisCount: 4,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.9,
                          children: section.map((item) {
                            final color = item.color ?? primary;
                            final isDanger = item.isDanger;
                            final showBadge =
                                item.value == 'reminders' &&
                                activeReminderCount > 0;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                                onSelected(item.value);
                              },
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color:
                                          (isDanger
                                                  ? const Color(0xFFEF4444)
                                                  : color)
                                              .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color:
                                            (isDanger
                                                    ? const Color(0xFFEF4444)
                                                    : color)
                                                .withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          item.icon,
                                          color: isDanger
                                              ? const Color(0xFFEF4444)
                                              : color,
                                          size: 22,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          item.label,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isDanger
                                                ? const Color(0xFFEF4444)
                                                : palette.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          item.description,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            color: palette.textHint,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (showBadge)
                                    Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          activeReminderCount > 9
                                              ? '9+'
                                              : '$activeReminderCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _modeEmoji(BubbleMode mode) => switch (mode) {
    BubbleMode.work => '💼',
    BubbleMode.media => '🎵',
    BubbleMode.location => '📍',
    BubbleMode.secure => '🔒',
    BubbleMode.shared => '🎨',
    _ => '💬',
  };
}

class _SheetItem {
  const _SheetItem(
    this.value,
    this.icon,
    this.label,
    this.color,
    this.description, {
    this.isDanger = false,
  });
  final String value;
  final IconData icon;
  final String label;
  final Color? color;
  final String description;
  final bool isDanger;
}

// ── Input icon button ────────────────────────────────────────────────────
class _InputIconBtn extends StatelessWidget {
  const _InputIconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.rotate = false,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool rotate;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(10.0),
      child: AnimatedRotation(
        turns: rotate ? 0.125 : 0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        child: Icon(icon, color: color, size: 24),
      ),
    ),
  );
}

// ── Feature menu tile ────────────────────────────────────────────────────
class _FeatureMenuTile extends StatelessWidget {
  const _FeatureMenuTile({required this.item, required this.p});
  final _GFeatureItem item;
  final ThemePalette p;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: item.onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      width: 68,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: item.color.withValues(alpha: .22),
                width: .8,
              ),
            ),
            child: Icon(item.icon, color: item.color, size: 23),
          ),
          const SizedBox(height: 5),
          Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: p.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Quick start chip ─────────────────────────────────────────────────────
class _QuickStartChip extends StatelessWidget {
  const _QuickStartChip(this.label, this.onTap, this.color, this.p);
  final String label;
  final VoidCallback onTap;
  final Color color;
  final ThemePalette p;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

// ── AI action data class ─────────────────────────────────────────────────
class _AIAction {
  const _AIAction(this.icon, this.label, this.onTap, this.color);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
}

// ── Scam banner ──────────────────────────────────────────────────────────
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
      border: Border.all(color: palette.dangerColor.withValues(alpha: .4)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, color: palette.dangerColor, size: 15),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'AI: $reason',
            style: TextStyle(
              color: palette.dangerColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Reminder banner inside bubble ────────────────────────────────────────
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
      border: Border.all(color: palette.infoColor.withValues(alpha: .3)),
    ),
    child: Row(
      children: [
        Icon(Icons.alarm_add_rounded, color: palette.infoColor, size: 15),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'AI: Phát hiện việc cần nhắc nhở',
            style: TextStyle(color: palette.infoColor, fontSize: 12),
          ),
        ),
        GestureDetector(
          onTap: () => onSet(msg, messageId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: palette.infoColor.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Đặt',
              style: TextStyle(
                color: palette.infoColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Location content widget ──────────────────────────────────────────────
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on_rounded,
            color: isMe ? Colors.white : palette.dangerColor,
            size: 18,
          ),
          const SizedBox(width: 5),
          Text(
            'Vị trí',
            style: TextStyle(
              color: isMe ? Colors.white : palette.textPrimary,
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
          color: isMe ? Colors.white70 : palette.textSecondary,
          fontSize: 12.5,
        ),
      ),
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
                  : theme.primaryColor.withValues(alpha: .3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_rounded,
                size: 13,
                color: isMe ? Colors.white : theme.primaryColor,
              ),
              const SizedBox(width: 5),
              Text(
                'Xem trên Maps',
                style: TextStyle(
                  fontSize: 12,
                  color: isMe ? Colors.white : theme.primaryColor,
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

// ── Themed dialog & actions ───────────────────────────────────────────────
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
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          content,
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions
                .map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: a,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    ),
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
    if (isPrimary)
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        child: Text(label),
      );
    if (isDanger)
      return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: palette.dangerColor),
        child: Text(label),
      );
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
      child: Text(label),
    );
  }
}

// ── Recording dot animation ───────────────────────────────────────────────
class _RecDot extends StatefulWidget {
  const _RecDot({required this.color});
  final Color color;
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
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}

// ── Date divider ──────────────────────────────────────────────────────────
class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date, required this.palette});
  final DateTime date;
  final ThemePalette palette;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final String label;
    if (_same(date, now))
      label = 'Hôm nay';
    else if (_same(date, now.subtract(const Duration(days: 1))))
      label = 'Hôm qua';
    else
      label = DateFormat('dd/MM/yyyy').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: palette.divider.withValues(alpha: 0.4),
              height: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: palette.surfaceVariant,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow,
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: palette.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: palette.divider.withValues(alpha: 0.4),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── AI Analysis Dialog ────────────────────────────────────────────────────
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
      future: AIBackendService().analyzeChatContext(
        messages,
        'work',
        'extract_tasks',
      ),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 80,
            child: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF8B5CF6),
                strokeWidth: 2,
              ),
            ),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return Text(
            'AI không khả dụng lúc này.',
            style: TextStyle(color: palette.textSecondary),
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: Text(
              snap.data!,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        );
      },
    ),
    actions: [
      _ThemedDialogAction(
        label: 'Đóng',
        palette: palette,
        primary: primary,
        onTap: () => Navigator.pop(context),
      ),
    ],
  );
}

// ── Feature item data class ───────────────────────────────────────────────
class _GFeatureItem {
  const _GFeatureItem(this.icon, this.label, this.onTap, this.color);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
}

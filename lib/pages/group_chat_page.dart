// lib/pages/group_chat_page.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/utils/utilities.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/resource_manager.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key, required this.group});
  final Group group;

  @override
  GroupChatPageState createState() => GroupChatPageState();
}

class GroupChatPageState extends State<GroupChatPage>
    with WidgetsBindingObserver, ResourceManagerMixin {
  // ── State ─────────────────────────────────────
  late String _currentUserId;
  List<QueryDocumentSnapshot> _listMessage = [];
  int _limit = 20;
  final int _limitIncrement = 20;
  bool _isLoading = false;
  bool _isShowSticker = false;
  bool _showFeaturesMenu = false;
  bool _isRecording = false;
  String _recordingDuration = "0:00";
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // Reply state
  MessageChat? _replyingTo;
  String? _replyingToSenderName;

  // Pin state
  List<DocumentSnapshot> _pinnedMessages = [];

  // Mention
  bool _showMentionSuggestions = false;
  List<Map<String, dynamic>> _memberSuggestions = [];
  Map<String, String> _memberNames = {}; // userId -> nickname
  String _mentionQuery = '';

  // File & upload
  File? _imageFile;
  String _imageUrl = '';

  // Smart replies
  List<SmartReply> _smartReplies = [];

  // Providers
  late ChatProvider _chatProvider;
  late AuthProvider _authProvider;
  late MessageProvider _messageProvider;
  late ReactionProvider _reactionProvider;
  late ReminderProvider _reminderProvider;
  late AutoDeleteProvider _autoDeleteProvider;
  late ViewOnceProvider _viewOnceProvider;
  late SmartReplyProvider _smartReplyProvider;
  UserPresenceProvider? _presenceProvider;
  TranslationProvider? _translationProvider;
  VoiceMessageProvider? _voiceProvider;
  LocationProvider? _locationProvider;

  // Controllers
  late TextEditingController _chatInputController;
  late ScrollController _listScrollController;
  late FocusNode _focusNode;

  // Deduplication
  final Set<String> _processedMessageIds = {};

  // Scheduled messages
  final Map<String, Timer> _scheduledMessages = {};
  final Map<String, String> _scheduledMessageContents = {};

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
    _locationProvider = LocationProvider();

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
    _markMessagesAsRead();
  }

  void _scrollListener() {
    if (resourceManager.isDisposed || !_listScrollController.hasClients) return;
    final pos = _listScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 &&
        !pos.outOfRange &&
        _limit <= _listMessage.length) {
      if (mounted) setState(() => _limit += _limitIncrement);
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

  // ── Member Names ───────────────────────────────
  Future<void> _loadMemberNames() async {
    final names = <String, String>{};
    for (final uid in widget.group.memberIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(FirestoreConstants.pathUserCollection)
            .doc(uid)
            .get();
        if (doc.exists) {
          names[uid] = doc.get(FirestoreConstants.nickname) ?? 'User';
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

  // ── Pinned Messages ────────────────────────────
  void _loadPinnedMessages() {
    if (resourceManager.isDisposed) return;
    final sub = _messageProvider.getPinnedMessages(widget.group.id).listen(
      (snapshot) {
        if (!mounted || resourceManager.isDisposed) return;
        setState(() => _pinnedMessages = snapshot.docs);
      },
      onError: (_) {},
    );
    resourceManager.addSubscription(sub);
  }

  // ── Mentions ───────────────────────────────────
  void _handleTextChange(String text) {
    if (resourceManager.isDisposed) return;
    _handleTyping(text);

    // Detect @mention
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
          _mentionQuery = query;
        });
      }
    } else {
      if (mounted) setState(() => _showMentionSuggestions = false);
    }

    // Smart replies
    if (text.isNotEmpty && _smartReplies.isNotEmpty && mounted) {
      setState(() => _smartReplies = []);
    }
  }

  void _insertMention(String userId, String name) {
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

  // ── Typing ─────────────────────────────────────
  void _handleTyping(String text) {
    if (_presenceProvider == null || resourceManager.isDisposed) return;
    _presenceProvider!.setTypingStatus(
      conversationId: widget.group.id,
      userId: _currentUserId,
      isTyping: text.isNotEmpty,
    );
  }

  // ── Mark as read ───────────────────────────────
  Future<void> _markMessagesAsRead() async {
    if (resourceManager.isDisposed) return;
    try {
      final unread = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(widget.group.id)
          .collection(widget.group.id)
          .where(FirestoreConstants.idTo, isEqualTo: widget.group.id)
          .where('isRead', isEqualTo: false)
          .get();

      if (unread.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in unread.docs) {
        batch.update(doc.reference,
            {'isRead': true, 'readAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
    } catch (_) {}
  }

  // ── Send Message ───────────────────────────────
  Future<void> _onSendMessage(String content, int type) async {
    if (resourceManager.isDisposed) return;
    if (content.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'Nothing to send');
      return;
    }

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
        _smartReplies = [];
        _showMentionSuggestions = false;
      });
    }

    try {
      await _sendGroupMessage(finalContent, type);
      await _autoDeleteProvider.scheduleMessageDeletion(
        groupChatId: widget.group.id,
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        conversationId: widget.group.id,
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'Send failed');
    }

    if (_listScrollController.hasClients && !resourceManager.isDisposed) {
      _listScrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _sendGroupMessage(String content, int type) async {
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final docRef = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(widget.group.id)
        .collection(widget.group.id)
        .doc(messageId);

    final messageData = {
      FirestoreConstants.idFrom: _currentUserId,
      FirestoreConstants.idTo: widget.group.id,
      FirestoreConstants.timestamp: messageId,
      FirestoreConstants.content: content,
      FirestoreConstants.type: type,
      'isDeleted': false,
      'isPinned': false,
      'isRead': false,
      'groupId': widget.group.id,
    };

    await FirebaseFirestore.instance.runTransaction((tx) async {
      tx.set(docRef, messageData);
    });

    await FirebaseFirestore.instance
        .collection(FirestoreConstants.pathConversationCollection)
        .doc(widget.group.id)
        .set({
      FirestoreConstants.isGroup: true,
      FirestoreConstants.participants: widget.group.memberIds,
      FirestoreConstants.lastMessage: content,
      FirestoreConstants.lastMessageTime: messageId,
      FirestoreConstants.lastMessageType: type,
    }, SetOptions(merge: true));

    await _loadSmartReplies();
  }

  Future<void> _loadSmartReplies() async {
    if (_listMessage.isEmpty || resourceManager.isDisposed) return;
    final last = _listMessage.first;
    final msg = MessageChat.fromDocument(last);
    if (msg.idFrom != _currentUserId && msg.type == TypeMessage.text) {
      final replies = _smartReplyProvider.getRuleBasedReplies(msg.content);
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _smartReplies = replies);
      }
    }
  }

  // ── Image ──────────────────────────────────────
  Future<bool> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        if (mounted && !resourceManager.isDisposed) {
          setState(() {
            _imageFile = File(picked.path);
            _isLoading = true;
          });
        }
        return true;
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to pick image');
    }
    return false;
  }

  Future<void> _uploadFile() async {
    if (_imageFile == null) return;
    try {
      final fileName = DateTime.now().millisecondsSinceEpoch.toString();
      final task = _chatProvider.uploadFile(_imageFile!, fileName);
      final snapshot = await task;
      _imageUrl = await snapshot.ref.getDownloadURL();
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _isLoading = false);
      }
      await _onSendMessage(_imageUrl, TypeMessage.image);
    } catch (e) {
      if (mounted && !resourceManager.isDisposed) {
        setState(() => _isLoading = false);
      }
      Fluttertoast.showToast(msg: 'Upload failed');
    }
  }

  // ── Voice ──────────────────────────────────────
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
    _recordingTimer?.cancel();
    await _voiceProvider?.cancelRecording();
    if (mounted && !resourceManager.isDisposed) {
      setState(() => _isRecording = false);
    }
  }

  // ── Location ───────────────────────────────────
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
        final message = _locationProvider!.formatLocationMessage(locationData);
        await _onSendMessage(message, TypeMessage.text);
        Fluttertoast.showToast(msg: '📍 Location shared');
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Message Actions ────────────────────────────
  void _showMessageOptions(MessageChat message, String messageId) {
    if (resourceManager.isDisposed) return;
    showModalBottomSheet(
      context: context,
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
        onCopy: () => _copyMessage(message.content),
        onReply: () => _setReply(message),
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
              widget.group.id, messageId, newContent);
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
      final ok =
          await _messageProvider.deleteMessage(widget.group.id, messageId);
      if (ok) Fluttertoast.showToast(msg: 'Message deleted');
    }
  }

  Future<void> _togglePin(String messageId, bool current) async {
    final ok = await _messageProvider.togglePinMessage(
        widget.group.id, messageId, current);
    if (ok) Fluttertoast.showToast(msg: current ? 'Unpinned' : 'Pinned');
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    Fluttertoast.showToast(msg: 'Copied');
  }

  void _setReply(MessageChat message) {
    if (resourceManager.isDisposed || !mounted) return;
    setState(() {
      _replyingTo = message;
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
        conversationId: widget.group.id,
        reminderTime: reminderTime,
        message: message.content,
      );
      if (ok) Fluttertoast.showToast(msg: '⏰ Reminder set');
    }
  }

  Future<DateTime?> _pickReminderTime() async {
    DateTime selected = DateTime.now().add(const Duration(hours: 1));
    return await showDialog<DateTime>(
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
                  if (d != null)
                    ss(() => selected = DateTime(d.year, d.month, d.day,
                        selected.hour, selected.minute));
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
                  if (t != null)
                    ss(() => selected = DateTime(selected.year, selected.month,
                        selected.day, t.hour, t.minute));
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
    if (_translationProvider == null) return;
    showDialog(
      context: context,
      builder: (_) => TranslationDialog(
        originalText: content,
        translationProvider: _translationProvider!,
      ),
    );
  }

  // ── Schedule ───────────────────────────────────
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

  // ── View Once ──────────────────────────────────
  void _sendViewOnce() {
    showDialog(
      context: context,
      builder: (_) => SendViewOnceDialog(
        onSend: (content, type) async {
          await _viewOnceProvider.sendViewOnceMessage(
            groupChatId: widget.group.id,
            currentUserId: _currentUserId,
            peerId: widget.group.id,
            content: content,
            type: type,
          );
        },
      ),
    );
  }

  // ── Auto Delete ────────────────────────────────
  void _showAutoDeleteSettings() {
    showDialog(
      context: context,
      builder: (_) => AutoDeleteSettingsDialog(
        conversationId: widget.group.id,
        provider: _autoDeleteProvider,
      ),
    );
  }

  // ── Reactions ──────────────────────────────────
  void _showReactionPicker(String messageId) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ReactionPicker(
          onEmojiSelected: (emoji) {
            _reactionProvider.toggleReaction(
                widget.group.id, messageId, _currentUserId, emoji);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  // ── Open location ──────────────────────────────
  Future<void> _openLocationInMaps(String mapsUrl) async {
    try {
      final uri = Uri.parse(mapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  // ── Build UI ───────────────────────────────────
  void _getSticker() {
    _focusNode.unfocus();
    setState(() {
      _isShowSticker = !_isShowSticker;
      _showFeaturesMenu = false;
    });
  }

  void _toggleFeaturesMenu() {
    if (resourceManager.isDisposed || !mounted) return;
    setState(() {
      _showFeaturesMenu = !_showFeaturesMenu;
      _isShowSticker = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _onBackPress();
          },
          child: Stack(
            children: [
              Column(
                children: [
                  if (_pinnedMessages.isNotEmpty) _buildPinnedMessages(),
                  _buildListMessage(),
                  _buildTypingIndicator(),
                  if (_showMentionSuggestions) _buildMentionSuggestions(),
                  if (_isShowSticker) _buildStickers(),
                  if (_showFeaturesMenu) _buildFeaturesMenu(),
                  _buildInput(),
                ],
              ),
              Positioned(
                  child: _isLoading ? LoadingView() : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupInfoPage(
              group: widget.group,
              currentUserId: _currentUserId,
              memberNames: _memberNames,
            ),
          ),
        ),
        child: Row(
          children: [
            Hero(
              tag: 'group_avatar_${widget.group.id}',
              child: CircleAvatar(
                radius: 18,
                backgroundImage: widget.group.groupPhotoUrl.isNotEmpty
                    ? NetworkImage(widget.group.groupPhotoUrl)
                    : null,
                child: widget.group.groupPhotoUrl.isEmpty
                    ? const Icon(Icons.group, size: 18)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.group.groupName,
                    style: TextStyle(
                        color: ColorConstants.primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${widget.group.memberIds.length} members',
                    style: TextStyle(
                        color: ColorConstants.greyColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.videocam, color: ColorConstants.primaryColor),
          onPressed: () =>
              Fluttertoast.showToast(msg: 'Group video call coming soon'),
          tooltip: 'Group Video Call',
        ),
        IconButton(
          icon: const Icon(Icons.search, color: ColorConstants.primaryColor),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SearchMessagesPage(
                groupChatId: widget.group.id,
                peerName: widget.group.groupName,
              ),
            ),
          ),
          tooltip: 'Search',
        ),
        PopupMenuButton<String>(
          onSelected: _onMenuSelected,
          icon: const Icon(Icons.more_vert, color: ColorConstants.primaryColor),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'info', child: Text('Group Info')),
            const PopupMenuItem(value: 'media', child: Text('Media & Files')),
            const PopupMenuItem(
                value: 'search', child: Text('Search Messages')),
            const PopupMenuItem(
                value: 'mute', child: Text('Mute Notifications')),
            const PopupMenuItem(value: 'autodelte', child: Text('Auto-Delete')),
            const PopupMenuItem(value: 'clear', child: Text('Clear History')),
            const PopupMenuItem(
                value: 'leave',
                child:
                    Text('Leave Group', style: TextStyle(color: Colors.red))),
          ],
        ),
      ],
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'info':
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
        break;
      case 'media':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupMediaPage(
              groupId: widget.group.id,
              groupName: widget.group.groupName,
            ),
          ),
        );
        break;
      case 'search':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SearchMessagesPage(
              groupChatId: widget.group.id,
              peerName: widget.group.groupName,
            ),
          ),
        );
        break;
      case 'autodelte':
        _showAutoDeleteSettings();
        break;
      case 'clear':
        _clearHistory();
        break;
      case 'leave':
        _leaveGroup();
        break;
      default:
        Fluttertoast.showToast(msg: 'Coming soon');
    }
  }

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
    if (confirm == true) {
      if (mounted) setState(() => _isLoading = true);
      try {
        final msgs = await FirebaseFirestore.instance
            .collection(FirestoreConstants.pathMessageCollection)
            .doc(widget.group.id)
            .collection(widget.group.id)
            .get();
        WriteBatch batch = FirebaseFirestore.instance.batch();
        int count = 0;
        for (final doc in msgs.docs) {
          batch.delete(doc.reference);
          count++;
          if (count >= 500) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            count = 0;
          }
        }
        if (count > 0) await batch.commit();
        Fluttertoast.showToast(msg: 'History cleared');
      } catch (_) {
        Fluttertoast.showToast(msg: 'Failed to clear history');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
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
    if (confirm == true) {
      try {
        final newMembers =
            widget.group.memberIds.where((id) => id != _currentUserId).toList();
        await FirebaseFirestore.instance
            .collection(FirestoreConstants.pathGroupCollection)
            .doc(widget.group.id)
            .update({FirestoreConstants.memberIds: newMembers});

        // Send system message
        await _sendGroupMessage(
            '${_memberNames[_currentUserId] ?? 'User'} left the group',
            TypeMessage.text);

        if (mounted) Navigator.of(context).pop();
        Fluttertoast.showToast(msg: 'You left the group');
      } catch (_) {
        Fluttertoast.showToast(msg: 'Failed to leave group');
      }
    }
  }

  void _onBackPress() {
    if (_presenceProvider != null) {
      _presenceProvider!.setTypingStatus(
          conversationId: widget.group.id,
          userId: _currentUserId,
          isTyping: false);
    }
    Navigator.pop(context);
  }

  // ── Pinned Messages ────────────────────────────
  Widget _buildPinnedMessages() {
    return Container(
      height: 60,
      color: ColorConstants.greyColor2.withOpacity(0.3),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _pinnedMessages.length,
        itemExtent: 180,
        itemBuilder: (context, index) {
          final message = MessageChat.fromDocument(_pinnedMessages[index]);
          return Container(
            width: 170,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.push_pin,
                    size: 14, color: ColorConstants.primaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    message.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── List Messages ──────────────────────────────
  Widget _buildListMessage() {
    return Flexible(
      child: StreamBuilder<QuerySnapshot>(
        stream: _chatProvider.getChatStream(widget.group.id, _limit),
        builder: (_, snapshot) {
          if (snapshot.hasData) {
            _listMessage = snapshot.data!.docs;
            if (_listMessage.isNotEmpty) {
              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _listMessage.length,
                reverse: true,
                controller: _listScrollController,
                itemBuilder: (_, index) =>
                    _buildItemMessage(index, _listMessage[index]),
              );
            }
            return const Center(child: Text('No messages yet. Say hello!'));
          }
          return const Center(
              child:
                  CircularProgressIndicator(color: ColorConstants.themeColor));
        },
      ),
    );
  }

  // ── Single Message ─────────────────────────────
  Widget _buildItemMessage(int index, DocumentSnapshot document) {
    final msg = MessageChat.fromDocument(document);
    final isMe = msg.idFrom == _currentUserId;
    final data = document.data() as Map<String, dynamic>?;
    final isViewOnce = data?['isViewOnce'] ?? false;
    final isViewed = data?['isViewed'] ?? false;

    if (isViewOnce) {
      return _buildViewOnceMessage(document, msg, isMe);
    }

    if (msg.type == 3 && _voiceProvider != null) {
      return _buildVoiceMessage(document, msg, isMe);
    }

    if (msg.type == TypeMessage.text) {
      return _buildTextMessage(document, msg, isMe, index);
    }

    if (msg.type == TypeMessage.image) {
      return _buildImageMessage(document, msg, isMe);
    }

    // Sticker
    return _buildStickerMessage(document, msg, isMe);
  }

  Widget _buildSenderInfo(String senderId) {
    if (senderId == _currentUserId) return const SizedBox.shrink();
    final name = _getSenderName(senderId);
    return Padding(
      padding: const EdgeInsets.only(left: 40, bottom: 2),
      child: Text(
        name,
        style: TextStyle(
            color: ColorConstants.primaryColor,
            fontSize: 12,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildAvatar(String senderId) {
    if (senderId == _currentUserId) return const SizedBox(width: 35);
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection(FirestoreConstants.pathUserCollection)
          .doc(senderId)
          .get(),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox(width: 35);
        String photoUrl = '';
        try {
          photoUrl = snap.data!.get(FirestoreConstants.photoUrl) ?? '';
        } catch (_) {}
        return ClipOval(
          child: photoUrl.isNotEmpty
              ? Image.network(photoUrl,
                  width: 35,
                  height: 35,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.account_circle,
                      size: 35, color: ColorConstants.greyColor))
              : const Icon(Icons.account_circle,
                  size: 35, color: ColorConstants.greyColor),
        );
      },
    );
  }

  Widget _buildTextMessage(
      DocumentSnapshot doc, MessageChat msg, bool isMe, int index) {
    final location = _locationProvider?.parseLocationFromMessage(msg.content);

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
            Flexible(
              child: GestureDetector(
                onLongPress: () => _showMessageOptions(msg, doc.id),
                onDoubleTap: () => _showReactionPicker(doc.id),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 250),
                  decoration: BoxDecoration(
                    color: msg.isDeleted
                        ? ColorConstants.greyColor2
                        : isMe
                            ? ColorConstants.primaryColor
                            : ColorConstants.greyColor2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: msg.isDeleted
                      ? Text('This message was deleted',
                          style: TextStyle(
                              color: ColorConstants.greyColor,
                              fontStyle: FontStyle.italic,
                              fontSize: 13))
                      : location != null
                          ? _buildLocationContent(location, isMe)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.content,
                                  style: TextStyle(
                                      color:
                                          isMe ? Colors.white : Colors.black87),
                                ),
                                if (msg.editedAt != null)
                                  Text('(edited)',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: isMe
                                              ? Colors.white70
                                              : ColorConstants.greyColor)),
                              ],
                            ),
                ),
              ),
            ),
            if (!isMe) ...[
              const SizedBox(width: 4),
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_reaction, size: 18),
                    onPressed: () => _showReactionPicker(doc.id),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ],
        ),
        // Reactions
        _buildReactions(doc.id, isMe),
        // Timestamp
        Padding(
          padding: EdgeInsets.only(
              left: isMe ? 0 : 45, right: isMe ? 8 : 0, bottom: 4),
          child: Text(
            _formatTimestamp(msg.timestamp),
            style:
                const TextStyle(fontSize: 11, color: ColorConstants.greyColor),
          ),
        ),
      ],
    );
  }

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
                    color: isMe ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(location.address,
            style: TextStyle(
                color: isMe ? Colors.white : Colors.black87, fontSize: 13)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _openLocationInMaps(location.mapsUrl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white24
                  : ColorConstants.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map,
                    size: 14,
                    color: isMe ? Colors.white : ColorConstants.primaryColor),
                const SizedBox(width: 4),
                Text('View on Google Maps',
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            isMe ? Colors.white : ColorConstants.primaryColor,
                        decoration: TextDecoration.underline)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageMessage(DocumentSnapshot doc, MessageChat msg, bool isMe) {
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
            GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => FullPhotoPage(url: msg.content))),
              onLongPress: () => _showMessageOptions(msg, doc.id),
              child: Container(
                clipBehavior: Clip.hardEdge,
                decoration:
                    BoxDecoration(borderRadius: BorderRadius.circular(12)),
                child: Image.network(msg.content,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(
                          width: 200,
                          height: 200,
                          color: ColorConstants.greyColor2,
                          child:
                              const Center(child: CircularProgressIndicator()));
                    },
                    errorBuilder: (_, __, ___) => Container(
                        width: 200,
                        height: 200,
                        color: ColorConstants.greyColor2,
                        child: const Icon(Icons.error))),
              ),
            ),
          ],
        ),
        _buildReactions(doc.id, isMe),
        Padding(
          padding: EdgeInsets.only(left: isMe ? 0 : 45, right: 8, bottom: 4),
          child: Text(_formatTimestamp(msg.timestamp),
              style: const TextStyle(
                  fontSize: 11, color: ColorConstants.greyColor)),
        ),
      ],
    );
  }

  Widget _buildVoiceMessage(DocumentSnapshot doc, MessageChat msg, bool isMe) {
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
        Padding(
          padding: EdgeInsets.only(left: isMe ? 0 : 45, right: 8, bottom: 4),
          child: Text(_formatTimestamp(msg.timestamp),
              style: const TextStyle(
                  fontSize: 11, color: ColorConstants.greyColor)),
        ),
      ],
    );
  }

  Widget _buildStickerMessage(
      DocumentSnapshot doc, MessageChat msg, bool isMe) {
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
              onLongPress: () => _showMessageOptions(msg, doc.id),
              child: Image.asset('images/${msg.content}.gif',
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      width: 100,
                      height: 100,
                      color: ColorConstants.greyColor2,
                      child: const Icon(Icons.error))),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildViewOnceMessage(
      DocumentSnapshot doc, MessageChat msg, bool isMe) {
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
              groupChatId: widget.group.id,
              messageId: doc.id,
              content: msg.content,
              type: msg.type,
              currentUserId: _currentUserId,
              isViewed:
                  (doc.data() as Map<String, dynamic>?)?['isViewed'] ?? false,
              provider: _viewOnceProvider,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReactions(String messageId, bool isMe) {
    return StreamBuilder<QuerySnapshot>(
      stream: _reactionProvider.getReactions(widget.group.id, messageId),
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
          padding: EdgeInsets.only(left: isMe ? 0 : 45, top: 2),
          child: MessageReactionsDisplay(
            reactions: reactions,
            currentUserId: _currentUserId,
            userReactions: userReactions,
            onReactionTap: (emoji) => _reactionProvider.toggleReaction(
                widget.group.id, messageId, _currentUserId, emoji),
          ),
        );
      },
    );
  }

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
      final now = DateTime.now();
      if (now.difference(dt).inDays == 0) return DateFormat('HH:mm').format(dt);
      return DateFormat('MMM dd HH:mm').format(dt);
    } catch (_) {
      return '';
    }
  }

  // ── Typing Indicator ───────────────────────────
  Widget _buildTypingIndicator() {
    if (_presenceProvider == null) return const SizedBox.shrink();
    return StreamBuilder<Map<String, bool>>(
      stream: _presenceProvider!.getTypingStatus(widget.group.id),
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

  // ── Mention Suggestions ────────────────────────
  Widget _buildMentionSuggestions() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: ColorConstants.greyColor2)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _memberSuggestions.length,
        itemBuilder: (_, i) {
          final m = _memberSuggestions[i];
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: ColorConstants.primaryColor.withOpacity(0.2),
              child: Text((m['name'] as String).substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                      color: ColorConstants.primaryColor,
                      fontWeight: FontWeight.bold)),
            ),
            title: Text('@${m['name']}',
                style: const TextStyle(
                    color: ColorConstants.primaryColor, fontSize: 14)),
            onTap: () => _insertMention(m['userId']!, m['name']!),
          );
        },
      ),
    );
  }

  // ── Stickers ───────────────────────────────────
  Widget _buildStickers() {
    return Container(
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: ColorConstants.greyColor2, width: 0.5)),
          color: Colors.white),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['mimi1', 'mimi2', 'mimi3']
                .map((s) => TextButton(
                    onPressed: () => _onSendMessage(s, TypeMessage.sticker),
                    child: Image.asset('images/$s.gif',
                        width: 50, height: 50, fit: BoxFit.cover)))
                .toList(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['mimi4', 'mimi5', 'mimi6']
                .map((s) => TextButton(
                    onPressed: () => _onSendMessage(s, TypeMessage.sticker),
                    child: Image.asset('images/$s.gif',
                        width: 50, height: 50, fit: BoxFit.cover)))
                .toList(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['mimi7', 'mimi8', 'mimi9']
                .map((s) => TextButton(
                    onPressed: () => _onSendMessage(s, TypeMessage.sticker),
                    child: Image.asset('images/$s.gif',
                        width: 50, height: 50, fit: BoxFit.cover)))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ── Features Menu ──────────────────────────────
  Widget _buildFeaturesMenu() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: ColorConstants.greyColor2))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
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
            _featureBtn(Icons.image, 'Gallery', () {
              setState(() => _showFeaturesMenu = false);
              _pickImage().then((ok) {
                if (ok) _uploadFile();
              });
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
            Icon(icon, color: ColorConstants.primaryColor, size: 26),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: ColorConstants.primaryColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── Input ──────────────────────────────────────
  Widget _buildInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Smart replies
        if (_smartReplies.isNotEmpty)
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
        // Reply indicator
        if (_replyingTo != null)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 56),
            color: ColorConstants.greyColor2.withOpacity(0.3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 36,
                  color: ColorConstants.primaryColor,
                  margin: const EdgeInsets.only(right: 8),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Replying to $_replyingToSenderName',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: ColorConstants.primaryColor)),
                      Text(_replyingTo!.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    if (mounted)
                      setState(() {
                        _replyingTo = null;
                        _replyingToSenderName = null;
                      });
                  },
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        // Recording indicator
        if (_isRecording)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.red.withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record,
                    color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Text('Recording... $_recordingDuration',
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: _cancelRecording,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36)),
                IconButton(
                    icon: const Icon(Icons.send,
                        color: ColorConstants.primaryColor, size: 20),
                    onPressed: _stopRecording,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36)),
              ],
            ),
          ),
        // Main input row
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 50, maxHeight: 120),
          decoration: BoxDecoration(
              border: Border(
                  top:
                      BorderSide(color: ColorConstants.greyColor2, width: 0.5)),
              color: Colors.white),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // More options
              Material(
                color: Colors.white,
                child: IconButton(
                  icon: Icon(_showFeaturesMenu ? Icons.close : Icons.more_horiz,
                      color: ColorConstants.primaryColor, size: 24),
                  onPressed: _toggleFeaturesMenu,
                  padding: const EdgeInsets.all(8),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
              // Image
              Material(
                color: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.image, size: 24),
                  onPressed: () => _pickImage().then((ok) {
                    if (ok) _uploadFile();
                  }),
                  color: ColorConstants.primaryColor,
                  padding: const EdgeInsets.all(8),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
              // Sticker
              Material(
                color: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.face, size: 24),
                  onPressed: _getSticker,
                  color: ColorConstants.primaryColor,
                  padding: const EdgeInsets.all(8),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
              // Text field
              Expanded(
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 40, maxHeight: 100),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextField(
                    onTapOutside: (_) => Utilities.closeKeyboard(),
                    onSubmitted: (_) => _onSendMessage(
                        _chatInputController.text, TypeMessage.text),
                    onChanged: _handleTextChange,
                    style: const TextStyle(
                        color: ColorConstants.primaryColor, fontSize: 15),
                    controller: _chatInputController,
                    decoration: InputDecoration.collapsed(
                      hintText: 'Type a message... (@ to mention)',
                      hintStyle:
                          const TextStyle(color: ColorConstants.greyColor),
                    ),
                    focusNode: _focusNode,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
              ),
              // Voice
              if (_voiceProvider != null && !_isRecording)
                Material(
                  color: Colors.white,
                  child: IconButton(
                    icon: const Icon(Icons.mic, size: 24),
                    onPressed: _startRecording,
                    color: ColorConstants.primaryColor,
                    padding: const EdgeInsets.all(8),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),
              // Send
              Material(
                color: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.send, size: 24),
                  onPressed: () => _onSendMessage(
                      _chatInputController.text, TypeMessage.text),
                  color: ColorConstants.primaryColor,
                  padding: const EdgeInsets.all(8),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _scheduledMessages.forEach((_, t) => t.cancel());
    _scheduledMessages.clear();
    _scheduledMessageContents.clear();
    try {
      if (_presenceProvider != null && _currentUserId.isNotEmpty) {
        _presenceProvider!.setTypingStatus(
            conversationId: widget.group.id,
            userId: _currentUserId,
            isTyping: false);
      }
    } catch (_) {}
    try {
      _voiceProvider?.dispose();
    } catch (_) {}
    _chatInputController.dispose();
    _listScrollController.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

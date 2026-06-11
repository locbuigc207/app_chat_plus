import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallChatPanel
// In-call text messaging with real-time Firestore sync
// ══════════════════════════════════════════════════════════════════════════════

class _ChatMessage {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String text;
  final DateTime sentAt;
  final bool isSystem;

  const _ChatMessage({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.text,
    required this.sentAt,
    this.isSystem = false,
  });

  factory _ChatMessage.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _ChatMessage(
      id: doc.id,
      userId: d['userId'] ?? '',
      userName: d['userName'] ?? '',
      userAvatar: d['userAvatar'] ?? '',
      text: d['text'] ?? '',
      sentAt: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(d['sentAt']?.toString() ?? '0') ?? 0),
      isSystem: d['isSystem'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'userAvatar': userAvatar,
        'text': text,
        'sentAt': sentAt.millisecondsSinceEpoch.toString(),
        'isSystem': isSystem,
      };
}

class GroupCallChatPanel extends StatefulWidget {
  final String callId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final VoidCallback? onClose;

  const GroupCallChatPanel({
    super.key,
    required this.callId,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    this.onClose,
  });

  @override
  State<GroupCallChatPanel> createState() => _GroupCallChatPanelState();
}

class _GroupCallChatPanelState extends State<GroupCallChatPanel>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  StreamSubscription? _msgSub;
  final List<_ChatMessage> _messages = [];
  bool _sending = false;
  int _unreadCount = 0;

  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  static const _bg = Color(0xFF0A0E1A);
  static const _surface = Color(0xFF111827);
  static const _surface2 = Color(0xFF1C2333);
  static const _accent = Color(0xFF3B82F6);
  static const _text = Color(0xFFF8FAFC);
  static const _sub = Color(0xFF94A3B8);
  static const _muted = Color(0xFF475569);

  CollectionReference<Map<String, dynamic>> get _chatRef =>
      _db.collection('group_calls').doc(widget.callId).collection('call_chat');

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);
    _slideCtrl.forward();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  void _subscribeToMessages() {
    _msgSub = _chatRef
        .orderBy('sentAt', descending: false)
        .limit(200)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final msgs = snap.docs.map(_ChatMessage.fromDoc).toList();
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
      });
      _scrollToBottom();
    });
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _textCtrl.clear();
    HapticFeedback.lightImpact();

    try {
      final msg = _ChatMessage(
        id: '',
        userId: widget.currentUserId,
        userName: widget.currentUserName,
        userAvatar: widget.currentUserAvatar,
        text: text,
        sentAt: DateTime.now(),
      );
      await _chatRef.add(msg.toJson());
    } catch (e) {
      debugPrint('❌ GroupCallChat send error: $e');
      // Restore text on failure
      _textCtrl.text = text;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              width: 300,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                border: Border(
                  left: BorderSide(
                      color: Colors.white.withOpacity(0.08), width: 1),
                ),
              ),
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildMessageList()),
                  _buildInputBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: MediaQuery.of(context).padding.top + 12,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.chat_rounded, color: _accent, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Chat trong cuộc gọi',
                  style: TextStyle(
                    color: _text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_messages.length} tin nhắn',
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          if (widget.onClose != null)
            GestureDetector(
              onTap: widget.onClose,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.close_rounded, color: _sub, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────
  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                color: _muted.withOpacity(0.4), size: 40),
            const SizedBox(height: 12),
            Text(
              'Chưa có tin nhắn nào\nHãy gửi tin nhắn đầu tiên!',
              style: TextStyle(
                  color: _muted.withOpacity(0.6), fontSize: 12, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg = _messages[i];
        final isSelf = msg.userId == widget.currentUserId;
        final showAvatar =
            !isSelf && (i == 0 || _messages[i - 1].userId != msg.userId);
        final showName = showAvatar;

        if (msg.isSystem) return _buildSystemMsg(msg);

        return _buildMessageBubble(
          msg: msg,
          isSelf: isSelf,
          showAvatar: showAvatar,
          showName: showName,
        );
      },
    );
  }

  Widget _buildSystemMsg(_ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required _ChatMessage msg,
    required bool isSelf,
    required bool showAvatar,
    required bool showName,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        top: showName ? 8 : 2,
        bottom: 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          // Avatar (others only)
          if (!isSelf)
            SizedBox(
              width: 30,
              child: showAvatar
                  ? CircleAvatar(
                      radius: 13,
                      backgroundImage: msg.userAvatar.isNotEmpty
                          ? NetworkImage(msg.userAvatar)
                          : null,
                      backgroundColor: _surface2,
                      child: msg.userAvatar.isEmpty
                          ? Text(
                              msg.userName.isNotEmpty
                                  ? msg.userName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            )
                          : null,
                    )
                  : null,
            ),

          const SizedBox(width: 4),

          // Bubble
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (showName && !isSelf)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 3),
                    child: Text(
                      msg.userName,
                      style: const TextStyle(
                          color: _sub,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 210),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelf ? _accent.withOpacity(0.85) : _surface2,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(isSelf ? 14 : 4),
                      bottomRight: Radius.circular(isSelf ? 4 : 14),
                    ),
                    border: isSelf
                        ? null
                        : Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: isSelf ? Colors.white : _text,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
                  child: Text(
                    _formatTime(msg.sentAt),
                    style: const TextStyle(color: _muted, fontSize: 9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _surface2,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: TextField(
                controller: _textCtrl,
                focusNode: _focusNode,
                style: const TextStyle(color: _text, fontSize: 14),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Nhắn tin…',
                  hintStyle: const TextStyle(color: _muted, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildSendButton(),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _textCtrl,
      builder: (_, value, __) {
        final hasText = value.text.trim().isNotEmpty;
        return GestureDetector(
          onTap: hasText ? _send : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: hasText ? _accent : Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
              boxShadow: hasText
                  ? [
                      BoxShadow(
                          color: _accent.withOpacity(0.35), blurRadius: 10)
                    ]
                  : null,
            ),
            child: _sending
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Icon(
                    Icons.send_rounded,
                    color: hasText ? Colors.white : _muted,
                    size: 18,
                  ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CallChatBadge
// Floating badge showing unread chat count
// ══════════════════════════════════════════════════════════════════════════════
class CallChatBadge extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;
  final bool isActive;

  const CallChatBadge({
    super.key,
    required this.unreadCount,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF3B82F6).withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF3B82F6).withOpacity(0.5)
                : Colors.white.withOpacity(0.15),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_rounded, color: Colors.white, size: 14),
            if (unreadCount > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS (Dark premium — consistent with app)
// ─────────────────────────────────────────────────────────────────────────────

const _kBg = Color(0xFF0D0D14);
const _kSurface = Color(0xFF16161F);
const _kSurface2 = Color(0xFF1E1E2A);
const _kBorder = Color(0xFF2A2A3A);
const _kAccent = Color(0xFF7C6EFF);
const _kAccent2 = Color(0xFFFF6E9C);
const _kTextPri = Color(0xFFF0F0FF);
const _kTextSec = Color(0xFF8888AA);
const _kTextDim = Color(0xFF55556A);
const _kHighlight = Color(0xFFFFE066);

// ─────────────────────────────────────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────────────────────────────────────

class SearchResult {
  final String messageId;
  final String idFrom;
  final String content;
  final String timestamp;
  final bool isMyMessage;
  final String source; // 'local' | 'cloud'

  const SearchResult({
    required this.messageId,
    required this.idFrom,
    required this.content,
    required this.timestamp,
    required this.isMyMessage,
    this.source = 'local',
  });

  factory SearchResult.fromLocalDb(
    Map<dynamic, dynamic> data,
    String currentUserId,
  ) =>
      SearchResult(
        messageId: data['messageId']?.toString() ?? '',
        idFrom: data['idFrom']?.toString() ?? '',
        content: data['content']?.toString() ?? '',
        timestamp: data['timestamp']?.toString() ?? '0',
        isMyMessage: data['idFrom'] == currentUserId,
        source: 'local',
      );

  factory SearchResult.fromFirestore(
    DocumentSnapshot doc,
    MessageChat message,
    String decryptedContent,
    String currentUserId,
  ) =>
      SearchResult(
        messageId: doc.id,
        idFrom: message.idFrom,
        content: decryptedContent,
        timestamp: message.timestamp,
        isMyMessage: message.idFrom == currentUserId,
        source: 'cloud',
      );

  DateTime? get dateTime {
    try {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class SearchMessagesPage extends StatefulWidget {
  const SearchMessagesPage({
    super.key,
    required this.groupChatId,
    required this.peerName,
    required this.peerId,
  });

  final String groupChatId;
  final String peerName;
  final String peerId;

  @override
  State<SearchMessagesPage> createState() => _SearchMessagesPageState();
}

class _SearchMessagesPageState extends State<SearchMessagesPage>
    with SingleTickerProviderStateMixin {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  // ── State ──────────────────────────────────────────────────────────────────
  List<SearchResult> _results = [];
  bool _isSearching = false;
  bool _usingLocal = false;
  String _query = '';
  String? _errorMsg;

  // Debounce
  Timer? _debounce;

  // Firestore search cancellation flag
  String? _lastFirestoreQuery;

  late final String _currentUserId;

  // ── Animation ──────────────────────────────────────────────────────────────
  late final AnimationController _listAc;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
    _listAc = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _listAc.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEARCH LOGIC
  // ─────────────────────────────────────────────────────────────────────────

  void _onQueryChanged(String raw) {
    setState(() {}); // Refresh clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(raw);
    });
  }

  Future<void> _performSearch(String raw) async {
    final trimmed = raw.trim();

    if (trimmed.length < 2) {
      setState(() {
        _results = [];
        _query = '';
        _isSearching = false;
        _usingLocal = false;
        _errorMsg = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _query = trimmed.toLowerCase();
      _errorMsg = null;
    });

    // 1. Local DB — synchronous, instant
    final local = _searchLocalDb(_query);
    if (local.isNotEmpty) {
      if (mounted) {
        setState(() {
          _results = local;
          _isSearching = false;
          _usingLocal = true;
        });
        _animateList();
      }
      return;
    }

    // 2. Firestore fallback — async + decrypt
    await _searchFirestore(_query);
  }

  List<SearchResult> _searchLocalDb(String query) {
    try {
      final all = LocalDbService().getMessages(widget.groupChatId);
      return all
          .where((m) =>
              m['type'] == TypeMessage.text &&
              m['isDeleted'] != true &&
              (m['content']?.toString().toLowerCase().contains(query) ?? false))
          .map((m) => SearchResult.fromLocalDb(m, _currentUserId))
          .toList();
    } catch (e) {
      debugPrint('[SearchPage] Local DB error: $e');
      return [];
    }
  }

  Future<void> _searchFirestore(String query) async {
    _lastFirestoreQuery = query;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(widget.groupChatId)
          .collection(widget.groupChatId)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(500)
          .get();

      if (!mounted || _lastFirestoreQuery != query) return;

      final List<SearchResult> temp = [];

      for (final doc in snapshot.docs) {
        if (!mounted || _lastFirestoreQuery != query) return;

        final msg = MessageChat.fromDocument(doc);
        if (msg.type != TypeMessage.text || msg.isDeleted) continue;

        final decrypted = await EncryptionService().decryptPayload(
          msg.content,
          widget.groupChatId,
          [_currentUserId, widget.peerId],
          _currentUserId,
        );

        if (decrypted.toLowerCase().contains(query)) {
          temp.add(
              SearchResult.fromFirestore(doc, msg, decrypted, _currentUserId));
        }
      }

      if (!mounted || _lastFirestoreQuery != query) return;

      setState(() {
        _results = temp;
        _isSearching = false;
        _usingLocal = false;
      });
      _animateList();
    } catch (e) {
      debugPrint('[SearchPage] Firestore error: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
          _errorMsg = e.toString();
        });
      }
    }
  }

  void _animateList() {
    _listAc.forward(from: 0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildStatusBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _kSurface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: _kTextPri, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tìm kiếm tin nhắn',
              style: TextStyle(
                  color: _kTextPri, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(
            widget.peerName,
            style: const TextStyle(color: _kTextSec, fontSize: 11),
          ),
        ],
      ),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: _kSurface,
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        style: const TextStyle(color: _kTextPri, fontSize: 15),
        cursorColor: _kAccent,
        decoration: InputDecoration(
          hintText: 'Nhập ít nhất 2 ký tự…',
          hintStyle: const TextStyle(color: _kTextDim, fontSize: 14),
          prefixIcon:
              const Icon(Icons.search_rounded, color: _kTextSec, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded,
                      color: _kTextSec, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _performSearch('');
                  },
                )
              : null,
          filled: true,
          fillColor: _kSurface2,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kAccent, width: 1.5),
          ),
        ),
        onChanged: _onQueryChanged,
        onSubmitted: _performSearch,
      ),
    );
  }

  Widget _buildStatusBar() {
    if (_query.isEmpty || _isSearching) return const SizedBox.shrink();

    final count = _results.length;
    final source = _usingLocal ? '· local' : '· cloud';
    final label =
        count == 0 ? 'Không tìm thấy kết quả' : '$count kết quả $source';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: _kBg,
      child: Row(
        children: [
          Icon(
            count > 0 ? Icons.check_circle_rounded : Icons.search_off_rounded,
            size: 13,
            color: count > 0 ? _kAccent : _kTextDim,
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: count > 0 ? _kTextSec : _kTextDim, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearching) return _buildLoading();
    if (_errorMsg != null) return _buildError(_errorMsg!);
    if (_query.isEmpty) return _buildHint();
    if (_results.isEmpty) return _buildEmpty();
    return _buildResultList();
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: _kAccent,
              strokeWidth: 2.5,
              backgroundColor: _kAccent.withOpacity(0.15),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Đang tìm kiếm…',
              style: TextStyle(color: _kTextSec, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kAccent.withOpacity(0.08),
            ),
            child: const Icon(Icons.search_rounded, color: _kAccent, size: 36),
          ),
          const SizedBox(height: 18),
          const Text('Tìm kiếm trong cuộc trò chuyện',
              style: TextStyle(
                  color: _kTextPri, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Nhập ít nhất 2 ký tự để bắt đầu',
              style: TextStyle(color: _kTextSec, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, color: _kTextDim, size: 56),
          const SizedBox(height: 14),
          Text('Không tìm thấy "$_query"',
              style: const TextStyle(color: _kTextSec, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('Thử từ khóa khác',
              style: TextStyle(color: _kTextDim, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _kAccent2, size: 48),
            const SizedBox(height: 12),
            const Text('Lỗi tìm kiếm',
                style: TextStyle(
                    color: _kTextPri,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kTextSec, fontSize: 12)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => _performSearch(_query),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kAccent.withOpacity(0.4)),
                ),
                child: const Text('Thử lại',
                    style: TextStyle(
                        color: _kAccent, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultList() {
    return FadeTransition(
      opacity: _listAc,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) => _SearchResultCard(
          result: _results[i],
          query: _query,
          peerName: widget.peerName,
          onTap: () => Navigator.pop(context, _results[i].messageId),
          onLongPress: () => _copyResult(_results[i]),
        ),
      ),
    );
  }

  void _copyResult(SearchResult result) {
    Clipboard.setData(ClipboardData(text: result.content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Đã sao chép nội dung'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _kSurface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESULT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final String query;
  final String peerName;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SearchResultCard({
    required this.result,
    required this.query,
    required this.peerName,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = result.dateTime != null
        ? DateFormat('dd/MM HH:mm').format(result.dateTime!)
        : '';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: (result.isMyMessage ? _kAccent : _kAccent2)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    result.isMyMessage
                        ? Icons.send_rounded
                        : Icons.reply_rounded,
                    size: 12,
                    color: result.isMyMessage ? _kAccent : _kAccent2,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  result.isMyMessage ? 'Bạn' : peerName,
                  style: TextStyle(
                    color: result.isMyMessage ? _kAccent : _kAccent2,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (dateStr.isNotEmpty)
                  Text(dateStr,
                      style: const TextStyle(color: _kTextDim, fontSize: 11)),
                const SizedBox(width: 6),
                // Source badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kSurface2,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Text(
                    result.source,
                    style: const TextStyle(
                        color: _kTextDim,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Highlighted content
            _HighlightedText(
              text: result.content,
              query: query,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HIGHLIGHTED TEXT
// ─────────────────────────────────────────────────────────────────────────────

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightedText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _kTextSec, fontSize: 13, height: 1.5));
    }

    final lower = text.toLowerCase();
    final idx = lower.indexOf(query);

    if (idx == -1) {
      return Text(text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _kTextSec, fontSize: 13, height: 1.5));
    }

    // Show context around match (max 120 chars)
    String display = text;
    int matchIdx = idx;
    if (text.length > 120) {
      final start = (idx - 40).clamp(0, text.length);
      final prefix = start > 0 ? '…' : '';
      display =
          prefix + text.substring(start, (idx + 80).clamp(0, text.length));
      matchIdx = prefix.length + (idx - start);
    }

    final before = display.substring(0, matchIdx);
    final match = display.substring(
        matchIdx, (matchIdx + query.length).clamp(0, display.length));
    final after =
        display.substring((matchIdx + query.length).clamp(0, display.length));

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(color: _kTextSec, fontSize: 13, height: 1.5),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: TextStyle(
              color: _kBg,
              backgroundColor: _kHighlight,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}

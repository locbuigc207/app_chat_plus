import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/services/services.dart';

class SearchResult {
  final String messageId;
  final String idFrom;
  final String content;
  final String timestamp;
  final bool isMyMessage;
  final String source;

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

class _SearchMessagesPageState extends State<SearchMessagesPage> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  List<SearchResult> _results = [];
  bool _isSearching = false;
  bool _usingLocal = false;
  String _query = '';
  String? _errorMsg;

  Timer? _debounce;
  String? _lastFirestoreQuery;

  late final String _currentUserId;
  late final AnimationController _listAc;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
    _listAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
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

  void _onQueryChanged(String raw) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _performSearch(raw));
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
          temp.add(SearchResult.fromFirestore(doc, msg, decrypted, _currentUserId));
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
      if (mounted) {
        setState(() {
          _isSearching = false;
          _errorMsg = e.toString();
        });
      }
    }
  }

  void _animateList() => _listAc.forward(from: 0);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: _buildAppBar(p, theme),
        body: Column(
          children: [
            _buildSearchBar(p, theme),
            _buildStatusBar(p, theme),
            Expanded(child: _buildBody(p, theme)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemePalette p, ThemeProvider theme) {
    return AppBar(
      backgroundColor: p.appBarBackground,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: theme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Tìm kiếm tin nhắn',
              style: TextStyle(color: p.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)
          ),
          Text(
              widget.peerName,
              style: TextStyle(color: p.textSecondary, fontSize: 11.5)
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemePalette p, ThemeProvider theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: p.appBarBackground,
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        style: TextStyle(color: p.textPrimary, fontSize: 15),
        cursorColor: theme.primaryColor,
        decoration: InputDecoration(
          hintText: 'Nhập ít nhất 2 ký tự…',
          hintStyle: TextStyle(color: p.textSecondary, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: p.textSecondary, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.clear_rounded, color: p.textSecondary, size: 18),
            onPressed: () {
              _searchController.clear();
              _performSearch('');
            },
          )
              : null,
          filled: true,
          fillColor: p.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
          ),
        ),
        onChanged: _onQueryChanged,
        onSubmitted: _performSearch,
      ),
    );
  }

  Widget _buildStatusBar(ThemePalette p, ThemeProvider theme) {
    if (_query.isEmpty || _isSearching) return const SizedBox.shrink();

    final count = _results.length;
    final source = _usingLocal ? '· local cache' : '· cloud';
    final label = count == 0 ? 'Không tìm thấy kết quả' : '$count kết quả $source';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: p.background,
        border: Border(bottom: BorderSide(color: p.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            count > 0 ? Icons.check_circle_outline_rounded : Icons.search_off_rounded,
            size: 13,
            color: count > 0 ? theme.primaryColor : p.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
              label,
              style: TextStyle(color: p.textSecondary, fontSize: 12)
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemePalette p, ThemeProvider theme) {
    if (_isSearching) return _buildLoading(p, theme);
    if (_errorMsg != null) return _buildError(p, theme, _errorMsg!);
    if (_query.isEmpty) return _buildHint(p, theme);
    if (_results.isEmpty) return _buildEmpty(p);
    return _buildResultList(p, theme);
  }

  Widget _buildLoading(ThemePalette p, ThemeProvider theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(color: theme.primaryColor, strokeWidth: 2.5)
          ),
          const SizedBox(height: 14),
          Text(
              'Đang tìm kiếm…',
              style: TextStyle(color: p.textSecondary, fontSize: 13)
          ),
        ],
      ),
    );
  }

  Widget _buildHint(ThemePalette p, ThemeProvider theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.primaryColor.withValues(alpha: 0.08),
            ),
            child: Icon(Icons.search_rounded, color: theme.primaryColor, size: 36),
          ),
          const SizedBox(height: 18),
          Text(
              'Tìm trong cuộc trò chuyện',
              style: TextStyle(color: p.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)
          ),
          const SizedBox(height: 8),
          Text(
              'Nhập ít nhất 2 ký tự để bắt đầu',
              style: TextStyle(color: p.textSecondary, fontSize: 13)
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemePalette p) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, color: p.textSecondary, size: 56),
          const SizedBox(height: 14),
          Text(
              'Không tìm thấy "$_query"',
              style: TextStyle(color: p.textSecondary, fontSize: 15)
          ),
          const SizedBox(height: 6),
          Text(
              'Thử từ khóa khác',
              style: TextStyle(color: p.textSecondary, fontSize: 12)
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemePalette p, ThemeProvider theme, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: p.dangerColor, size: 48),
            const SizedBox(height: 12),
            Text(
                'Lỗi tìm kiếm',
                style: TextStyle(color: p.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)
            ),
            const SizedBox(height: 8),
            Text(
                msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, fontSize: 12)
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _performSearch(_query),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Thử lại'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.primaryColor,
                side: BorderSide(color: theme.primaryColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultList(ThemePalette p, ThemeProvider theme) {
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
          palette: p,
          primary: theme.primaryColor,
          onTap: () => Navigator.pop(context, _results[i].messageId),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: _results[i].content));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Đã sao chép nội dung'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: p.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Result Card ──────────────────────────────────────────────────────────────

class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final String query;
  final String peerName;
  final ThemePalette palette;
  final Color primary;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SearchResultCard({
    required this.result,
    required this.query,
    required this.peerName,
    required this.palette,
    required this.primary,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = result.dateTime != null
        ? DateFormat('dd/MM HH:mm').format(result.dateTime!)
        : '';
    final msgColor = result.isMyMessage ? primary : Colors.purple.shade400;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.divider, width: 0.6),
          boxShadow: [
            BoxShadow(color: palette.shadow, blurRadius: 6)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      color: msgColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)
                  ),
                  child: Icon(
                      result.isMyMessage ? Icons.send_rounded : Icons.reply_rounded,
                      size: 12,
                      color: msgColor
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                    result.isMyMessage ? 'Bạn' : peerName,
                    style: TextStyle(color: msgColor, fontSize: 12, fontWeight: FontWeight.w700)
                ),
                const Spacer(),
                if (dateStr.isNotEmpty)
                  Text(
                      dateStr,
                      style: TextStyle(color: palette.textSecondary, fontSize: 11)
                  ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: palette.surfaceVariant,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: palette.divider)
                  ),
                  child: Text(
                      result.source,
                      style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3
                      )
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _HighlightedText(
                text: result.content,
                query: query,
                palette: palette,
                highlight: Colors.amber.shade300
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final ThemePalette palette;
  final Color highlight;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.palette,
    required this.highlight
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(color: palette.textSecondary, fontSize: 13, height: 1.5);

    if (query.isEmpty) {
      return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: baseStyle);
    }

    final lower = text.toLowerCase();
    final idx = lower.indexOf(query);

    if (idx == -1) {
      return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: baseStyle);
    }

    String display = text;
    int matchIdx = idx;

    if (text.length > 120) {
      final start = (idx - 40).clamp(0, text.length);
      final prefix = start > 0 ? '…' : '';
      display = prefix + text.substring(start, (idx + 80).clamp(0, text.length));
      matchIdx = prefix.length + (idx - start);
    }

    final before = display.substring(0, matchIdx);
    final match = display.substring(matchIdx, (matchIdx + query.length).clamp(0, display.length));
    final after = display.substring((matchIdx + query.length).clamp(0, display.length));

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: before),
          TextSpan(
              text: match,
              style: TextStyle(
                  color: Colors.black87,
                  backgroundColor: highlight,
                  fontWeight: FontWeight.w700
              )
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}
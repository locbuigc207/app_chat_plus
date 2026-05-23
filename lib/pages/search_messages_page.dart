import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// Model thống nhất cho kết quả tìm kiếm từ cả 2 nguồn
// ---------------------------------------------------------------------------

class SearchResult {
  final String messageId;
  final String idFrom;
  final String content; // Plaintext đã giải mã
  final String timestamp;
  final bool isMyMessage;

  const SearchResult({
    required this.messageId,
    required this.idFrom,
    required this.content,
    required this.timestamp,
    required this.isMyMessage,
  });

  /// Tạo từ Hive local DB map
  factory SearchResult.fromLocalDb(
    Map<dynamic, dynamic> data,
    String currentUserId,
  ) {
    return SearchResult(
      messageId: data['messageId']?.toString() ?? '',
      idFrom: data['idFrom']?.toString() ?? '',
      content: data['content']?.toString() ?? '',
      timestamp: data['timestamp']?.toString() ?? '0',
      isMyMessage: data['idFrom'] == currentUserId,
    );
  }

  /// Tạo từ Firestore document đã giải mã
  factory SearchResult.fromFirestore(
    DocumentSnapshot doc,
    MessageChat message,
    String decryptedContent,
    String currentUserId,
  ) {
    return SearchResult(
      messageId: doc.id,
      idFrom: message.idFrom,
      content: decryptedContent,
      timestamp: message.timestamp,
      isMyMessage: message.idFrom == currentUserId,
    );
  }

  DateTime? get dateTime {
    try {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class SearchMessagesPage extends StatefulWidget {
  final String groupChatId;
  final String peerName;
  final String peerId;

  const SearchMessagesPage({
    super.key,
    required this.groupChatId,
    required this.peerName,
    required this.peerId,
  });

  @override
  State<SearchMessagesPage> createState() => _SearchMessagesPageState();
}

class _SearchMessagesPageState extends State<SearchMessagesPage> {
  final _searchController = TextEditingController();

  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  String _searchQuery = '';

  /// Nguồn dữ liệu đang được dùng — hiển thị để debug / UX
  bool _usingLocalDb = false;

  late final String _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
  }

  // -------------------------------------------------------------------------
  // Search logic
  // -------------------------------------------------------------------------

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchQuery = '';
        _isSearching = false;
        _usingLocalDb = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = trimmed.toLowerCase();
    });

    // 1️⃣ Thử local DB trước — đồng bộ, cực nhanh (~0.05 s / 10k tin nhắn)
    final localResults = _searchLocalDb(_searchQuery);

    if (localResults.isNotEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = localResults;
          _isSearching = false;
          _usingLocalDb = true;
        });
      }
      return;
    }

    // 2️⃣ Fallback: Firestore + giải mã async (khi local DB trống / chưa sync)
    await _searchFirestore(_searchQuery);
  }

  /// Tìm kiếm đồng bộ từ Hive — trả về list ngay lập tức.
  List<SearchResult> _searchLocalDb(String query) {
    try {
      final allMessages = LocalDbService().getMessages(widget.groupChatId);

      return allMessages
          .where(
            (msg) =>
                msg['type'] == 0 &&
                msg['isDeleted'] != true &&
                msg['content'].toString().toLowerCase().contains(query),
          )
          .map((msg) => SearchResult.fromLocalDb(msg, _currentUserId))
          .toList();
    } catch (e) {
      debugPrint('[SearchPage] Local DB error: $e');
      return [];
    }
  }

  /// Tìm kiếm bất đồng bộ từ Firestore, giải mã từng tin nhắn.
  Future<void> _searchFirestore(String query) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(widget.groupChatId)
          .collection(widget.groupChatId)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(1000)
          .get();

      final List<SearchResult> tempResults = [];

      for (final doc in snapshot.docs) {
        // Huỷ sớm nếu từ khoá đã thay đổi trong lúc giải mã
        if (!mounted || _searchController.text.toLowerCase() != query) return;

        final message = MessageChat.fromDocument(doc);

        if (message.type != TypeMessage.text || message.isDeleted) continue;

        final decryptedText = await EncryptionService().decryptPayload(
          message.content,
          widget.groupChatId,
          [_currentUserId, widget.peerId],
          _currentUserId,
        );

        if (decryptedText.toLowerCase().contains(query)) {
          tempResults.add(
            SearchResult.fromFirestore(
              doc,
              message,
              decryptedText,
              _currentUserId,
            ),
          );
        }
      }

      if (mounted && _searchController.text.toLowerCase() == query) {
        setState(() {
          _searchResults = tempResults;
          _isSearching = false;
          _usingLocalDb = false;
        });
      }
    } catch (e) {
      debugPrint('[SearchPage] Firestore search error: $e');
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search Messages',
              style: TextStyle(
                color: ColorConstants.primaryColor,
                fontSize: 18,
              ),
            ),
            Text(
              widget.peerName,
              style: const TextStyle(
                color: ColorConstants.greyColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildResultCountBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search in conversation...',
          prefixIcon: const Icon(
            Icons.search,
            color: ColorConstants.greyColor,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    color: ColorConstants.greyColor,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _performSearch('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: ColorConstants.greyColor2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() {}); // Cập nhật nút clear
          if (value.length >= 2) {
            _performSearch(value);
          } else if (value.isEmpty) {
            _performSearch('');
          }
        },
      ),
    );
  }

  Widget _buildResultCountBar() {
    if (_searchQuery.isEmpty || _isSearching) return const SizedBox.shrink();

    final source = _usingLocalDb ? ' (local)' : ' (cloud)';
    final count = _searchResults.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: ColorConstants.greyColor2.withOpacity(0.3),
      width: double.infinity,
      child: Text(
        '$count result${count != 1 ? 's' : ''} found$source',
        style: const TextStyle(
          color: ColorConstants.greyColor,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: ColorConstants.themeColor),
      );
    }

    if (_searchQuery.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search,
        label: 'Search for messages',
      );
    }

    if (_searchResults.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off,
        label: 'No messages found',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) =>
          _buildSearchResultItem(_searchResults[index]),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String label}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 80, color: ColorConstants.greyColor.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            label,
            style:
                const TextStyle(color: ColorConstants.greyColor, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultItem(SearchResult result) {
    final content = result.content;
    final queryIndex = content.toLowerCase().indexOf(_searchQuery);

    Widget contentWidget;

    if (queryIndex != -1) {
      final before = content.substring(0, queryIndex);
      final match =
          content.substring(queryIndex, queryIndex + _searchQuery.length);
      final after = content.substring(queryIndex + _searchQuery.length);

      contentWidget = RichText(
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(
            color: ColorConstants.primaryColor,
            fontSize: 14,
          ),
          children: [
            TextSpan(text: before),
            TextSpan(
              text: match,
              style: const TextStyle(
                backgroundColor: Colors.yellow,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(text: after),
          ],
        ),
      );
    } else {
      contentWidget = Text(
        content,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: ColorConstants.primaryColor,
          fontSize: 14,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pop(context, result.messageId),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ColorConstants.greyColor2.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ColorConstants.greyColor2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      result.isMyMessage ? Icons.send : Icons.reply,
                      size: 16,
                      color: ColorConstants.greyColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      result.isMyMessage ? 'You' : widget.peerName,
                      style: TextStyle(
                        color: result.isMyMessage
                            ? ColorConstants.primaryColor
                            : ColorConstants.greyColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    if (result.dateTime != null)
                      Text(
                        DateFormat('MMM dd, HH:mm').format(result.dateTime!),
                        style: const TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                contentWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/services/encryption_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Wrapper để chứa dữ liệu sau khi đã giải mã
class DecryptedSearchResult {
  final DocumentSnapshot doc;
  final MessageChat message;
  final String decryptedContent;

  DecryptedSearchResult({
    required this.doc,
    required this.message,
    required this.decryptedContent,
  });
}

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
  List<DecryptedSearchResult> _searchResults = [];
  bool _isSearching = false;
  String _searchQuery = '';

  late final String _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchQuery = '';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query.toLowerCase();
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(widget.groupChatId)
          .collection(widget.groupChatId)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(1000)
          .get();

      List<DecryptedSearchResult> tempResults = [];

      // Giải mã và lọc tuần tự trên thiết bị
      for (var doc in snapshot.docs) {
        final message = MessageChat.fromDocument(doc);

        if (message.type == TypeMessage.text && !message.isDeleted) {
          // Giải mã nội dung tin nhắn
          final decryptedText = await EncryptionService().decryptPayload(
            message.content,
            widget.groupChatId,
            [_currentUserId, widget.peerId],
            _currentUserId,
          );

          // Tìm kiếm trên plaintext sau khi giải mã
          if (decryptedText.toLowerCase().contains(_searchQuery)) {
            tempResults.add(
              DecryptedSearchResult(
                doc: doc,
                message: message,
                decryptedContent: decryptedText,
              ),
            );
          }
        }
      }

      // Chỉ cập nhật UI nếu từ khóa chưa thay đổi trong lúc giải mã
      if (mounted && _searchController.text.toLowerCase() == _searchQuery) {
        setState(() {
          _searchResults = tempResults;
          _isSearching = false;
        });
      }
    } catch (e) {
      print('Error searching encrypted messages: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

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
          // Thanh tìm kiếm
          Container(
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
                setState(() {});
                // Chỉ tìm kiếm khi >= 2 ký tự để tránh lag
                if (value.length >= 2) {
                  _performSearch(value);
                } else if (value.isEmpty) {
                  _performSearch('');
                }
              },
            ),
          ),

          // Hiển thị số kết quả
          if (_searchQuery.isNotEmpty && !_isSearching)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: ColorConstants.greyColor2.withOpacity(0.3),
              width: double.infinity,
              child: Text(
                '${_searchResults.length} result${_searchResults.length != 1 ? 's' : ''} found',
                style: const TextStyle(
                  color: ColorConstants.greyColor,
                  fontSize: 14,
                ),
              ),
            ),

          // Nội dung chính
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(
                      color: ColorConstants.themeColor,
                    ),
                  )
                : _searchQuery.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search,
                              size: 80,
                              color: ColorConstants.greyColor.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Search for messages',
                              style: TextStyle(
                                color: ColorConstants.greyColor,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 80,
                                  color:
                                      ColorConstants.greyColor.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No messages found',
                                  style: TextStyle(
                                    color: ColorConstants.greyColor,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              return _buildSearchResultItem(
                                  _searchResults[index]);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultItem(DecryptedSearchResult result) {
    final isMyMessage = result.message.idFrom == _currentUserId;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      int.parse(result.message.timestamp),
    );

    // Highlight từ khóa trong nội dung đã giải mã
    final content = result.decryptedContent;
    final queryIndex = content.toLowerCase().indexOf(_searchQuery);

    Widget contentWidget;
    if (queryIndex != -1) {
      final before = content.substring(0, queryIndex);
      final match = content.substring(
        queryIndex,
        queryIndex + _searchQuery.length,
      );
      final after = content.substring(queryIndex + _searchQuery.length);

      contentWidget = RichText(
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
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
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
          onTap: () {
            Navigator.pop(context, result.doc.id);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ColorConstants.greyColor2.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ColorConstants.greyColor2,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isMyMessage ? Icons.send : Icons.reply,
                      size: 16,
                      color: ColorConstants.greyColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isMyMessage ? 'You' : widget.peerName,
                      style: TextStyle(
                        color: isMyMessage
                            ? ColorConstants.primaryColor
                            : ColorConstants.greyColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('MMM dd, HH:mm').format(timestamp),
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

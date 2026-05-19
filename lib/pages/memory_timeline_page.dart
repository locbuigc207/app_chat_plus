import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';

class MemoryTimelinePage extends StatefulWidget {
  final String peerId;
  final String peerNickname;
  final String currentUserId;
  final String conversationId;

  const MemoryTimelinePage({
    super.key,
    required this.peerId,
    required this.peerNickname,
    required this.currentUserId,
    required this.conversationId,
  });

  @override
  _MemoryTimelinePageState createState() => _MemoryTimelinePageState();
}

class _MemoryTimelinePageState extends State<MemoryTimelinePage> {
  bool _isLoading = true;
  Map<String, dynamic>? _memoryData;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _fetchCachedMemory();
  }

  
  Future<void> _fetchCachedMemory() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('relationship_memories')
          .doc(widget.conversationId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        setState(() {
          _memoryData = data?['data'];
          _lastUpdated = (data?['lastUpdated'] as Timestamp?)?.toDate();
        });
      }
    } catch (e) {
      print("Lỗi đọc cache: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  
  Future<void> _analyzeMemory({bool forceRefresh = false}) async {
    
    if (!forceRefresh && _lastUpdated != null) {
      final daysSinceUpdate = DateTime.now().difference(_lastUpdated!).inDays;
      if (daysSinceUpdate < 7) {
        Fluttertoast.showToast(msg: "Dữ liệu AI đã được cập nhật gần đây.");
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      
      final querySnapshot = await FirebaseFirestore.instance
          .collection('messages')
          .doc(widget.conversationId)
          .collection(widget.conversationId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      if (querySnapshot.docs.isEmpty) {
        Fluttertoast.showToast(msg: "Chưa có đủ tin nhắn để phân tích.");
        setState(() => _isLoading = false);
        return;
      }

      List<String> chatHistory = querySnapshot.docs
          .map((doc) {
            final msg = MessageChat.fromDocument(doc);
            final senderName = msg.idFrom == widget.currentUserId
                ? "Tôi"
                : widget.peerNickname;
            return "$senderName: ${msg.content}";
          })
          .toList()
          .reversed
          .toList();

      
      final data =
          await AIBackendService().extractRelationshipMemory(chatHistory);

      if (data != null) {
        
        await FirebaseFirestore.instance
            .collection('relationship_memories')
            .doc(widget.conversationId)
            .set({
          'data': data,
          'lastUpdated': FieldValue.serverTimestamp(),
          'participants': [widget.currentUserId, widget.peerId]
        });

        setState(() {
          _memoryData = data;
          _lastUpdated = DateTime.now();
        });
        Fluttertoast.showToast(msg: "Đã cập nhật AI mới nhất!");
      } else {
        Fluttertoast.showToast(msg: "Lỗi phân tích AI.");
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Có lỗi xảy ra: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildHealthScore() {
    final score = _memoryData?['healthScore'] ?? 0;
    Color scoreColor = Colors.green;
    if (score < 50) {
      scoreColor = Colors.red;
    } else if (score < 75) scoreColor = Colors.orange;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Health Score",
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
              if (_lastUpdated != null)
                Text(
                  "Cập nhật: ${DateFormat('dd/MM/yyyy').format(_lastUpdated!)}",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "$score/100",
            style: TextStyle(
                fontSize: 40, fontWeight: FontWeight.bold, color: scoreColor),
          ),
          const SizedBox(height: 8),
          Text(
            _memoryData?['summary'] ?? "",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryTimeline() {
    final memories = _memoryData?['memories'] as List<dynamic>? ?? [];
    if (memories.isEmpty) return const SizedBox.shrink();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final mem = memories[index];
        final category = mem['category'] ?? 'memory';
        final content = mem['content'] ?? '';

        IconData icon = Icons.history;
        Color color = Colors.blue;
        String catName = "Kỷ niệm";

        if (category == 'preference') {
          icon = Icons.favorite;
          color = Colors.pink;
          catName = "Sở thích";
        } else if (category == 'promise') {
          icon = Icons.handshake;
          color = Colors.orange;
          catName = "Lời hứa";
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  child: Icon(icon, color: color)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(catName,
                        style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(content, style: const TextStyle(fontSize: 15)),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Relationship Memory',
            style: TextStyle(fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if (_memoryData != null)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.purple),
              onPressed: () => _analyzeMemory(forceRefresh: true),
              tooltip: "Cập nhật AI mới nhất",
            )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _memoryData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.psychology,
                          size: 80, color: Colors.purple),
                      const SizedBox(height: 16),
                      const Text("AI chưa phân tích mối quan hệ này.",
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple),
                        onPressed: () => _analyzeMemory(forceRefresh: true),
                        child: const Text("Khởi chạy AI Memory",
                            style: TextStyle(color: Colors.white)),
                      )
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHealthScore(),
                      const SizedBox(height: 24),
                      const Text(
                        "Ký ức & Sự kiện quan trọng",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _buildMemoryTimeline(),
                      const SizedBox(height: 24),
                      Center(
                        child: TextButton.icon(
                          onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection('relationship_memories')
                                .doc(widget.conversationId)
                                .delete();
                            setState(() {
                              _memoryData = null;
                              _lastUpdated = null;
                            });
                            Fluttertoast.showToast(msg: "Đã xóa dữ liệu AI.");
                          },
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text("Xóa dữ liệu Memory",
                              style: TextStyle(color: Colors.red)),
                        ),
                      )
                    ],
                  ),
                ),
    );
  }
}

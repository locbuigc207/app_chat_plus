import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/services.dart';

class AdaptiveChatBubble extends StatelessWidget {
  final MessageChat message;
  final String currentUserId;
  final String peerId;
  final String conversationId;

  /// Loại ngữ cảnh tin nhắn — dùng để hiển thị indicator đặc biệt (vd: 'study').
  final String contextType;

  const AdaptiveChatBubble({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.peerId,
    required this.conversationId,
    this.contextType = 'default',
  });

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final bool isMe = message.idFrom == currentUserId;

    // Ảnh / sticker / file → hiển thị trực tiếp
    if (message.type != TypeMessage.text) {
      return _buildImageOrFileMessage(isMe);
    }

    // Tin nhắn văn bản — dữ liệu từ Local DB đã được giải mã sẵn,
    // render trực tiếp message.content, không cần FutureBuilder/decryptPayload.
    // Loại bỏ hoàn toàn async decode để đạt 120 FPS khi cuộn.

    // 🤖 Kích hoạt AI scan phía client (chỉ với tin người khác gửi, chưa cảnh báo)
    if (!isMe && message.scamWarning != true) {
      _triggerClientSideAI(message.content, message.timestamp);
    }

    return _buildBubbleUI(
      context: context,
      isMe: isMe,
      text: message.content,
    );
  }

  // =========================================================
  // BUBBLE UI — ADAPTIVE THEO APP MODE
  // =========================================================

  Widget _buildBubbleUI({
    required BuildContext context,
    required bool isMe,
    required String text,
    Color? overrideColor,
  }) {
    final appMode = context.watch<AppModeProvider>().currentMode;

    // --- Giá trị mặc định ---
    double padding = 12.0;
    double fontSize = 16.0;
    FontWeight fontWeight = FontWeight.normal;
    Color bubbleColor = isMe ? Colors.blue : Colors.grey[300]!;
    Color textColor = isMe ? Colors.white : Colors.black87;
    BorderRadius borderRadius = BorderRadius.circular(16);
    List<BoxShadow>? boxShadow;

    // --- Ghi đè theo AppMode ---
    if (appMode == AppMode.elder) {
      padding = 20.0;
      fontSize = 24.0;
      fontWeight = FontWeight.w500;
      bubbleColor = isMe ? Colors.blue[800]! : Colors.grey[400]!;
      borderRadius = BorderRadius.circular(8);
      boxShadow = [const BoxShadow(color: Colors.black12, blurRadius: 4)];
    } else if (appMode == AppMode.work) {
      padding = 10.0;
      fontSize = 14.0;
      bubbleColor = isMe ? Colors.blueGrey : Colors.grey[800]!;
      textColor = Colors.white;
      borderRadius = BorderRadius.circular(4);
    } else if (appMode == AppMode.student) {
      bubbleColor = isMe ? Colors.purpleAccent : Colors.orangeAccent[100]!;
    }

    // Override màu khi có trạng thái đặc biệt
    if (overrideColor != null) {
      bubbleColor = overrideColor;
      textColor = Colors.black87;
    }

    // --- Context indicator (chỉ hiện trong student + study mode) ---
    Widget contextIndicator = const SizedBox.shrink();
    if (contextType == 'study' && appMode == AppMode.student) {
      contextIndicator = const Padding(
        padding: EdgeInsets.only(bottom: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 12, color: Colors.white70),
            SizedBox(width: 4),
            Text(
              'Study Note',
              style: TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: borderRadius,
          boxShadow: boxShadow,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            contextIndicator,
            Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: fontWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // IMAGE / FILE MESSAGE
  // =========================================================

  /// Hiển thị tin nhắn dạng ảnh hoặc file.
  Widget _buildImageOrFileMessage(bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.content,
          style: const TextStyle(color: Colors.black87),
        ),
      ),
    );
  }

  // =========================================================
  // CLIENT-SIDE AI SCAN
  // =========================================================

  /// Kích hoạt AI scan phía client sau khi tin nhắn được hiển thị.
  /// Chỉ gọi với tin nhắn người khác gửi đến và chưa được cảnh báo scam.
  /// Nên cache [messageId] đã scan (qua SharedPreferences) để tránh gọi lặp.
  void _triggerClientSideAI(String plainText, String messageId) {
    AIBackendService().analyzeDecryptedMessage(
      plainText: plainText,
      conversationId: conversationId,
      messageId: messageId,
      idFrom: peerId,
      idTo: currentUserId,
    );
  }
}

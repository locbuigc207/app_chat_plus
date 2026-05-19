import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_mode_provider.dart';

class AdaptiveChatBubble extends StatelessWidget {
  final String message;
  final bool isMe;
  final String contextType;

  const AdaptiveChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.contextType = 'default',
  });

  @override
  Widget build(BuildContext context) {
    final appMode = context.watch<AppModeProvider>().currentMode;

    double padding = 12.0;
    double fontSize = 16.0;
    Color bubbleColor = isMe ? Colors.blue : Colors.grey[300]!;
    Color textColor = isMe ? Colors.white : Colors.black;
    BorderRadius borderRadius = BorderRadius.circular(16);

    if (appMode == AppMode.elder) {
      padding = 20.0;
      fontSize = 24.0;
      bubbleColor = isMe ? Colors.blue[800]! : Colors.grey[400]!;
      borderRadius = BorderRadius.circular(8);
    } else if (appMode == AppMode.work) {
      padding = 10.0;
      fontSize = 14.0;
      bubbleColor = isMe ? Colors.blueGrey : Colors.grey[800]!;
      textColor = Colors.white;
      borderRadius = BorderRadius.circular(4);
    } else if (appMode == AppMode.student) {
      bubbleColor = isMe ? Colors.purpleAccent : Colors.orangeAccent[100]!;
    }

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
              "Study Note",
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
          boxShadow: appMode == AppMode.elder
              ? [const BoxShadow(color: Colors.black12, blurRadius: 4)]
              : null,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            contextIndicator,
            Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: appMode == AppMode.elder
                    ? FontWeight.w500
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

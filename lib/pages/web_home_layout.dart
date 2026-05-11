import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/color_constants.dart';
import 'package:flutter_chat_demo/pages/chat_page.dart';
import 'package:flutter_chat_demo/pages/home_page.dart';

class WebHomeLayout extends StatefulWidget {
  const WebHomeLayout({Key? key}) : super(key: key);

  @override
  State<WebHomeLayout> createState() => _WebHomeLayoutState();
}

class _WebHomeLayoutState extends State<WebHomeLayout> {
  Map<String, dynamic>? selectedChatInfo;

  void updateSelectedChat(Map<String, dynamic> chatInfo) {
    setState(() {
      selectedChatInfo = chatInfo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double sidebarWidth = MediaQuery.of(context).size.width * 0.35;
    if (sidebarWidth > 350) sidebarWidth = 350;
    if (sidebarWidth < 280) sidebarWidth = 280;

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: sidebarWidth,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color:
                      isDark ? ColorConstants.borderDark : Colors.grey.shade300,
                  width: 1,
                ),
              ),
            ),
            child: HomePage(
              onChatSelected: updateSelectedChat,
              isWebSidebar: true,
            ),
          ),
          Expanded(
            child: selectedChatInfo == null
                ? Container(
                    color:
                        isDark ? ColorConstants.backgroundDark : Colors.white,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 80, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Chọn một cuộc trò chuyện để bắt đầu',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ChatPage(
                    arguments: ChatPageArguments(
                      peerId: selectedChatInfo!['peerId'],
                      peerAvatar: selectedChatInfo!['peerAvatar'],
                      peerNickname: selectedChatInfo!['peerNickname'],
                    ),
                    isWebMode: true,
                  ),
          ),
        ],
      ),
    );
  }
}

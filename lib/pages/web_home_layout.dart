// lib/pages/web_home_layout.dart
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
    final screenWidth = MediaQuery.of(context).size.width;

    // Responsive sidebar: rộng hơn trên màn hình lớn, có min/max
    double sidebarWidth = screenWidth > 1200 ? 400 : 320;
    if (sidebarWidth > 400) sidebarWidth = 400;
    if (sidebarWidth < 280) sidebarWidth = 280;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar: Danh sách chat
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

          // Vùng hiển thị nội dung chat
          Expanded(
            child: Container(
              color: isDark ? ColorConstants.backgroundDark : Colors.white,
              child: selectedChatInfo == null
                  ? _buildWelcomeWeb(isDark)
                  : ChatPage(
                      arguments: ChatPageArguments(
                        peerId: selectedChatInfo!['peerId'],
                        peerAvatar: selectedChatInfo!['peerAvatar'],
                        peerNickname: selectedChatInfo!['peerNickname'],
                      ),
                      isWebMode: true,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeWeb(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 100,
            color: Colors.blue.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          Text(
            'Chọn một cuộc trò chuyện để bắt đầu',
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

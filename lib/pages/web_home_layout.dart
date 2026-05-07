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
  // Biến lưu trữ thông tin cuộc trò chuyện đang được chọn
  Map<String, dynamic>? selectedChatInfo;

  void updateSelectedChat(Map<String, dynamic> chatInfo) {
    setState(() {
      selectedChatInfo = chatInfo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children: [
          // BÊN TRÁI: Danh sách chat (chiếm 350px hoặc 30% màn hình)
          Container(
            width: 350,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color:
                      isDark ? ColorConstants.borderDark : Colors.grey.shade300,
                  width: 1,
                ),
              ),
            ),
            // Sửa HomePage của bạn để nó nhận callback khi click vào 1 item
            child: HomePage(
              onChatSelected: updateSelectedChat,
              isWebSidebar: true, // Biến cờ báo cho HomePage biết nó đang ở Web
            ),
          ),

          // BÊN PHẢI: Khung chat
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
                    // Truyền các tham số cần thiết vào ChatPage của bạn
                    arguments: ChatPageArguments(
                      peerId: selectedChatInfo!['peerId'],
                      peerAvatar: selectedChatInfo!['peerAvatar'],
                      peerNickname: selectedChatInfo!['peerNickname'],
                    ),
                    isWebMode:
                        true, // Cờ báo cho ChatPage không hiển thị nút Back
                  ),
          ),
        ],
      ),
    );
  }
}

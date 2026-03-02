// lib/widgets/bubble_manager.dart - COMPLETE FIXED VERSION
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/services/chat_bubble_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

class BubbleManager extends StatefulWidget {
  final Widget child;

  const BubbleManager({super.key, required this.child});

  @override
  State<BubbleManager> createState() => _BubbleManagerState();
}

class _BubbleManagerState extends State<BubbleManager>
    with WidgetsBindingObserver {
  ChatBubbleService? _bubbleService;
  StreamSubscription? _bubbleClickSubscription;
  StreamSubscription? _miniChatMessageSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeBubbleService();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('📱 App lifecycle changed: $state');
  }

  void _initializeBubbleService() {
    if (!Platform.isAndroid) return;

    try {
      _bubbleService = context.read<ChatBubbleService>();
      _listenToBubbleClicks();
      _listenToMiniChatMessages();
    } catch (e) {
      print('⚠️ BubbleManager: Service not available: $e');
    }
  }

  void _listenToBubbleClicks() {
    if (_bubbleService == null) return;

    _bubbleClickSubscription?.cancel();
    _bubbleClickSubscription = _bubbleService!.bubbleClickStream.listen(
      (event) {
        _handleBubbleClick(event);
      },
      onError: (error) {
        print('❌ Bubble click stream error: $error');
      },
    );

    print('✅ Bubble click listener setup');
  }

  void _listenToMiniChatMessages() {
    if (_bubbleService == null) return;

    _miniChatMessageSubscription?.cancel();
    _miniChatMessageSubscription = _bubbleService!.miniChatMessageStream.listen(
      (message) {
        _handleMiniChatMessage(message);
      },
      onError: (error) {
        print('❌ Mini chat message stream error: $error');
      },
    );

    print('✅ Mini chat message listener setup');
  }

  /// ✅ FIX: Don't hide bubble when clicked
  void _handleBubbleClick(BubbleClickEvent event) {
    if (!mounted) return;

    print('🫧 Bubble clicked: ${event.userName}');

    try {
      // ✅ FIX: Show dialog to choose action
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: Text(event.userName),
          content: Text('What would you like to do?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Hide bubble and open full chat
                _bubbleService?.hideChatBubble(event.userId);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      arguments: ChatPageArguments(
                        peerId: event.userId,
                        peerAvatar: event.avatarUrl,
                        peerNickname: event.userName,
                      ),
                    ),
                  ),
                );
              },
              child: Text('Open Full Chat'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // Hide bubble and show mini chat
                await _bubbleService?.hideChatBubble(event.userId);
                await Future.delayed(Duration(milliseconds: 200));
                await _bubbleService?.showMiniChat(
                  userId: event.userId,
                  userName: event.userName,
                  avatarUrl: event.avatarUrl,
                );
              },
              child: Text('Open Mini Chat'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ Error handling bubble click: $e');
      Fluttertoast.showToast(
        msg: 'Error opening chat',
        backgroundColor: Colors.red,
      );
    }
  }

  void _handleMiniChatMessage(MiniChatMessage message) {
    if (!mounted) return;

    print('💬 Mini chat message from ${message.userId}: ${message.message}');

    Fluttertoast.showToast(
      msg: '📨 Message sent: ${message.message}',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.TOP,
      backgroundColor: Colors.green,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bubbleClickSubscription?.cancel();
    _miniChatMessageSubscription?.cancel();
    super.dispose();
  }
}

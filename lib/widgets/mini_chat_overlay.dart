// lib/widgets/mini_chat_overlay.dart - COMPLETELY FIXED
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/pages/chat_page.dart';

/// ✅ Mini Chat: Render ChatPage trong overlay nhỏ với bounds validation
class MiniChatOverlay extends StatelessWidget {
  final String peerId;
  final String peerNickname;
  final String peerAvatar;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;

  const MiniChatOverlay({
    super.key,
    required this.peerId,
    required this.peerNickname,
    required this.peerAvatar,
    this.onMinimize,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ FIX: Get safe screen dimensions
    final screenSize = MediaQuery.of(context).size;
    final safeWidth = (screenSize.width * 0.85).clamp(280.0, 400.0);
    final safeHeight = (screenSize.height * 0.7).clamp(400.0, 650.0);

    return Container(
      width: safeWidth,
      height: safeHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // ✅ Custom header với minimize/close
          _buildHeader(context),

          // ✅ RENDER CHATPAGE (reuse toàn bộ logic)
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: ChatPage(
                arguments: ChatPageArguments(
                  peerId: peerId,
                  peerAvatar: peerAvatar,
                  peerNickname: peerNickname,
                ),
                isMiniChat: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xff2196f3),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage:
                peerAvatar.isNotEmpty ? NetworkImage(peerAvatar) : null,
            child: peerAvatar.isEmpty ? Icon(Icons.person, size: 16) : null,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              peerNickname,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(Icons.remove, color: Colors.white, size: 20),
            onPressed: onMinimize,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// ✅ FIXED: Draggable Mini Chat Overlay Widget with proper bounds validation
class MiniChatOverlayWidget extends StatefulWidget {
  final String peerId;
  final String peerNickname;
  final String peerAvatar;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const MiniChatOverlayWidget({
    super.key,
    required this.peerId,
    required this.peerNickname,
    required this.peerAvatar,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  State<MiniChatOverlayWidget> createState() => _MiniChatOverlayWidgetState();
}

class _MiniChatOverlayWidgetState extends State<MiniChatOverlayWidget> {
  late double _x;
  late double _y;
  late double _width;
  late double _height;

  @override
  void initState() {
    super.initState();
    // ✅ Initialize with safe defaults
    _x = 40.0;
    _y = 100.0;
    _width = 320.0;
    _height = 480.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ✅ FIX: Calculate safe dimensions after context is available
    final screenSize = MediaQuery.of(context).size;

    // Ensure width/height fit in screen
    _width = (_width).clamp(280.0, screenSize.width * 0.9);
    _height = (_height).clamp(400.0, screenSize.height * 0.8);

    // ✅ FIX: Safe position calculation with proper validation
    final maxX = (screenSize.width - _width).clamp(0.0, double.infinity);
    final maxY = (screenSize.height - _height).clamp(0.0, double.infinity);

    // Center if possible, otherwise clamp to safe bounds
    _x = ((screenSize.width - _width) / 2).clamp(0.0, maxX);
    _y = ((screenSize.height - _height) / 2).clamp(0.0, maxY);

    print('✅ Mini Chat size: ${_width.toInt()}x${_height.toInt()}');
    print('✅ Mini Chat position: (${_x.toInt()}, ${_y.toInt()})');
    print(
        '✅ Screen size: ${screenSize.width.toInt()}x${screenSize.height.toInt()}');
  }

  void _onPanUpdate(DragUpdateDetails details, Size screenSize) {
    setState(() {
      // ✅ FIX: Update position with safe bounds
      _x += details.delta.dx;
      _y += details.delta.dy;

      // ✅ FIX: Proper bounds validation
      final maxX = (screenSize.width - _width).clamp(0.0, double.infinity);
      final maxY = (screenSize.height - _height).clamp(0.0, double.infinity);

      _x = _x.clamp(0.0, maxX);
      _y = _y.clamp(0.0, maxY);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);

        // ✅ FIX: Validate dimensions before render
        if (_width > screenSize.width || _height > screenSize.height) {
          print('⚠️ Mini Chat too large for screen, adjusting...');
          _width = (screenSize.width * 0.85).clamp(280.0, 400.0);
          _height = (screenSize.height * 0.7).clamp(400.0, 650.0);

          // Recalculate position
          final maxX = (screenSize.width - _width).clamp(0.0, double.infinity);
          final maxY =
              (screenSize.height - _height).clamp(0.0, double.infinity);
          _x = _x.clamp(0.0, maxX);
          _y = _y.clamp(0.0, maxY);
        }

        return Stack(
          children: [
            Positioned(
              left: _x,
              top: _y,
              child: GestureDetector(
                onPanUpdate: (details) => _onPanUpdate(details, screenSize),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: _width,
                    height: _height,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Color(0xff2196f3),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Drag handle header
                        _buildDragHandle(),

                        // Chat content
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(14),
                            ),
                            child: ChatPage(
                              arguments: ChatPageArguments(
                                peerId: widget.peerId,
                                peerAvatar: widget.peerAvatar,
                                peerNickname: widget.peerNickname,
                              ),
                              isMiniChat: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDragHandle() {
    return Container(
      height: 50,
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Color(0xff2196f3),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          // Drag indicator
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Avatar
          CircleAvatar(
            radius: 14,
            backgroundImage: widget.peerAvatar.isNotEmpty
                ? NetworkImage(widget.peerAvatar)
                : null,
            child:
                widget.peerAvatar.isEmpty ? Icon(Icons.person, size: 14) : null,
          ),
          SizedBox(width: 8),

          // Name
          Expanded(
            child: Text(
              widget.peerNickname,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Minimize button
          IconButton(
            icon: Icon(Icons.remove, color: Colors.white, size: 18),
            onPressed: widget.onMinimize,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          // Close button
          IconButton(
            icon: Icon(Icons.close, color: Colors.white, size: 18),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

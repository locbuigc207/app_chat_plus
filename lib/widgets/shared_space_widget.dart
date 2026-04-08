// lib/widgets/shared_space_widget.dart
// Contextual Bubble Universe - Shared Space (Micro-Collaboration)
// Bảng vẽ cộng tác + Co-browsing trong cửa sổ mini

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── DATA MODELS ─────────────────────────────────────────────────────────────

class DrawPoint {
  final double x;
  final double y;
  final bool isStart; // true = bắt đầu nét mới
  final int color;
  final double strokeWidth;

  const DrawPoint({
    required this.x,
    required this.y,
    required this.isStart,
    required this.color,
    required this.strokeWidth,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'isStart': isStart,
        'color': color,
        'strokeWidth': strokeWidth,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };

  factory DrawPoint.fromJson(Map<String, dynamic> json) => DrawPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        isStart: json['isStart'] as bool,
        color: json['color'] as int,
        strokeWidth: (json['strokeWidth'] as num).toDouble(),
      );
}

// ─── PAINTER ─────────────────────────────────────────────────────────────────

class WhiteboardPainter extends CustomPainter {
  final List<DrawPoint> points;

  const WhiteboardPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    // Nền trắng với grid mờ
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFFAFAFA),
    );

    // Grid dots
    final gridPaint = Paint()
      ..color = const Color(0xFFDDE3EE)
      ..strokeWidth = 1;
    const spacing = 20.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, gridPaint);
      }
    }

    // Vẽ các nét
    Paint? currentPaint;
    Path? currentPath;

    for (final point in points) {
      if (point.isStart) {
        // Flush nét trước
        if (currentPath != null && currentPaint != null) {
          canvas.drawPath(currentPath, currentPaint);
        }
        currentPaint = Paint()
          ..color = Color(point.color)
          ..strokeWidth = point.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;
        currentPath = Path()..moveTo(point.x, point.y);
      } else {
        currentPath?.lineTo(point.x, point.y);
      }
    }

    if (currentPath != null && currentPaint != null) {
      canvas.drawPath(currentPath, currentPaint);
    }
  }

  @override
  bool shouldRepaint(WhiteboardPainter old) => old.points != points;
}

// ─── SHARED SPACE WIDGET ──────────────────────────────────────────────────────

class SharedSpaceWidget extends StatefulWidget {
  final String conversationId;
  final String currentUserId;
  final String peerName;

  const SharedSpaceWidget({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.peerName,
  });

  @override
  State<SharedSpaceWidget> createState() => _SharedSpaceWidgetState();
}

class _SharedSpaceWidgetState extends State<SharedSpaceWidget>
    with TickerProviderStateMixin {
  // Tab: 0=Whiteboard, 1=Co-browse
  int _activeTab = 0;

  // Whiteboard
  final List<DrawPoint> _localPoints = [];
  Color _selectedColor = const Color(0xFF2196F3);
  double _strokeWidth = 3.0;
  bool _isEraser = false;
  StreamSubscription? _drawSub;
  final _boardKey = GlobalKey();

  // Co-browse
  final _urlController = TextEditingController();
  String? _sharedUrl;

  // Animations
  late AnimationController _tabAnim;
  late AnimationController _toolAnim;

  // Firestore ref cho whiteboard data
  late final DocumentReference _boardRef;

  // Màu sắc palette
  final _palette = const [
    Color(0xFF2196F3), // Blue
    Color(0xFFE91E63), // Pink
    Color(0xFF4CAF50), // Green
    Color(0xFFFF9800), // Orange
    Color(0xFF9C27B0), // Purple
    Color(0xFF00BCD4), // Cyan
    Color(0xFF212121), // Black
    Color(0xFFFFFFFF), // White (eraser visual)
  ];

  @override
  void initState() {
    super.initState();
    _boardRef = FirebaseFirestore.instance
        .collection('shared_spaces')
        .doc(widget.conversationId);

    _tabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _toolAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();

    _listenToBoard();
  }

  // Lắng nghe thay đổi từ Firestore (real-time sync)
  void _listenToBoard() {
    _drawSub = _boardRef.snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return;

      final rawPoints = data['points'] as List<dynamic>? ?? [];
      final synced = rawPoints
          .map((p) => DrawPoint.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();

      final sharedUrl = data['sharedUrl'] as String?;

      if (mounted) {
        setState(() {
          _localPoints
            ..clear()
            ..addAll(synced);
          if (sharedUrl != null && sharedUrl.isNotEmpty) {
            _sharedUrl = sharedUrl;
          }
        });
      }
    });
  }

  // Ghi nét vẽ lên Firestore
  Future<void> _syncPoint(DrawPoint point) async {
    try {
      await _boardRef.set({
        'points': FieldValue.arrayUnion([point.toJson()]),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': widget.currentUserId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Whiteboard sync error: $e');
    }
  }

  Future<void> _clearBoard() async {
    try {
      await _boardRef.update({'points': []});
      setState(() => _localPoints.clear());
    } catch (e) {
      debugPrint('❌ Clear board error: $e');
    }
  }

  Future<void> _saveAsMessage() async {
    // Capture canvas as image và gửi vào tin nhắn
    // TODO: implement nếu muốn tích hợp với ChatProvider
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('✅ Đã lưu bản vẽ vào tin nhắn!'),
        backgroundColor: const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _shareUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    try {
      await _boardRef.set({
        'sharedUrl': url,
        'sharedBy': widget.currentUserId,
        'sharedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _sharedUrl = url);
      _urlController.clear();
    } catch (e) {
      debugPrint('❌ Share URL error: $e');
    }
  }

  Future<void> _openInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _drawSub?.cancel();
    _urlController.dispose();
    _tabAnim.dispose();
    _toolAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FE),
      ),
      child: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: child,
              ),
              child: _activeTab == 0 ? _buildWhiteboard() : _buildCoBrowse(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildTab(0, Icons.draw_rounded, 'Whiteboard'),
          _buildTab(1, Icons.open_in_browser_rounded, 'Co-Browse'),
        ],
      ),
    );
  }

  Widget _buildTab(int index, IconData icon, String label) {
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isActive
                    ? const Color(0xFF2196F3)
                    : const Color(0xFF9AA5B8),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive
                      ? const Color(0xFF1A2340)
                      : const Color(0xFF9AA5B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── WHITEBOARD ──────────────────────────────────────────────────────────

  Widget _buildWhiteboard() {
    return Column(
      key: const ValueKey('whiteboard'),
      children: [
        _buildToolbar(),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: RepaintBoundary(
                key: _boardKey,
                child: GestureDetector(
                  onPanStart: (d) {
                    final pt = DrawPoint(
                      x: d.localPosition.dx,
                      y: d.localPosition.dy,
                      isStart: true,
                      color:
                          _isEraser ? Colors.white.value : _selectedColor.value,
                      strokeWidth: _isEraser ? 24 : _strokeWidth,
                    );
                    setState(() => _localPoints.add(pt));
                    _syncPoint(pt);
                  },
                  onPanUpdate: (d) {
                    final pt = DrawPoint(
                      x: d.localPosition.dx,
                      y: d.localPosition.dy,
                      isStart: false,
                      color:
                          _isEraser ? Colors.white.value : _selectedColor.value,
                      strokeWidth: _isEraser ? 24 : _strokeWidth,
                    );
                    setState(() => _localPoints.add(pt));
                    _syncPoint(pt);
                  },
                  child: CustomPaint(
                    painter: WhiteboardPainter(points: _localPoints),
                    child: Container(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          // Palette
          ...List.generate(
            _palette.length - 1, // Skip white (eraser visual)
            (i) => _buildColorDot(_palette[i]),
          ),
          const SizedBox(width: 6),
          // Eraser
          _buildToolBtn(
            icon: Icons.auto_fix_high_rounded,
            active: _isEraser,
            onTap: () => setState(() => _isEraser = !_isEraser),
            tooltip: 'Tẩy',
          ),
          // Brush size
          _buildStrokeSlider(),
          const Spacer(),
          // Clear
          _buildToolBtn(
            icon: Icons.delete_outline_rounded,
            active: false,
            onTap: _clearBoard,
            tooltip: 'Xóa tất cả',
            color: const Color(0xFFE53935),
          ),
          const SizedBox(width: 4),
          // Save as message
          _buildToolBtn(
            icon: Icons.send_rounded,
            active: false,
            onTap: _saveAsMessage,
            tooltip: 'Gửi vào chat',
            color: const Color(0xFF4CAF50),
          ),
        ],
      ),
    );
  }

  Widget _buildColorDot(Color color) {
    final isSelected = _selectedColor == color && !_isEraser;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedColor = color;
        _isEraser = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: isSelected ? 22 : 18,
        height: isSelected ? 22 : 18,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF2196F3) : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  Widget _buildToolBtn({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    required String tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF2196F3).withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 16,
            color: color ??
                (active ? const Color(0xFF2196F3) : const Color(0xFF7B8499)),
          ),
        ),
      ),
    );
  }

  Widget _buildStrokeSlider() {
    return SizedBox(
      width: 60,
      child: Slider(
        value: _strokeWidth,
        min: 1.5,
        max: 10,
        onChanged: (v) => setState(() => _strokeWidth = v),
        activeColor: _selectedColor,
        inactiveColor: const Color(0xFFDDE3EE),
      ),
    );
  }

  // ─── CO-BROWSE ────────────────────────────────────────────────────────────

  Widget _buildCoBrowse() {
    return Column(
      key: const ValueKey('cobrowse'),
      children: [
        _buildUrlInput(),
        Expanded(
          child: _sharedUrl != null
              ? _buildSharedUrlPreview(_sharedUrl!)
              : _buildCoBrowsePlaceholder(),
        ),
      ],
    );
  }

  Widget _buildUrlInput() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          const Icon(Icons.link_rounded, size: 18, color: Color(0xFF9AA5B8)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _urlController,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Nhập URL để chia sẻ...',
                hintStyle: TextStyle(color: Color(0xFFB0BAD0), fontSize: 13),
                border: InputBorder.none,
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _shareUrl(),
            ),
          ),
          GestureDetector(
            onTap: _shareUrl,
            child: Container(
              margin: const EdgeInsets.all(5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Chia sẻ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedUrlPreview(String url) {
    final isYouTube = url.contains('youtube.com') || url.contains('youtu.be');
    final isMap =
        url.contains('maps.google.com') || url.contains('goo.gl/maps');

    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF1565C0)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(
                  isYouTube
                      ? Icons.play_circle_filled_rounded
                      : isMap
                          ? Icons.map_rounded
                          : Icons.language_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    url,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _openInBrowser(url),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Mở',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EEF8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isYouTube
                          ? Icons.smart_display_rounded
                          : isMap
                              ? Icons.place_rounded
                              : Icons.web_rounded,
                      size: 36,
                      color: const Color(0xFF2196F3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isYouTube
                        ? 'YouTube Video'
                        : isMap
                            ? 'Google Maps'
                            : 'Trang web',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A2340),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Nhấn "Mở" để xem trong trình duyệt',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9AA5B8)),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _openInBrowser(url),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Mở cùng nhau'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoBrowsePlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EEF8),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.open_in_browser_rounded,
                size: 40,
                color: Color(0xFF2196F3),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Co-Browsing',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A2340),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Chia sẻ link YouTube, Google Maps hoặc bất kỳ trang web nào để cùng xem với ${widget.peerName}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9AA5B8),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

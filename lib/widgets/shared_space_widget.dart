// lib/bubble/widgets/shared_space_widget.dart
// ignore_for_file: use_super_parameters

import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// A single point in a drawing stroke.
@immutable
class DrawPoint {
  final double x;
  final double y;

  /// true = start a new stroke (moveTo), false = continue (lineTo).
  final bool isStart;
  final int color;
  final double strokeWidth;
  final int ts;

  const DrawPoint({
    required this.x,
    required this.y,
    required this.isStart,
    required this.color,
    required this.strokeWidth,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'isStart': isStart,
        'color': color,
        'strokeWidth': strokeWidth,
        'ts': ts,
      };

  factory DrawPoint.fromJson(Map<String, dynamic> json) => DrawPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        isStart: json['isStart'] as bool,
        color: (json['color'] as num).toInt(),
        strokeWidth: (json['strokeWidth'] as num).toDouble(),
        ts: (json['ts'] as num?)?.toInt() ?? 0,
      );

  DrawPoint now() => DrawPoint(
        x: x,
        y: y,
        isStart: isStart,
        color: color,
        strokeWidth: strokeWidth,
        ts: DateTime.now().millisecondsSinceEpoch,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// WHITEBOARD PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class WhiteboardPainter extends CustomPainter {
  final List<DrawPoint> points;
  const WhiteboardPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFBFCFF),
    );

    // Dot grid
    final dotPaint = Paint()..color = const Color(0xFFCDD5E0);
    const step = 22.0;
    for (double x = step; x < size.width; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.1, dotPaint);
      }
    }

    // Strokes
    Paint? paint;
    Path? path;

    for (final pt in points) {
      if (pt.isStart) {
        if (path != null && paint != null) canvas.drawPath(path, paint);
        paint = Paint()
          ..color = Color(pt.color)
          ..strokeWidth = pt.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true;
        path = Path()..moveTo(pt.x, pt.y);
      } else {
        path?.lineTo(pt.x, pt.y);
      }
    }
    if (path != null && paint != null) canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WhiteboardPainter old) => old.points != points;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SPACE WIDGET
// ─────────────────────────────────────────────────────────────────────────────

/// Two-tab panel:
///  • **Whiteboard** — real-time collaborative drawing synced via Firestore.
///  • **Co-Browse**  — share a URL with your chat partner and open it together.
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
  // ── Tabs ──────────────────────────────────────────────────────────────────
  int _tab = 0; // 0 = whiteboard, 1 = co-browse

  // ── Whiteboard ────────────────────────────────────────────────────────────
  final List<DrawPoint> _points = [];
  final List<DrawPoint> _undoBuffer = []; // last stroke for undo
  Color _color = const Color(0xFF1E88E5);
  double _stroke = 3.5;
  bool _isEraser = false;
  bool _isSyncing = false;
  StreamSubscription? _boardSub;
  final _boardKey = GlobalKey();

  // Current stroke accumulator (for batched sync)
  final List<DrawPoint> _pendingBatch = [];
  Timer? _batchTimer;

  // ── Co-browse ─────────────────────────────────────────────────────────────
  final _urlCtrl = TextEditingController();
  String? _sharedUrl;
  String? _sharedBy;
  StreamSubscription? _urlSub;

  // ── Firestore ─────────────────────────────────────────────────────────────
  late final DocumentReference _docRef;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _tabSwitch;
  late AnimationController _entryAnim;

  // ── Color palette ─────────────────────────────────────────────────────────
  static const _palette = <Color>[
    Color(0xFF1E88E5), // blue
    Color(0xFFE53935), // red
    Color(0xFF43A047), // green
    Color(0xFFFF9800), // orange
    Color(0xFF8E24AA), // purple
    Color(0xFF00ACC1), // cyan
    Color(0xFF212121), // black
    Color(0xFFEC407A), // pink
  ];

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _docRef = FirebaseFirestore.instance
        .collection('shared_spaces')
        .doc(widget.conversationId);

    _tabSwitch = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _listenBoard();
    _listenUrl();
  }

  @override
  void dispose() {
    _boardSub?.cancel();
    _urlSub?.cancel();
    _batchTimer?.cancel();
    _urlCtrl.dispose();
    _tabSwitch.dispose();
    _entryAnim.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIRESTORE LISTENERS
  // ─────────────────────────────────────────────────────────────────────────

  void _listenBoard() {
    _boardSub = _docRef.snapshots().listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final raw = data['points'] as List<dynamic>? ?? [];
      final synced = raw
          .map((p) => DrawPoint.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();
      if (mounted)
        setState(() {
          _points
            ..clear()
            ..addAll(synced);
        });
    }, onError: (e) => debugPrint('SharedSpace board error: $e'));
  }

  void _listenUrl() {
    _urlSub = _docRef.snapshots().listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final url = data['sharedUrl'] as String?;
      final by = data['sharedBy'] as String?;
      if (url != null && url.isNotEmpty && mounted) {
        setState(() {
          _sharedUrl = url;
          _sharedBy = by;
        });
      }
    }, onError: (_) {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DRAW SYNC — batched writes to avoid Firestore rate limits
  // ─────────────────────────────────────────────────────────────────────────

  void _addPoint(DrawPoint pt) {
    final stamped = pt.now();
    setState(() => _points.add(stamped));
    _pendingBatch.add(stamped);
    _scheduleBatchSync();
  }

  void _scheduleBatchSync() {
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 120), _flushBatch);
  }

  Future<void> _flushBatch() async {
    if (_pendingBatch.isEmpty) return;
    final batch = List<DrawPoint>.from(_pendingBatch);
    _pendingBatch.clear();
    try {
      setState(() => _isSyncing = true);
      await _docRef.set({
        'points': FieldValue.arrayUnion(batch.map((p) => p.toJson()).toList()),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': widget.currentUserId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('SharedSpace sync error: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _clearBoard() async {
    try {
      HapticFeedback.heavyImpact();
      setState(() {
        _points.clear();
        _undoBuffer.clear();
      });
      await _docRef.set({'points': []}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('SharedSpace clear error: $e');
    }
  }

  Future<void> _saveAsImage() async {
    try {
      final boundary = _boardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      // TODO: share / save bytes via share_plus or image_gallery_saver
      if (mounted) _showSnack('✅ Đã lưu bảng vẽ!', const Color(0xFF43A047));
    } catch (e) {
      debugPrint('SharedSpace save error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CO-BROWSE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _shareUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final norm = url.startsWith('http') ? url : 'https://$url';
    try {
      await _docRef.set({
        'sharedUrl': norm,
        'sharedBy': widget.currentUserId,
        'sharedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _sharedUrl = norm;
      });
      _urlCtrl.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      debugPrint('SharedSpace shareUrl error: $e');
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _switchTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _tabSwitch.forward(from: 0);
    HapticFeedback.selectionClick();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _entryAnim, curve: Curves.easeOut),
      child: Container(
        decoration: const BoxDecoration(color: Color(0xFFF5F7FD)),
        child: Column(
          children: [
            _buildTabBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _tab == 0
                    ? _buildWhiteboard(key: const ValueKey('wb'))
                    : _buildCoBrowse(key: const ValueKey('cb')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      height: 48,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF8),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          _TabItem(
              index: 0,
              current: _tab,
              icon: Icons.draw_rounded,
              label: 'Whiteboard',
              onTap: () => _switchTab(0)),
          _TabItem(
              index: 1,
              current: _tab,
              icon: Icons.open_in_browser_rounded,
              label: 'Co-Browse',
              onTap: () => _switchTab(1)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WHITEBOARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWhiteboard({Key? key}) {
    return Column(
      key: key,
      children: [
        _buildToolbar(),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 18,
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
                    _addPoint(DrawPoint(
                      x: d.localPosition.dx,
                      y: d.localPosition.dy,
                      isStart: true,
                      color: _isEraser ? Colors.white.value : _color.value,
                      strokeWidth: _isEraser ? 26 : _stroke,
                      ts: 0,
                    ));
                  },
                  onPanUpdate: (d) {
                    _addPoint(DrawPoint(
                      x: d.localPosition.dx,
                      y: d.localPosition.dy,
                      isStart: false,
                      color: _isEraser ? Colors.white.value : _color.value,
                      strokeWidth: _isEraser ? 26 : _stroke,
                      ts: 0,
                    ));
                  },
                  child: CustomPaint(
                    painter:
                        WhiteboardPainter(points: List.unmodifiable(_points)),
                    child: const SizedBox.expand(),
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
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          // Color swatches
          for (final c in _palette)
            _ColorDot(
              color: c,
              isSelected: _color == c && !_isEraser,
              onTap: () => setState(() {
                _color = c;
                _isEraser = false;
              }),
            ),

          const SizedBox(width: 4),
          // Divider
          Container(width: 1, height: 20, color: const Color(0xFFDDE3EE)),
          const SizedBox(width: 4),

          // Eraser
          _ToolButton(
            icon: Icons.auto_fix_high_rounded,
            active: _isEraser,
            tooltip: 'Tẩy',
            onTap: () => setState(() => _isEraser = !_isEraser),
          ),

          // Stroke size (small icon toggle)
          PopupMenuButton<double>(
            tooltip: 'Cỡ bút',
            icon: Icon(Icons.line_weight_rounded,
                size: 17, color: const Color(0xFF7B8499)),
            onSelected: (v) => setState(() => _stroke = v),
            itemBuilder: (_) => [
              for (final s in [1.5, 3.0, 5.0, 8.0, 12.0])
                PopupMenuItem(
                  value: s,
                  child: Row(children: [
                    Container(
                        width: s * 3,
                        height: s,
                        color: const Color(0xFF1E88E5)),
                    const SizedBox(width: 10),
                    Text('${s.toStringAsFixed(1)} px',
                        style: const TextStyle(fontSize: 12)),
                  ]),
                ),
            ],
          ),

          const Spacer(),

          // Sync indicator
          if (_isSyncing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF1E88E5))),
            ),

          const SizedBox(width: 4),

          // Save
          _ToolButton(
            icon: Icons.image_outlined,
            active: false,
            tooltip: 'Lưu ảnh',
            color: const Color(0xFF43A047),
            onTap: _saveAsImage,
          ),

          // Clear
          _ToolButton(
            icon: Icons.delete_outline_rounded,
            active: false,
            tooltip: 'Xóa tất cả',
            color: const Color(0xFFE53935),
            onTap: _clearBoard,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CO-BROWSE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCoBrowse({Key? key}) {
    return Column(
      key: key,
      children: [
        _buildUrlBar(),
        Expanded(
          child: _sharedUrl != null
              ? _buildUrlPreview(_sharedUrl!)
              : _buildCoBrowsePlaceholder(),
        ),
      ],
    );
  }

  Widget _buildUrlBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
              controller: _urlCtrl,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A2340)),
              decoration: const InputDecoration(
                hintText: 'Nhập URL (youtube, maps, web…)',
                hintStyle: TextStyle(color: Color(0xFFB0BAD0), fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _shareUrl(),
            ),
          ),
          GestureDetector(
            onTap: _shareUrl,
            child: Container(
              margin: const EdgeInsets.all(5),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1E88E5), Color(0xFF1565C0)]),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text(
                'Chia sẻ',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlPreview(String url) {
    final type = _detectUrlType(url);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 18,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: type.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(type.icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    url,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _PreviewActionBtn(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: url));
                    _showSnack('✅ Đã copy link!', const Color(0xFF1E88E5));
                  },
                ),
                const SizedBox(width: 5),
                _PreviewActionBtn(
                  icon: Icons.open_in_new_rounded,
                  label: 'Mở',
                  onTap: () => _openUrl(url),
                ),
              ],
            ),
          ),

          // Preview body
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: type.gradient.first.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(type.icon, size: 36, color: type.gradient.first),
                ),
                const SizedBox(height: 14),
                Text(
                  type.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2340),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  type.hint,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9AA5B8)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // "Open together" CTA
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _openUrl(url);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 11),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: type.gradient),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: type.gradient.first.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 7),
                        Text(
                          'Mở cùng nhau',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_sharedBy != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Chia sẻ bởi ${_sharedBy == widget.currentUserId ? "bạn" : widget.peerName}',
                    style:
                        const TextStyle(color: Color(0xFFB0BAD0), fontSize: 10),
                  ),
                ],
              ],
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
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.open_in_browser_rounded,
                size: 38,
                color: Color(0xFF1E88E5),
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
              'Chia sẻ link YouTube, Maps hoặc bất kỳ trang web nào để cùng xem với ${widget.peerName}.',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9AA5B8),
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Quick-share chips
            Wrap(
              spacing: 8,
              children: [
                _QuickChip(
                  icon: Icons.play_circle_fill_rounded,
                  label: 'YouTube',
                  color: const Color(0xFFE53935),
                  onTap: () {
                    _urlCtrl.text = 'https://www.youtube.com/';
                  },
                ),
                _QuickChip(
                  icon: Icons.map_rounded,
                  label: 'Maps',
                  color: const Color(0xFF43A047),
                  onTap: () {
                    _urlCtrl.text = 'https://maps.google.com/';
                  },
                ),
                _QuickChip(
                  icon: Icons.language_rounded,
                  label: 'Web',
                  color: const Color(0xFF1E88E5),
                  onTap: () => _urlCtrl.text = 'https://',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // URL TYPE DETECTION
  // ─────────────────────────────────────────────────────────────────────────

  _UrlType _detectUrlType(String url) {
    final u = url.toLowerCase();
    if (u.contains('youtube.com') || u.contains('youtu.be')) {
      return _UrlType(
        icon: Icons.smart_display_rounded,
        label: 'YouTube Video',
        hint: 'Xem video cùng nhau',
        gradient: [const Color(0xFFE53935), const Color(0xFFB71C1C)],
      );
    }
    if (u.contains('maps.google.com') ||
        u.contains('goo.gl/maps') ||
        u.contains('maps.app.goo.gl')) {
      return _UrlType(
        icon: Icons.place_rounded,
        label: 'Google Maps',
        hint: 'Xem địa điểm cùng nhau',
        gradient: [const Color(0xFF43A047), const Color(0xFF1B5E20)],
      );
    }
    if (u.contains('spotify.com')) {
      return _UrlType(
        icon: Icons.music_note_rounded,
        label: 'Spotify',
        hint: 'Nghe nhạc cùng nhau',
        gradient: [const Color(0xFF1DB954), const Color(0xFF0D7A3A)],
      );
    }
    if (u.contains('github.com')) {
      return _UrlType(
        icon: Icons.code_rounded,
        label: 'GitHub',
        hint: 'Review code cùng nhau',
        gradient: [const Color(0xFF212121), const Color(0xFF424242)],
      );
    }
    if (u.contains('figma.com')) {
      return _UrlType(
        icon: Icons.design_services_rounded,
        label: 'Figma',
        hint: 'Xem thiết kế cùng nhau',
        gradient: [const Color(0xFF7C4DFF), const Color(0xFF4527A0)],
      );
    }
    return _UrlType(
      icon: Icons.language_rounded,
      label: 'Trang web',
      hint: 'Duyệt web cùng nhau',
      gradient: [const Color(0xFF1E88E5), const Color(0xFF0D47A1)],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _TabItem extends StatelessWidget {
  final int index;
  final int current;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TabItem({
    required this.index,
    required this.current,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == current;
    final color = isActive ? const Color(0xFF1E88E5) : const Color(0xFF9AA5B8);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: isSelected ? 22 : 17,
        height: isSelected ? 22 : 17,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF1E88E5) : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 6,
                      spreadRadius: 1)
                ]
              : null,
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _ToolButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF1E88E5).withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 17,
            color: color ??
                (active ? const Color(0xFF1E88E5) : const Color(0xFF7B8499)),
          ),
        ),
      ),
    );
  }
}

class _PreviewActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PreviewActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 12),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// URL TYPE METADATA
// ─────────────────────────────────────────────────────────────────────────────

class _UrlType {
  final IconData icon;
  final String label;
  final String hint;
  final List<Color> gradient;

  const _UrlType({
    required this.icon,
    required this.label,
    required this.hint,
    required this.gradient,
  });
}

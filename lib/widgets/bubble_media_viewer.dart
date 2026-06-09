// lib/widgets/bubble_media_viewer.dart
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OPEN HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Open a single image in full-screen viewer.
Future<void> openImageViewer(
  BuildContext context, {
  required String url,
  String? heroTag,
  String? senderName,
  String? timestamp,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => BubbleMediaViewer(
        url: url,
        heroTag: heroTag ?? url,
        senderName: senderName,
        timestamp: timestamp,
      ),
    ),
  );
}

/// Open multiple images as a swipeable gallery.
Future<void> openGalleryViewer(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
  String? heroTag,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => BubbleGalleryViewer(
        urls: urls,
        initialIndex: initialIndex,
        heroTag: heroTag,
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SINGLE IMAGE VIEWER
// ═══════════════════════════════════════════════════════════════════════════

class BubbleMediaViewer extends StatefulWidget {
  final String url;
  final String heroTag;
  final String? senderName;
  final String? timestamp;

  const BubbleMediaViewer({
    super.key,
    required this.url,
    required this.heroTag,
    this.senderName,
    this.timestamp,
  });

  @override
  State<BubbleMediaViewer> createState() => _BubbleMediaViewerState();
}

class _BubbleMediaViewerState extends State<BubbleMediaViewer>
    with SingleTickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late Animation<double> _bgFade;

  final _transformCtrl = TransformationController();
  bool _isZoomed = false;
  bool _showControls = true;

  // Swipe-to-dismiss
  double _dragY = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _bgFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _bgCtrl, curve: Curves.easeOut));
    _bgCtrl.forward();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _transformCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _close() {
    _bgCtrl.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    }
  }

  Future<void> _shareImage() async {
    try {
      final file = await DefaultCacheManager().getSingleFile(widget.url);
      await Share.shareXFiles([XFile(file.path)],
          subject: widget.senderName != null
              ? 'Ảnh từ ${widget.senderName}'
              : 'Hình ảnh');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể chia sẻ ảnh')));
      }
    }
  }

  // ─── Drag-to-dismiss ──────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) {
    if (_isZoomed) return;
    setState(() {
      _dragY += d.delta.dy;
      _dragging = true;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    final velocity = d.velocity.pixelsPerSecond.dy;
    if (_dragY.abs() > 120 || velocity.abs() > 800) {
      _close();
    } else {
      setState(() => _dragY = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dismissProgress = (_dragY.abs() / 300).clamp(0.0, 1.0);

    return FadeTransition(
      opacity: _bgFade,
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(1 - dismissProgress * 0.7),
        body: GestureDetector(
          onTap: _toggleControls,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          child: Stack(
            children: [
              // ── Image ─────────────────────────────────────────────────
              Center(
                child: Transform.translate(
                  offset: Offset(0, _dragY),
                  child: Transform.scale(
                    scale: 1 - dismissProgress * 0.15,
                    child: Hero(
                      tag: widget.heroTag,
                      child: InteractiveViewer(
                        transformationController: _transformCtrl,
                        minScale: 0.8,
                        maxScale: 5.0,
                        onInteractionEnd: (_) {
                          final scale =
                              _transformCtrl.value.getMaxScaleOnAxis();
                          setState(() => _isZoomed = scale > 1.05);
                        },
                        child: CachedNetworkImage(
                          imageUrl: widget.url,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => _ShimmerPlaceholder(),
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.broken_image_rounded,
                              color: Colors.white54,
                              size: 64),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Top bar ────────────────────────────────────────────────
              AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: _TopBar(
                  senderName: widget.senderName,
                  timestamp: widget.timestamp,
                  onClose: _close,
                  onShare: _shareImage,
                ),
              ),

              // ── Bottom actions ─────────────────────────────────────────
              if (_showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _BottomBar(
                    onShare: _shareImage,
                    onZoomReset: _isZoomed
                        ? () {
                            _transformCtrl.value = Matrix4.identity();
                            setState(() => _isZoomed = false);
                          }
                        : null,
                  ),
                ),

              // ── Drag hint ──────────────────────────────────────────────
              if (_dragging && _dragY.abs() > 20)
                Positioned(
                  bottom: 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: dismissProgress.clamp(0.0, 1.0),
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20)),
                        child: const Text('Thả để đóng',
                            style:
                                TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String? senderName;
  final String? timestamp;
  final VoidCallback onClose;
  final VoidCallback onShare;

  const _TopBar(
      {this.senderName,
      this.timestamp,
      required this.onClose,
      required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.7), Colors.transparent],
        ),
      ),
      padding:
          EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 16),
      child: Row(
        children: [
          // Close
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: onClose,
          ),
          const SizedBox(width: 4),
          // Sender info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (senderName != null)
                  Text(senderName!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                if (timestamp != null)
                  Text(timestamp!,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7), fontSize: 12)),
              ],
            ),
          ),
          // Share
          IconButton(
            icon:
                const Icon(Icons.share_rounded, color: Colors.white, size: 22),
            onPressed: onShare,
          ),
        ],
      ),
    );
  }
}

// ─── Bottom bar ───────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback? onZoomReset;

  const _BottomBar({required this.onShare, this.onZoomReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.6), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (onZoomReset != null) ...[
            _BarBtn(
              icon: Icons.zoom_out_map_rounded,
              label: 'Khôi phục',
              onTap: onZoomReset!,
            ),
            const SizedBox(width: 24),
          ],
          _BarBtn(
            icon: Icons.share_rounded,
            label: 'Chia sẻ',
            onTap: onShare,
          ),
        ],
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BarBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── Shimmer placeholder ──────────────────────────────────────────────────────

class _ShimmerPlaceholder extends StatefulWidget {
  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        color: Colors.white.withOpacity(_anim.value * 0.1),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GALLERY VIEWER (multiple images)
// ═══════════════════════════════════════════════════════════════════════════

class BubbleGalleryViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final String? heroTag;

  const BubbleGalleryViewer({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.heroTag,
  });

  @override
  State<BubbleGalleryViewer> createState() => _BubbleGalleryViewerState();
}

class _BubbleGalleryViewerState extends State<BubbleGalleryViewer>
    with SingleTickerProviderStateMixin {
  late PageController _pageCtrl;
  late AnimationController _bgCtrl;
  late Animation<double> _bgFade;
  int _current = 0;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _bgFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _bgCtrl, curve: Curves.easeOut));
    _bgCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _bgCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _close() => _bgCtrl.reverse().then((_) {
        if (mounted) Navigator.of(context).pop();
      });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _bgFade,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Page view
            GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (_, i) => InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[i],
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (_, __) => _ShimmerPlaceholder(),
                    errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white54,
                        size: 64),
                  ),
                ),
              ),
            ),

            // Top bar
            AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: _GalleryTopBar(
                current: _current,
                total: widget.urls.length,
                onClose: _close,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryTopBar extends StatelessWidget {
  final int current;
  final int total;
  final VoidCallback onClose;
  const _GalleryTopBar(
      {required this.current, required this.total, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.7), Colors.transparent]),
      ),
      padding: EdgeInsets.fromLTRB(
          4, MediaQuery.of(context).padding.top + 4, 16, 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: onClose,
          ),
          Expanded(
            child: Text('${current + 1} / $total',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

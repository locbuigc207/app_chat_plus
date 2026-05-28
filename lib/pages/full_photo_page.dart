import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';

import '../constants/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FullPhotoPage — single-image immersive viewer
// ─────────────────────────────────────────────────────────────────────────────

class FullPhotoPage extends StatefulWidget {
  final String url;
  final String? heroTag;
  final String? senderName;

  const FullPhotoPage({
    super.key,
    required this.url,
    this.heroTag,
    this.senderName,
  });

  @override
  State<FullPhotoPage> createState() => _FullPhotoPageState();
}

class _FullPhotoPageState extends State<FullPhotoPage>
    with SingleTickerProviderStateMixin {
  bool _showControls = true;
  late final AnimationController _ctrlsAnim;
  late final Animation<double> _ctrlsFade;
  Timer? _hideTimer;

  final _photoController = PhotoViewController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _ctrlsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
    _ctrlsFade = CurvedAnimation(parent: _ctrlsAnim, curve: Curves.easeOut);

    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _ctrlsAnim.reverse();
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _ctrlsAnim.forward();
      _scheduleHide();
    } else {
      _ctrlsAnim.reverse();
      _hideTimer?.cancel();
    }
  }

  void _resetZoom() {
    _photoController.reset();
  }

  @override
  void dispose() {
    _ctrlsAnim.dispose();
    _photoController.dispose();
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTap: _resetZoom,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Photo view ─────────────────────────────────────────────────
            Hero(
              tag: widget.heroTag ?? widget.url,
              child: PhotoView(
                controller: _photoController,
                imageProvider: NetworkImage(widget.url),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                initialScale: PhotoViewComputedScale.contained,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                loadingBuilder: (context, event) {
                  final progress = event == null
                      ? null
                      : event.cumulativeBytesLoaded /
                          (event.expectedTotalBytes ?? 1);
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            value: progress,
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        if (progress != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_rounded,
                          color: Colors.white30, size: 64),
                      const SizedBox(height: 16),
                      const Text('Không thể tải ảnh',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),

            // ── Top bar ─────────────────────────────────────────────────────
            FadeTransition(
              opacity: _ctrlsFade,
              child: Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.72),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Row(
                          children: [
                            // Back
                            _BarBtn(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onTap: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            // Title
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.senderName ??
                                        AppConstants.fullPhotoTitle,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Text(
                                    'Chạm 2 lần để đặt lại',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            // Share
                            _BarBtn(
                              icon: Icons.share_rounded,
                              onTap: _onShare,
                            ),
                            // Download
                            _BarBtn(
                              icon: Icons.download_rounded,
                              onTap: _onDownload,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom hint ─────────────────────────────────────────────────
            FadeTransition(
              opacity: _ctrlsFade,
              child: Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                    top: 24,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pinch_rounded,
                          color: Colors.white38, size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        'Kéo để thu phóng',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onShare() {
    HapticFeedback.lightImpact();
    // Share.shareUri(Uri.parse(widget.url));
  }

  void _onDownload() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Đang tải xuống ảnh…'),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _BarBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

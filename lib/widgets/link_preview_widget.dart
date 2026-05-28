// link_preview_widget.dart
import 'dart:async';

import 'package:any_link_preview/any_link_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkPreviewWidget extends StatefulWidget {
  final String url;
  final bool isMe;

  const LinkPreviewWidget({
    super.key,
    required this.url,
    this.isMe = false,
  });

  @override
  State<LinkPreviewWidget> createState() => _LinkPreviewWidgetState();
}

class _LinkPreviewWidgetState extends State<LinkPreviewWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  Metadata? _metadata;
  bool _isLoading = true;
  bool _hasFailed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _fetchMetadata();
  }

  Future<void> _fetchMetadata() async {
    try {
      final metadata = await AnyLinkPreview.getMetadata(
        link: widget.url,
        cache: const Duration(days: 7),
      );
      if (mounted) {
        setState(() {
          _metadata = metadata;
          _isLoading = false;
          _hasFailed = metadata == null;
        });
        if (!_hasFailed) _animController.forward();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// ✅ FIX: Dùng launchUrl với fallback, không kiểm tra canLaunchUrl trước
  Future<void> _launch() async {
    HapticFeedback.lightImpact();
    try {
      final uri = Uri.parse(widget.url);
      // Thử mở bằng browser ngoài trước
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      // Fallback: nếu không mở được, thử in-app webview
      if (!launched) {
        await launchUrl(
          uri,
          mode: LaunchMode.inAppWebView,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Cannot launch URL: ${widget.url} — $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở liên kết: ${widget.url}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _copyLink() {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: widget.url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link đã được sao chép'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String get _domain {
    try {
      return Uri.parse(widget.url).host.replaceAll('www.', '');
    } catch (_) {
      return widget.url;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    if (_hasFailed) return _buildFallback();

    final meta = _metadata!;
    final hasImage = meta.image != null && (meta.image?.isNotEmpty ?? false);
    final title = meta.title?.isNotEmpty == true ? meta.title! : _domain;
    final desc = meta.desc;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: GestureDetector(
          onTap: _launch, // ✅ Tap mở link
          onLongPress: _copyLink, // ✅ Long press sao chép
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: widget.isMe
                  ? Colors.white.withOpacity(0.15)
                  : const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isMe
                    ? Colors.white.withOpacity(0.25)
                    : const Color(0xFFDDE3F5),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasImage) _buildImage(meta.image!),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DomainPill(domain: _domain, isMe: widget.isMe),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.isMe
                              ? Colors.white
                              : const Color(0xFF111827),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      if (desc != null && desc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.isMe
                                ? Colors.white70
                                : const Color(0xFF6B7280),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // ✅ "Mở liên kết" row cũng tappable
                      Row(
                        children: [
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 12,
                            color: widget.isMe
                                ? Colors.white60
                                : const Color(0xFF6366F1),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Mở liên kết',
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.isMe
                                  ? Colors.white60
                                  : const Color(0xFF6366F1),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String imageUrl) {
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFFE5E7EB),
              child: const Icon(Icons.image_not_supported_outlined,
                  color: Color(0xFF9CA3AF), size: 32),
            ),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                color: const Color(0xFFE5E7EB),
                child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              );
            },
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: _Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 100, color: Colors.white),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: 10,
                      width: 80,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5))),
                  const SizedBox(height: 8),
                  Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5))),
                  const SizedBox(height: 4),
                  Container(
                      height: 12,
                      width: 160,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(5))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ Fallback cũng tap được
  Widget _buildFallback() {
    return GestureDetector(
      onTap: _launch,
      onLongPress: _copyLink,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withOpacity(0.12)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isMe
                ? Colors.white.withOpacity(0.2)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_rounded,
                size: 16,
                color: widget.isMe ? Colors.white70 : const Color(0xFF6366F1)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                // ✅ Hiển thị URL đầy đủ thay vì chỉ domain
                widget.url.length > 40
                    ? '${widget.url.substring(0, 40)}…'
                    : widget.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isMe ? Colors.white70 : const Color(0xFF6366F1),
                  decoration: TextDecoration.underline,
                  decorationColor:
                      widget.isMe ? Colors.white70 : const Color(0xFF6366F1),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.open_in_new_rounded,
              size: 12,
              color: widget.isMe ? Colors.white60 : const Color(0xFF6366F1),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Domain pill
// ─────────────────────────────────────────────────────────────────────────────

class _DomainPill extends StatelessWidget {
  final String domain;
  final bool isMe;

  const _DomainPill({required this.domain, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: isMe
                ? Colors.white.withOpacity(0.2)
                : const Color(0xFF6366F1).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.language_rounded,
            size: 9,
            color: isMe ? Colors.white70 : const Color(0xFF6366F1),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            domain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isMe ? Colors.white60 : const Color(0xFF6366F1),
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer loader
// ─────────────────────────────────────────────────────────────────────────────

class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
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
      builder: (_, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1 + _anim.value * 3, 0),
              end: Alignment(0 + _anim.value * 3, 0),
              colors: const [
                Color(0xFFE5E7EB),
                Color(0xFFF9FAFB),
                Color(0xFFE5E7EB),
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

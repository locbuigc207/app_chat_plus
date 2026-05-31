// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:any_link_preview/any_link_preview.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// URL DETECTION UTILITIES
// ─────────────────────────────────────────────────────────────────────────────

class UrlDetector {
  static final _urlRegex = RegExp(
    r'(https?://[^\s<>"]+|www\.[^\s<>"]+\.[^\s<>"]{2,})',
    caseSensitive: false,
  );

  static List<String> extractUrls(String text) {
    return _urlRegex
        .allMatches(text)
        .map((m) {
      var url = m.group(0)!;
      if (!url.startsWith('http')) url = 'https://$url';
      return url;
    })
        .toSet()
        .toList();
  }

  static bool containsUrl(String text) => _urlRegex.hasMatch(text);

  static String? firstUrl(String text) {
    final urls = extractUrls(text);
    return urls.isEmpty ? null : urls.first;
  }

  /// Split text into [TextSpan] segments with URLs highlighted
  static List<InlineSpan> buildRichText({
    required String text,
    required TextStyle normalStyle,
    required TextStyle linkStyle,
    required void Function(String url) onTapUrl,
  }) {
    final spans = <InlineSpan>[];
    int last = 0;
    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start), style: normalStyle));
      }
      var url = match.group(0)!;
      if (!url.startsWith('http')) url = 'https://$url';
      final captured = url;
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () => onTapUrl(captured),
          child: Text(
            match.group(0)!,
            style: linkStyle,
          ),
        ),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: normalStyle));
    }
    return spans;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// METADATA CACHE (singleton, in-memory + hive-optional)
// ─────────────────────────────────────────────────────────────────────────────

class _MetaEntry {
  final Metadata? meta;
  final DateTime fetchedAt;
  _MetaEntry(this.meta) : fetchedAt = DateTime.now();
  bool get isStale => DateTime.now().difference(fetchedAt) > const Duration(hours: 12);
}

class LinkMetaCache {
  LinkMetaCache._();
  static final LinkMetaCache _instance = LinkMetaCache._();
  factory LinkMetaCache() => _instance;

  final Map<String, _MetaEntry> _cache = {};

  Future<Metadata?> get(String url) async {
    final entry = _cache[url];
    if (entry != null && !entry.isStale) return entry.meta;
    try {
      final meta = await AnyLinkPreview.getMetadata(
        link: url,
        cache: const Duration(days: 7),
        proxyUrl: 'https://api.allorigins.win/get?url=',
      ).timeout(const Duration(seconds: 8));
      _cache[url] = _MetaEntry(meta);
      return meta;
    } catch (_) {
      _cache[url] = _MetaEntry(null);
      return null;
    }
  }

  void prefetch(List<String> urls) {
    for (final url in urls) {
      if (!_cache.containsKey(url)) get(url);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LINK TYPE DETECTION
// ─────────────────────────────────────────────────────────────────────────────

enum LinkKind { youtube, image, video, twitter, github, spotify, generic }

class LinkTypeDetector {
  static LinkKind detect(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com/watch') || lower.contains('youtu.be/')) {
      return LinkKind.youtube;
    }
    if (lower.contains('twitter.com') || lower.contains('x.com')) {
      return LinkKind.twitter;
    }
    if (lower.contains('github.com')) return LinkKind.github;
    if (lower.contains('open.spotify.com')) return LinkKind.spotify;
    if (RegExp(r'\.(jpg|jpeg|png|gif|webp|svg)(\?.*)?$').hasMatch(lower)) {
      return LinkKind.image;
    }
    if (RegExp(r'\.(mp4|webm|mov|mkv)(\?.*)?$').hasMatch(lower)) {
      return LinkKind.video;
    }
    return LinkKind.generic;
  }

  static IconData iconFor(LinkKind kind) {
    switch (kind) {
      case LinkKind.youtube:
        return Icons.play_circle_filled_rounded;
      case LinkKind.twitter:
        return Icons.alternate_email_rounded;
      case LinkKind.github:
        return Icons.code_rounded;
      case LinkKind.spotify:
        return Icons.music_note_rounded;
      case LinkKind.image:
        return Icons.image_rounded;
      case LinkKind.video:
        return Icons.videocam_rounded;
      case LinkKind.generic:
        return Icons.language_rounded;
    }
  }

  static Color colorFor(LinkKind kind) {
    switch (kind) {
      case LinkKind.youtube:
        return const Color(0xFFFF0000);
      case LinkKind.twitter:
        return const Color(0xFF1DA1F2);
      case LinkKind.github:
        return const Color(0xFF24292E);
      case LinkKind.spotify:
        return const Color(0xFF1DB954);
      case LinkKind.image:
        return const Color(0xFF8B5CF6);
      case LinkKind.video:
        return const Color(0xFFEF4444);
      case LinkKind.generic:
        return const Color(0xFF6366F1);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YOUTUBE THUMBNAIL HELPER
// ─────────────────────────────────────────────────────────────────────────────

class YoutubeHelper {
  static String? extractId(String url) {
    final patterns = [
      RegExp(r'youtube\.com/watch\?v=([^&]+)'),
      RegExp(r'youtu\.be/([^?]+)'),
      RegExp(r'youtube\.com/embed/([^?]+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static String? thumbnailUrl(String url) {
    final id = extractId(url);
    if (id == null) return null;
    return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }

  static String watchUrl(String videoId) => 'https://www.youtube.com/watch?v=$videoId';
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN LINK PREVIEW WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class LinkPreviewWidget extends StatefulWidget {
  final String url;
  final bool isMe;
  final Color? primaryColor;
  final bool compact;

  const LinkPreviewWidget({
    super.key,
    required this.url,
    this.isMe = false,
    this.primaryColor,
    this.compact = false,
  });

  @override
  State<LinkPreviewWidget> createState() => _LinkPreviewWidgetState();
}

class _LinkPreviewWidgetState extends State<LinkPreviewWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  Metadata? _meta;
  bool _loading = true;
  bool _failed = false;
  late final LinkKind _kind;

  @override
  void initState() {
    super.initState();
    _kind = LinkTypeDetector.detect(widget.url);
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, .1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _fetch();
  }

  Future<void> _fetch() async {
    final meta = await LinkMetaCache().get(widget.url);
    if (!mounted) return;
    setState(() {
      _meta = meta;
      _loading = false;
      _failed = meta == null;
    });
    if (!_failed) _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(widget.url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở: ${widget.url}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _copy() {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: widget.url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 Đã sao chép link'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _share() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: widget.url));
  }

  String get _domain {
    try {
      return Uri.parse(widget.url).host.replaceAll('www.', '');
    } catch (_) {
      return widget.url;
    }
  }

  Color get _accent =>
      widget.primaryColor ?? LinkTypeDetector.colorFor(_kind);

  bool get _isDark => widget.isMe;

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildSkeleton();
    if (_failed) return _buildFallback();

    if (_kind == LinkKind.youtube) return _buildYoutube();
    if (_kind == LinkKind.image) return _buildImageDirect();

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.compact ? _buildCompact() : _buildFull(),
      ),
    );
  }

  // ── Full card ──────────────────────────────────────────────────────────────
  Widget _buildFull() {
    final meta = _meta!;
    final hasImage = (meta.image?.isNotEmpty ?? false);
    final title = (meta.title?.isNotEmpty ?? false) ? meta.title! : _domain;
    final desc = meta.desc;

    return GestureDetector(
      onTap: _open,
      onLongPress: _showContextMenu,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: _cardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── hero image
            if (hasImage)
              _HeroImage(url: meta.image!, height: widget.compact ? 110 : 170),
            // ── content
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DomainRow(
                    domain: _domain,
                    kind: _kind,
                    accent: _accent,
                    isDark: _isDark,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (desc != null && desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _isDark ? Colors.white60 : const Color(0xFF64748B),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _OpenRow(isDark: _isDark, accent: _accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Compact card (no image) ────────────────────────────────────────────────
  Widget _buildCompact() {
    final meta = _meta!;
    final title = (meta.title?.isNotEmpty ?? false) ? meta.title! : _domain;

    return GestureDetector(
      onTap: _open,
      onLongPress: _showContextMenu,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: _cardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(
              width: 4,
              height: 52,
              color: _accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DomainRow(domain: _domain, kind: _kind, accent: _accent, isDark: _isDark),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: _isDark ? Colors.white38 : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── YouTube special card ───────────────────────────────────────────────────
  Widget _buildYoutube() {
    final thumb = YoutubeHelper.thumbnailUrl(widget.url);
    final meta = _meta;
    final title = meta?.title ?? 'YouTube Video';

    return FadeTransition(
      opacity: _fade,
      child: GestureDetector(
        onTap: _open,
        onLongPress: _showContextMenu,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: _cardDecoration(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // thumbnail
              if (thumb != null)
                Stack(
                  alignment: Alignment.center,
                  children: [
                    _HeroImage(url: thumb, height: 170),
                    // Play button overlay
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .35),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DomainRow(
                      domain: 'youtube.com',
                      kind: LinkKind.youtube,
                      accent: const Color(0xFFFF0000),
                      isDark: _isDark,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _OpenRow(isDark: _isDark, accent: const Color(0xFFFF0000)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Direct image link ──────────────────────────────────────────────────────
  Widget _buildImageDirect() {
    return FadeTransition(
      opacity: _fade,
      child: GestureDetector(
        onTap: _open,
        onLongPress: _showContextMenu,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: _cardDecoration(),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 200,
            placeholder: (_, __) => Container(
              height: 200,
              color: _isDark ? Colors.white10 : const Color(0xFFF1F5F9),
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (_, __, ___) => _buildFallback(),
          ),
        ),
      ),
    );
  }

  // ── Skeleton loading ───────────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: _ShimmerBlock(
        isDark: _isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              color: _isDark ? Colors.white.withValues(alpha: .08) : const Color(0xFFE2E8F0),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonLine(width: 90, height: 10, isDark: _isDark),
                  const SizedBox(height: 8),
                  _SkeletonLine(width: double.infinity, height: 14, isDark: _isDark),
                  const SizedBox(height: 4),
                  _SkeletonLine(width: 180, height: 12, isDark: _isDark),
                  const SizedBox(height: 8),
                  _SkeletonLine(width: 80, height: 10, isDark: _isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Fallback (no metadata) ─────────────────────────────────────────────────
  Widget _buildFallback() {
    return GestureDetector(
      onTap: _open,
      onLongPress: _showContextMenu,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                LinkTypeDetector.iconFor(_kind),
                color: _accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _domain,
                    style: TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.url.length > 50
                        ? '${widget.url.substring(0, 50)}…'
                        : widget.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _isDark ? Colors.white60 : const Color(0xFF64748B),
                      fontSize: 11.5,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new_rounded,
              size: 14,
              color: _isDark ? Colors.white38 : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  // ── Context menu ───────────────────────────────────────────────────────────
  void _showContextMenu() {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LinkContextMenu(
        url: widget.url,
        onOpen: _open,
        onCopy: _copy,
      ),
    );
  }

  // ── Decoration helpers ─────────────────────────────────────────────────────
  BoxDecoration _cardDecoration() {
    if (_isDark) {
      return BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .18), width: .8),
      );
    }
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0), width: .8),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .06),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INLINE RICH-TEXT MESSAGE with auto link preview
// ─────────────────────────────────────────────────────────────────────────────

/// Drop-in replacement for [Text] inside a bubble that detects links,
/// renders them clickable, and shows a preview card below the text.
class ChatMessageWithLinkPreview extends StatelessWidget {
  final String content;
  final bool isMe;
  final Color textColor;
  final double fontSize;
  final Color? primaryColor;
  final bool showPreview;

  const ChatMessageWithLinkPreview({
    super.key,
    required this.content,
    required this.isMe,
    required this.textColor,
    this.fontSize = 15,
    this.primaryColor,
    this.showPreview = true,
  });

  @override
  Widget build(BuildContext context) {
    final urls = UrlDetector.extractUrls(content);
    final hasUrl = urls.isNotEmpty;
    final firstUrl = hasUrl ? urls.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // rich text with tappable links
        if (hasUrl)
          RichText(
            text: TextSpan(
              children: UrlDetector.buildRichText(
                text: content,
                normalStyle: TextStyle(
                  color: textColor,
                  fontSize: fontSize,
                  height: 1.45,
                ),
                linkStyle: TextStyle(
                  color: isMe
                      ? Colors.white
                      : (primaryColor ?? const Color(0xFF6366F1)),
                  fontSize: fontSize,
                  height: 1.45,
                  decoration: TextDecoration.underline,
                  decorationColor: isMe
                      ? Colors.white70
                      : (primaryColor ?? const Color(0xFF6366F1)),
                  fontWeight: FontWeight.w600,
                ),
                onTapUrl: (url) async {
                  HapticFeedback.lightImpact();
                  final uri = Uri.parse(url);
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (_) {
                    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
                  }
                },
              ),
            ),
          )
        else
          Text(
            content,
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              height: 1.45,
            ),
          ),

        // preview card
        if (showPreview && firstUrl != null)
          LinkPreviewWidget(
            key: ValueKey(firstUrl),
            url: firstUrl,
            isMe: isMe,
            primaryColor: primaryColor,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _HeroImage extends StatelessWidget {
  final String url;
  final double height;
  const _HeroImage({required this.url, required this.height});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: const Color(0xFFE2E8F0),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF94A3B8)),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFFE2E8F0),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined,
              color: Color(0xFF94A3B8), size: 32),
        ),
      ),
    ),
  );
}

class _DomainRow extends StatelessWidget {
  final String domain;
  final LinkKind kind;
  final Color accent;
  final bool isDark;
  const _DomainRow({
    required this.domain,
    required this.kind,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(LinkTypeDetector.iconFor(kind), size: 11, color: accent),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          domain,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark ? accent.withValues(alpha: .9) : accent,
            letterSpacing: .25,
          ),
        ),
      ),
    ],
  );
}

class _OpenRow extends StatelessWidget {
  final bool isDark;
  final Color accent;
  const _OpenRow({required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        Icons.open_in_new_rounded,
        size: 12,
        color: isDark ? accent.withValues(alpha: .75) : accent,
      ),
      const SizedBox(width: 4),
      Text(
        'Mở liên kết',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isDark ? accent.withValues(alpha: .75) : accent,
        ),
      ),
    ],
  );
}

class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final bool isDark;
  const _SkeletonLine(
      {required this.width, required this.height, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: .1)
          : const Color(0xFFE2E8F0),
      borderRadius: BorderRadius.circular(5),
    ),
  );
}

class _ShimmerBlock extends StatefulWidget {
  final Widget child;
  final bool isDark;
  const _ShimmerBlock({required this.child, required this.isDark});

  @override
  State<_ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<_ShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, child) => ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        final t = _ctrl.value;
        return LinearGradient(
          begin: Alignment(-1.5 + t * 3, 0),
          end: Alignment(0 + t * 3, 0),
          colors: widget.isDark
              ? [
            Colors.white.withValues(alpha: .05),
            Colors.white.withValues(alpha: .15),
            Colors.white.withValues(alpha: .05),
          ]
              : [
            const Color(0xFFE2E8F0),
            const Color(0xFFF8FAFC),
            const Color(0xFFE2E8F0),
          ],
        ).createShader(bounds);
      },
      child: child,
    ),
    child: widget.child,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTEXT MENU BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _LinkContextMenu extends StatelessWidget {
  final String url;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  const _LinkContextMenu({
    required this.url,
    required this.onOpen,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final domain = Uri.tryParse(url)?.host.replaceAll('www.', '') ?? url;
    return Container(
      padding: const EdgeInsets.only(bottom: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.link_rounded, color: Color(0xFF6366F1), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(domain,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(
                        url.length > 55 ? '${url.substring(0, 55)}…' : url,
                        style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          _ContextAction(
            icon: Icons.open_in_new_rounded,
            label: 'Mở trong trình duyệt',
            color: const Color(0xFF6366F1),
            onTap: () {
              Navigator.pop(context);
              onOpen();
            },
          ),
          _ContextAction(
            icon: Icons.copy_rounded,
            label: 'Sao chép liên kết',
            color: const Color(0xFF22D3EE),
            onTap: () {
              Navigator.pop(context);
              onCopy();
            },
          ),
        ],
      ),
    );
  }
}

class _ContextAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ContextAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 18),
    ),
    title: Text(label,
        style: const TextStyle(
            color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PREFETCH HOOK — call from chat page when messages load
// ─────────────────────────────────────────────────────────────────────────────

void prefetchLinkPreviews(List<Map<dynamic, dynamic>> messages) {
  final urls = <String>[];
  for (final m in messages) {
    final content = m['content'] as String? ?? '';
    final type = m['type'] as int? ?? 0;
    if (type == 0 && UrlDetector.containsUrl(content)) {
      final url = UrlDetector.firstUrl(content);
      if (url != null) urls.add(url);
    }
  }
  if (urls.isNotEmpty) LinkMetaCache().prefetch(urls);
}
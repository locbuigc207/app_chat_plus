// lib/widgets/bubble_link_preview.dart
//
// Detects URLs in message text → fetches OpenGraph / meta tags →
// renders a rich preview card below the message.
//
// Features
// ─────────
// • Regex-based URL detection (http/https/www)
// • Lightweight HTML meta-tag scraper (no heavy dependency)
// • 24-hour in-memory + SharedPreferences disk cache
// • Loading shimmer → rich card → error fallback
// • Tap opens URL via url_launcher
// • Respects BubbleMode colour theming

import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ═══════════════════════════════════════════════════════════════════════════
// METADATA MODEL
// ═══════════════════════════════════════════════════════════════════════════

class LinkMetadata {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? faviconUrl;
  final DateTime fetchedAt;

  const LinkMetadata({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
    required this.fetchedAt,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasTitle => title != null && title!.isNotEmpty;
  bool get hasDescription => description != null && description!.isNotEmpty;
  bool get isStale => DateTime.now().difference(fetchedAt).inHours >= 24;

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'siteName': siteName,
        'faviconUrl': faviconUrl,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      };

  factory LinkMetadata.fromJson(Map<String, dynamic> j) => LinkMetadata(
        url: j['url'] as String,
        title: j['title'] as String?,
        description: j['description'] as String?,
        imageUrl: j['imageUrl'] as String?,
        siteName: j['siteName'] as String?,
        faviconUrl: j['faviconUrl'] as String?,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(j['fetchedAt'] as int),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// METADATA SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class LinkMetadataService {
  static final LinkMetadataService _i = LinkMetadataService._();
  factory LinkMetadataService() => _i;
  LinkMetadataService._();

  // L1: in-memory
  final _cache = <String, LinkMetadata>{};
  // Inflight deduplication
  final _inflight = <String, Future<LinkMetadata?>>{};

  static const _prefsKey = 'link_preview_cache';
  static final _urlRe = RegExp(r'https?://[^\s\)\]\>"]+|www\.[^\s\)\]\>"]+',
      caseSensitive: false);

  /// Extract first URL from [text], null if none.
  static String? firstUrl(String text) {
    final m = _urlRe.firstMatch(text);
    if (m == null) return null;
    var url = m.group(0)!;
    if (!url.startsWith('http')) url = 'https://$url';
    return url;
  }

  /// Fetch metadata for [url], using cache if available.
  Future<LinkMetadata?> fetch(String url) async {
    // L1
    final cached = _cache[url];
    if (cached != null && !cached.isStale) return cached;

    // Deduplicate concurrent fetches
    if (_inflight.containsKey(url)) return _inflight[url];

    final future = _fetchRemote(url);
    _inflight[url] = future;
    try {
      final result = await future;
      _inflight.remove(url);
      if (result != null) {
        _cache[url] = result;
        _persistCache();
      }
      return result;
    } catch (_) {
      _inflight.remove(url);
      return null;
    }
  }

  Future<LinkMetadata?> _fetchRemote(String url) async {
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; ChatBubbleBot/1.0; +https://example.com)',
          'Accept': 'text/html',
        },
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;
      final html = resp.body;

      final meta = LinkMetadata(
        url: url,
        title: _og(html, 'title') ?? _tag(html, 'title'),
        description: _og(html, 'description') ?? _meta(html, 'description'),
        imageUrl: _og(html, 'image'),
        siteName: _og(html, 'site_name') ?? Uri.parse(url).host,
        faviconUrl: _favicon(url, html),
        fetchedAt: DateTime.now(),
      );
      return meta;
    } catch (_) {
      return null;
    }
  }

  // ─── HTML parsers (regex-based, no DOM dependency) ───────────────────────

  static String? _og(String html, String prop) {
    final re = RegExp(
        '<meta[^>]+property=["\']og:$prop["\'][^>]+content=["\']([^"\']+)["\']',
        caseSensitive: false);
    final m = re.firstMatch(html);
    if (m != null) return _decode(m.group(1)!);
    // Try reversed attribute order
    final re2 = RegExp(
        '<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:$prop["\']',
        caseSensitive: false);
    return re2.firstMatch(html)?.group(1)?.let(_decode);
  }

  static String? _meta(String html, String name) {
    final re = RegExp(
        '<meta[^>]+name=["\']$name["\'][^>]+content=["\']([^"\']+)["\']',
        caseSensitive: false);
    return re.firstMatch(html)?.group(1)?.let(_decode);
  }

  static String? _tag(String html, String tag) {
    final re = RegExp('<$tag[^>]*>([^<]+)</$tag>', caseSensitive: false);
    return re.firstMatch(html)?.group(1)?.trim().let(_decode);
  }

  static String _favicon(String pageUrl, String html) {
    final base = Uri.parse(pageUrl);
    final re = RegExp(
        '<link[^>]+rel=["\'][^"\']*icon[^"\']*["\'][^>]+href=["\']([^"\']+)["\']',
        caseSensitive: false);
    final m = re.firstMatch(html);
    if (m != null) {
      final href = m.group(1)!;
      if (href.startsWith('http')) return href;
      return base.resolve(href).toString();
    }
    return '${base.scheme}://${base.host}/favicon.ico';
  }

  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();

  // ─── Disk cache ───────────────────────────────────────────────────────────

  Future<void> _persistCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final map = _cache.map((k, v) => MapEntry(k, v.toJson()));
      await p.setString(_prefsKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<void> loadFromDisk() async {
    try {
      final p = await SharedPreferences.getInstance();
      final json = p.getString(_prefsKey);
      if (json == null) return;
      final map = jsonDecode(json) as Map<String, dynamic>;
      for (final e in map.entries) {
        final meta =
            LinkMetadata.fromJson(Map<String, dynamic>.from(e.value as Map));
        if (!meta.isStale) _cache[e.key] = meta;
      }
    } catch (_) {}
  }
}

extension _Ext<T> on T {
  R let<R>(R Function(T) block) => block(this);
}

// ═══════════════════════════════════════════════════════════════════════════
// LINK PREVIEW WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Automatically detects a URL in [messageText] and renders a preview card.
/// Returns [SizedBox.shrink] if no URL found.
class LinkPreviewCard extends StatefulWidget {
  final String messageText;
  final bool isMe;
  final Color? accentColor;
  final double borderRadius;

  const LinkPreviewCard({
    super.key,
    required this.messageText,
    this.isMe = false,
    this.accentColor,
    this.borderRadius = 12,
  });

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  LinkMetadata? _meta;
  bool _loading = false;
  String? _url;

  @override
  void initState() {
    super.initState();
    _url = LinkMetadataService.firstUrl(widget.messageText);
    if (_url != null) _load();
  }

  @override
  void didUpdateWidget(LinkPreviewCard old) {
    super.didUpdateWidget(old);
    final newUrl = LinkMetadataService.firstUrl(widget.messageText);
    if (newUrl != _url) {
      _url = newUrl;
      if (_url != null) _load();
    }
  }

  Future<void> _load() async {
    if (_url == null) return;
    setState(() => _loading = true);
    final meta = await LinkMetadataService().fetch(_url!);
    if (mounted)
      setState(() {
        _meta = meta;
        _loading = false;
      });
  }

  Future<void> _open() async {
    final u = Uri.tryParse(_url ?? '');
    if (u == null) return;
    HapticFeedback.lightImpact();
    if (await canLaunchUrl(u)) await launchUrl(u);
  }

  @override
  Widget build(BuildContext context) {
    if (_url == null) return const SizedBox.shrink();
    if (_loading) return _Shimmer(isMe: widget.isMe);
    if (_meta == null) return const SizedBox.shrink();

    final accent = widget.accentColor ??
        (widget.isMe
            ? Colors.white.withOpacity(0.85)
            : const Color(0xFF2979FF));

    return GestureDetector(
      onTap: _open,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withOpacity(0.12)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: accent.withOpacity(0.25), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Preview image ─────────────────────────────────────────
            if (_meta!.hasImage)
              CachedNetworkImage(
                imageUrl: _meta!.imageUrl!,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
                placeholder: (_, __) =>
                    Container(height: 150, color: Colors.grey.shade200),
              ),

            // ── Text content ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Site name + favicon
                  Row(
                    children: [
                      if (_meta!.faviconUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: CachedNetworkImage(
                            imageUrl: _meta!.faviconUrl!,
                            width: 14,
                            height: 14,
                            errorWidget: (_, __, ___) => Icon(
                                Icons.language_rounded,
                                size: 14,
                                color: accent),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          _meta!.siteName ?? Uri.parse(_url!).host,
                          style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Title
                  if (_meta!.hasTitle)
                    Text(
                      _meta!.title!,
                      style: TextStyle(
                          color: widget.isMe ? Colors.white : Colors.black87,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                  // Description
                  if (_meta!.hasDescription) ...[
                    const SizedBox(height: 3),
                    Text(
                      _meta!.description!,
                      style: TextStyle(
                          color: widget.isMe
                              ? Colors.white.withOpacity(0.7)
                              : Colors.black54,
                          fontSize: 12,
                          height: 1.4),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // ── Open link bar ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: accent.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  Icon(Icons.open_in_new_rounded,
                      size: 12, color: accent.withOpacity(0.8)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _url!.length > 50 ? '${_url!.substring(0, 50)}…' : _url!,
                      style: TextStyle(
                          color: accent.withOpacity(0.7), fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shimmer placeholder ──────────────────────────────────────────────────────

class _Shimmer extends StatefulWidget {
  final bool isMe;
  const _Shimmer({required this.isMe});

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
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.9)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor =
        widget.isMe ? Colors.white.withOpacity(0.15) : Colors.grey.shade200;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(top: 6),
        height: 80,
        decoration: BoxDecoration(
          color: Color.lerp(
              baseColor,
              baseColor.withOpacity(baseColor.opacity * _anim.value),
              _anim.value),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bar(width: 80, height: 10, color: baseColor),
              const SizedBox(height: 6),
              _Bar(width: 200, height: 12, color: baseColor),
              const SizedBox(height: 5),
              _Bar(width: 160, height: 10, color: baseColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double width, height;
  final Color color;
  const _Bar({required this.width, required this.height, required this.color});

  @override
  Widget build(BuildContext context) => Container(
      width: width,
      height: height,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)));
}

// ═══════════════════════════════════════════════════════════════════════════
// RICH TEXT WITH TAPPABLE URLS
// ═══════════════════════════════════════════════════════════════════════════

/// Renders [text] with URLs highlighted and tappable.
/// If a URL is detected, also renders a [LinkPreviewCard] below.
class BubbleRichText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool isMe;
  final Color? accentColor;
  final bool showPreview;

  const BubbleRichText({
    super.key,
    required this.text,
    required this.style,
    this.isMe = false,
    this.accentColor,
    this.showPreview = true,
  });

  static final _re = RegExp(r'https?://[^\s\)\]\>"]+|www\.[^\s\)\]\>"]+',
      caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    int last = 0;
    final accent =
        accentColor ?? (isMe ? Colors.white : const Color(0xFF2979FF));

    for (final m in _re.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: style));
      }
      final url = m.group(0)!;
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            var u = url;
            if (!u.startsWith('http')) u = 'https://$u';
            final uri = Uri.tryParse(u);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          },
          child: Text(url,
              style: style.copyWith(
                  color: accent,
                  decoration: TextDecoration.underline,
                  decorationColor: accent)),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(text: TextSpan(children: spans)),
        if (showPreview)
          LinkPreviewCard(
              messageText: text, isMe: isMe, accentColor: accentColor),
      ],
    );
  }
}

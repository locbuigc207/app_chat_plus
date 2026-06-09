import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';

class GroupMediaPage extends StatefulWidget {
  const GroupMediaPage({
    super.key,
    required this.groupId,
    required this.groupName
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupMediaPage> createState() => _GroupMediaPageState();
}

class _GroupMediaPageState extends State<GroupMediaPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DocumentSnapshot> _allMessages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadAllMessages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllMessages() async {
    setState(() => _isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(widget.groupId)
          .collection(widget.groupId)
          .where('isDeleted', isEqualTo: false)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(300)
          .get();

      if (mounted) {
        setState(() {
          _allMessages = snap.docs;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<DocumentSnapshot> get _images => _allMessages.where((d) {
    final data = d.data() as Map<String, dynamic>?;
    return data?['type'] == TypeMessage.image;
  }).toList();

  List<DocumentSnapshot> get _voiceMessages => _allMessages.where((d) {
    final data = d.data() as Map<String, dynamic>?;
    return data?['type'] == 3; // TypeMessage.audio/voice
  }).toList();

  List<DocumentSnapshot> get _links => _allMessages.where((d) {
    final data = d.data() as Map<String, dynamic>?;
    if (data?['type'] != TypeMessage.text) return false;
    final content = data?['content'] as String? ?? '';
    return content.contains('http') ||
        content.contains('maps.google.com');
  }).toList();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: NestedScrollView(
          headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
            _buildSliverAppBar(p, theme, innerBoxIsScrolled),
          ],
          body: _isLoading
              ? Center(
              child: CircularProgressIndicator(
                  color: theme.primaryColor,
                  strokeWidth: 2.5
              )
          )
              : TabBarView(
            controller: _tabController,
            children: [
              _buildImagesTab(p, theme),
              _buildVoiceTab(p, theme),
              _buildLinksTab(p, theme),
            ],
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar(ThemePalette p, ThemeProvider theme, bool innerBoxIsScrolled) {
    final tabs = [
      _TabInfo(icon: Icons.image_rounded, label: 'Ảnh', count: _images.length),
      _TabInfo(icon: Icons.mic_rounded, label: 'Voice', count: _voiceMessages.length),
      _TabInfo(icon: Icons.link_rounded, label: 'Liên kết', count: _links.length),
    ];

    return SliverAppBar(
      pinned: true,
      floating: true,
      forceElevated: innerBoxIsScrolled,
      backgroundColor: p.appBarBackground,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: theme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Media & Files',
              style: TextStyle(color: p.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)
          ),
          Text(
              widget.groupName,
              style: TextStyle(color: p.textSecondary, fontSize: 12)
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.refresh_rounded, color: p.textSecondary),
          onPressed: () {
            setState(() => _isLoading = true);
            _loadAllMessages();
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Container(
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.divider, width: 0.8))
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: theme.primaryColor,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: theme.primaryColor,
            unselectedLabelColor: p.textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            tabs: tabs.map((t) => Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(t.icon, size: 16),
                  const SizedBox(width: 6),
                  Text(t.label),
                  if (t.count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                          '${t.count}',
                          style: TextStyle(
                              color: theme.primaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700
                          )
                      ),
                    ),
                  ],
                ],
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildImagesTab(ThemePalette p, ThemeProvider theme) {
    if (_images.isEmpty) {
      return _EmptyState(
        icon: Icons.image_not_supported_rounded,
        title: 'Chưa có ảnh',
        subtitle: 'Ảnh chia sẻ trong nhóm sẽ xuất hiện ở đây',
        palette: p,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(3),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2
      ),
      itemCount: _images.length,
      itemBuilder: (_, i) {
        final data = _images[i].data() as Map<String, dynamic>? ?? {};
        final url = data['content'] as String? ?? '';

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(context, MaterialPageRoute(builder: (_) => FullPhotoPage(url: url)));
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) => prog == null
                    ? child
                    : Container(
                    color: p.surfaceVariant,
                    child: Center(
                        child: CircularProgressIndicator(
                            value: prog.expectedTotalBytes != null
                                ? prog.cumulativeBytesLoaded / prog.expectedTotalBytes!
                                : null,
                            color: theme.primaryColor,
                            strokeWidth: 1.5
                        )
                    )
                ),
                errorBuilder: (_, __, ___) => Container(
                    color: p.surfaceVariant,
                    child: Icon(Icons.broken_image_rounded, color: p.textSecondary)
                ),
              ),
              Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4)
                    ),
                    child: Text(
                        _formatShortDate(data['timestamp'] as String? ?? '0'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w500
                        )
                    ),
                  )
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceTab(ThemePalette p, ThemeProvider theme) {
    if (_voiceMessages.isEmpty) {
      return _EmptyState(
        icon: Icons.mic_off_rounded,
        title: 'Chưa có voice',
        subtitle: 'Voice messages chia sẻ ở đây sẽ xuất hiện',
        palette: p,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _voiceMessages.length,
      itemBuilder: (_, i) {
        final data = _voiceMessages[i].data() as Map<String, dynamic>? ?? {};
        final ts = data['timestamp'] as String? ?? '0';
        final dt = _parseTimestamp(ts);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.divider, width: 0.6),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [theme.primaryColor, theme.primaryLightColor]
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
            ),
            title: Text(
                'Voice Message',
                style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14
                )
            ),
            subtitle: Text(
                _formatFullDate(dt),
                style: TextStyle(color: p.textSecondary, fontSize: 12)
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20)
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, color: theme.primaryColor, size: 18),
                  const SizedBox(width: 2),
                  Text(
                      'Play',
                      style: TextStyle(
                          color: theme.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600
                      )
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLinksTab(ThemePalette p, ThemeProvider theme) {
    if (_links.isEmpty) {
      return _EmptyState(
        icon: Icons.link_off_rounded,
        title: 'Chưa có liên kết',
        subtitle: 'URLs chia sẻ trong nhóm sẽ xuất hiện ở đây',
        palette: p,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _links.length,
      itemBuilder: (_, i) {
        final data = _links[i].data() as Map<String, dynamic>? ?? {};
        final content = data['content'] as String? ?? '';
        final ts = data['timestamp'] as String? ?? '0';
        final dt = _parseTimestamp(ts);

        final urlReg = RegExp(r'https?://[^\s]+');
        final match = urlReg.firstMatch(content);
        final url = match?.group(0) ?? content;
        final domain = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;

        return GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            try {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            } catch (_) {}
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.divider, width: 0.6),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.teal.shade400.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.shade400.withValues(alpha: 0.25)),
                    ),
                    child: Icon(Icons.public_rounded, color: Colors.teal.shade400, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            domain,
                            style: TextStyle(
                                color: Colors.teal.shade400,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5
                            )
                        ),
                        const SizedBox(height: 3),
                        Text(
                            url,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                                decorationColor: p.textSecondary
                            )
                        ),
                        const SizedBox(height: 4),
                        Text(
                            _formatFullDate(dt),
                            style: TextStyle(color: p.textSecondary, fontSize: 11)
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.open_in_new_rounded, color: p.textSecondary, size: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  DateTime _parseTimestamp(String ts) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
    } catch (_) {
      return DateTime.now();
    }
  }

  String _formatShortDate(String ts) {
    final dt = _parseTimestamp(ts);
    return '${dt.day}/${dt.month}';
  }

  String _formatFullDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}  •  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  final int count;

  const _TabInfo({
    required this.icon,
    required this.label,
    required this.count
  });
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ThemePalette palette;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
                color: palette.surfaceVariant,
                shape: BoxShape.circle
            ),
            child: Icon(icon, size: 40, color: palette.textSecondary),
          ),
          const SizedBox(height: 18),
          Text(
              title,
              style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600
              )
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13.5,
                    height: 1.5
                )
            ),
          ),
        ],
      ),
    );
  }
}
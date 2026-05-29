import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:url_launcher/url_launcher.dart';

class GroupMediaPage extends StatefulWidget {
  const GroupMediaPage({
    super.key,
    required this.groupId,
    required this.groupName,
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
  int _selectedImageIndex = -1;

  static const _bg = Color(0xFF0D0F14);
  static const _surface = Color(0xFF181B24);
  static const _accent = Color(0xFF4F8EF7);
  static const _textPrimary = Color(0xFFEEF2FF);
  static const _textSecondary = Color(0xFF8B93B0);
  static const _divider = Color(0xFF252A3A);

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
        return data?['type'] == 3;
      }).toList();

  List<DocumentSnapshot> get _links => _allMessages.where((d) {
        final data = d.data() as Map<String, dynamic>?;
        if (data?['type'] != TypeMessage.text) return false;
        final content = data?['content'] as String? ?? '';
        return content.contains('http') || content.contains('maps.google.com');
      }).toList();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _bg,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            _buildSliverAppBar(innerBoxIsScrolled),
          ],
          body: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildImagesTab(),
                    _buildVoiceTab(),
                    _buildLinksTab(),
                  ],
                ),
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar(bool innerBoxIsScrolled) {
    final tabs = [
      _TabInfo(icon: Icons.image_rounded, label: 'Photos', count: _images.length),
      _TabInfo(icon: Icons.mic_rounded, label: 'Voice', count: _voiceMessages.length),
      _TabInfo(icon: Icons.link_rounded, label: 'Links', count: _links.length),
    ];

    return SliverAppBar(
      pinned: true,
      floating: true,
      forceElevated: innerBoxIsScrolled,
      backgroundColor: _bg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Media & Files',
              style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          Text(widget.groupName, style: const TextStyle(color: _textSecondary, fontSize: 12)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: _textSecondary),
          onPressed: () {
            setState(() => _isLoading = true);
            _loadAllMessages();
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _divider, width: .8)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: _accent,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: _accent,
            unselectedLabelColor: _textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            tabs: tabs.map((t) {
              return Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon, size: 16),
                    const SizedBox(width: 6),
                    Text(t.label),
                    if (t.count > 0) ...[
                      const SizedBox(width: 6),
                      _CountBadge(count: t.count),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildImagesTab() {
    if (_images.isEmpty) {
      return _EmptyState(
        icon: Icons.image_not_supported_rounded,
        title: 'No photos yet',
        subtitle: 'Photos shared in the group will appear here',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: _images.length,
      itemBuilder: (_, i) {
        final data = _images[i].data() as Map<String, dynamic>? ?? {};
        final url = data['content'] as String? ?? '';
        final isSelected = _selectedImageIndex == i;

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FullPhotoPage(url: url)),
            );
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            setState(() => _selectedImageIndex = isSelected ? -1 : i);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              border: isSelected ? Border.all(color: _accent, width: 2.5) : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, prog) {
                    if (prog == null) return child;
                    return Container(
                      color: _surface,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: prog.expectedTotalBytes != null
                              ? prog.cumulativeBytesLoaded / prog.expectedTotalBytes!
                              : null,
                          color: _accent,
                          strokeWidth: 1.5,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: _surface,
                    child: const Icon(Icons.broken_image_rounded, color: _textSecondary),
                  ),
                ),
                if (isSelected)
                  Container(
                    color: _accent.withValues(alpha: .25),
                    alignment: Alignment.center,
                    child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
                  ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatShortDate(data['timestamp'] as String? ?? '0'),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceTab() {
    if (_voiceMessages.isEmpty) {
      return _EmptyState(
        icon: Icons.mic_off_rounded,
        title: 'No voice messages',
        subtitle: 'Voice messages shared here will appear',
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
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _divider, width: .8),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accent, Color(0xFF6B4AE8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
            ),
            title: const Text('Voice Message',
                style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600, fontSize: 14.5)),
            subtitle: Text(
              _formatFullDate(dt),
              style: const TextStyle(color: _textSecondary, fontSize: 12.5),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, color: _accent, size: 18),
                  SizedBox(width: 2),
                  Text('Play',
                      style: TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLinksTab() {
    if (_links.isEmpty) {
      return _EmptyState(
        icon: Icons.link_off_rounded,
        title: 'No links shared',
        subtitle: 'URLs and links shared in the group appear here',
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
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _divider, width: .8),
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
                      color: const Color(0xFF43C6AC).withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF43C6AC).withValues(alpha: .3), width: .8),
                    ),
                    child: const Icon(Icons.public_rounded, color: Color(0xFF43C6AC), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          domain,
                          style: const TextStyle(
                              color: Color(0xFF43C6AC),
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          url,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF8B93B0)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatFullDate(dt),
                          style: const TextStyle(color: _textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.open_in_new_rounded, color: _textSecondary, size: 16),
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
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}  •  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _TabInfo {
  const _TabInfo({required this.icon, required this.label, required this.count});
  final IconData icon;
  final String label;
  final int count;
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF4F8EF7).withValues(alpha: .2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(color: Color(0xFF4F8EF7), fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF181B24),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF252A3A), width: .8),
            ),
            child: Icon(icon, size: 44, color: const Color(0xFF8B93B0)),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: const TextStyle(
                  color: Color(0xFFEEF2FF), fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8B93B0), fontSize: 14, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

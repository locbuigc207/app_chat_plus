import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

enum MemoryCategory {
  memory, preference, promise, milestone, conflict, gratitude;

  static MemoryCategory fromString(String? s) => MemoryCategory.values
      .firstWhere((e) => e.name == s, orElse: () => MemoryCategory.memory);

  String get label => switch (this) {
    MemoryCategory.memory    => 'Kỷ niệm',
    MemoryCategory.preference => 'Sở thích',
    MemoryCategory.promise   => 'Lời hứa',
    MemoryCategory.milestone => 'Dấu mốc',
    MemoryCategory.conflict  => 'Mâu thuẫn',
    MemoryCategory.gratitude => 'Biết ơn',
  };

  IconData get icon => switch (this) {
    MemoryCategory.memory    => Icons.auto_awesome_rounded,
    MemoryCategory.preference => Icons.favorite_rounded,
    MemoryCategory.promise   => Icons.handshake_rounded,
    MemoryCategory.milestone => Icons.flag_rounded,
    MemoryCategory.conflict  => Icons.thunderstorm_rounded,
    MemoryCategory.gratitude => Icons.sentiment_very_satisfied_rounded,
  };

  Color get color => switch (this) {
    MemoryCategory.memory    => const Color(0xFF7C6EFF),
    MemoryCategory.preference => const Color(0xFFFF6E9C),
    MemoryCategory.promise   => const Color(0xFFFFB86E),
    MemoryCategory.milestone => const Color(0xFF6EFFCB),
    MemoryCategory.conflict  => const Color(0xFFFF6E6E),
    MemoryCategory.gratitude => const Color(0xFFFFE56E),
  };
}

enum RelationshipType {
  friend, family, colleague, romantic, unknown;

  static RelationshipType fromString(String? s) => RelationshipType.values
      .firstWhere((e) => e.name == s, orElse: () => RelationshipType.unknown);

  String get label => switch (this) {
    RelationshipType.friend   => 'Bạn bè',
    RelationshipType.family   => 'Gia đình',
    RelationshipType.colleague => 'Đồng nghiệp',
    RelationshipType.romantic  => 'Tình cảm',
    RelationshipType.unknown   => 'Chưa xác định',
  };

  IconData get icon => switch (this) {
    RelationshipType.friend   => Icons.people_rounded,
    RelationshipType.family   => Icons.family_restroom_rounded,
    RelationshipType.colleague => Icons.work_rounded,
    RelationshipType.romantic  => Icons.favorite_rounded,
    RelationshipType.unknown   => Icons.person_rounded,
  };
}

class _MemoryEntry {
  final MemoryCategory category;
  final String content;

  const _MemoryEntry({required this.category, required this.content});

  factory _MemoryEntry.fromMap(Map<dynamic, dynamic> map) => _MemoryEntry(
    category: MemoryCategory.fromString(map['category'] as String?),
    content: map['content'] as String? ?? '',
  );
}

class _RelationshipData {
  final int healthScore, closenessLevel;
  final String summary, communicationStyle;
  final RelationshipType relationshipType;
  final List<String> sharedTopics, importantDates;
  final List<_MemoryEntry> memories;

  const _RelationshipData({
    required this.healthScore, required this.summary,
    required this.relationshipType, required this.communicationStyle,
    required this.closenessLevel, required this.sharedTopics,
    required this.importantDates, required this.memories,
  });

  factory _RelationshipData.fromMap(Map<String, dynamic> map) => _RelationshipData(
    healthScore: (map['healthScore'] as num?)?.toInt() ?? 0,
    summary: map['summary'] as String? ?? '',
    relationshipType: RelationshipType.fromString(map['relationshipType'] as String?),
    communicationStyle: map['communicationStyle'] as String? ?? 'mixed',
    closenessLevel: (map['closenessLevel'] as num?)?.toInt() ?? 1,
    sharedTopics: (map['sharedTopics'] as List? ?? []).map((e) => e.toString()).toList(),
    importantDates: (map['importantDates'] as List? ?? []).map((e) => e.toString()).toList(),
    memories: (map['memories'] as List? ?? []).map((e) => _MemoryEntry.fromMap(e as Map)).toList(),
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class MemoryTimelinePage extends StatefulWidget {
  const MemoryTimelinePage({
    super.key,
    required this.peerId,
    required this.peerNickname,
    required this.currentUserId,
    required this.conversationId
  });

  final String peerId, peerNickname, currentUserId, conversationId;

  @override
  State<MemoryTimelinePage> createState() => _MemoryTimelinePageState();
}

class _MemoryTimelinePageState extends State<MemoryTimelinePage> with TickerProviderStateMixin {
  bool _isLoading = true, _isAnalyzing = false;
  _RelationshipData? _data;
  DateTime? _lastUpdated;
  String? _errorMessage;

  late final AnimationController _fadeAc;
  late final AnimationController _scoreAc;
  late final Animation<double> _scoreAnim;

  @override
  void initState() {
    super.initState();
    _fadeAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scoreAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _scoreAnim = CurvedAnimation(parent: _scoreAc, curve: Curves.easeOutCubic);
    _fetchCachedMemory();
  }

  @override
  void dispose() {
    _fadeAc.dispose();
    _scoreAc.dispose();
    super.dispose();
  }

  Future<void> _fetchCachedMemory() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('relationship_memories')
          .doc(widget.conversationId)
          .get();

      if (doc.exists && doc.data() != null) {
        final raw = doc.data()!;
        final dataMap = raw['data'] as Map<String, dynamic>?;
        if (dataMap != null) {
          _applyData(_RelationshipData.fromMap(dataMap));
          _lastUpdated = (raw['lastUpdated'] as Timestamp?)?.toDate();
        }
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyData(_RelationshipData data) {
    setState(() => _data = data);
    _fadeAc.forward(from: 0);
    _scoreAc.forward(from: 0);
  }

  Future<void> _analyzeMemory({bool forceRefresh = false}) async {
    if (!forceRefresh && _lastUpdated != null && DateTime.now().difference(_lastUpdated!).inDays < 7) {
      _showToast('Dữ liệu AI đã được cập nhật gần đây.');
      return;
    }

    setState(() { _isAnalyzing = true; _errorMessage = null; });

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('messages')
          .doc(widget.conversationId)
          .collection(widget.conversationId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      if (querySnapshot.docs.isEmpty) {
        _showToast('Chưa có đủ tin nhắn để phân tích.');
        return;
      }

      final chatHistory = querySnapshot.docs.map((doc) {
        final msg = MessageChat.fromDocument(doc);
        final who = msg.idFrom == widget.currentUserId ? 'Tôi' : widget.peerNickname;
        return '$who: ${msg.content}';
      }).toList().reversed.toList();

      final result = await AIBackendService().extractRelationshipMemory(
          messages: chatHistory,
          conversationId: widget.conversationId
      );

      if (result != null) {
        final dataMap = result.toMap();
        await FirebaseFirestore.instance.collection('relationship_memories').doc(widget.conversationId).set({
          'data': dataMap,
          'lastUpdated': FieldValue.serverTimestamp(),
          'participants': [widget.currentUserId, widget.peerId],
        });
        _applyData(_RelationshipData.fromMap(dataMap));
        _lastUpdated = DateTime.now();
        _showToast('Đã cập nhật AI Memory ✨');
      } else {
        _showToast('Lỗi phân tích AI. Thử lại sau.');
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
      _showToast('Có lỗi xảy ra: $e');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _deleteMemory(ThemeProvider theme) async {
    final p = theme.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Xóa dữ liệu Memory?', style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('Toàn bộ phân tích AI về mối quan hệ này sẽ bị xóa vĩnh viễn.', style: TextStyle(color: p.textSecondary, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Hủy', style: TextStyle(color: p.textSecondary))
          ),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Xóa', style: TextStyle(color: p.dangerColor, fontWeight: FontWeight.w700))
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection('relationship_memories').doc(widget.conversationId).delete();
    setState(() { _data = null; _lastUpdated = null; });
    _showToast('Đã xóa dữ liệu AI Memory.');
  }

  void _showToast(String msg) => Fluttertoast.showToast(
      msg: msg,
      backgroundColor: Colors.black87,
      textColor: Colors.white
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: _buildAppBar(p, theme),
        body: _buildBody(p, theme),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemePalette p, ThemeProvider theme) => AppBar(
    backgroundColor: p.appBarBackground,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor, size: 20),
        onPressed: () => Navigator.pop(context)
    ),
    title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              widget.peerNickname,
              style: TextStyle(color: p.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)
          ),
          const Text(
              'AI Relationship Memory',
              style: TextStyle(color: Color(0xFF8888AA), fontSize: 11)
          ),
        ]
    ),
    actions: [
      if (_data != null && !_isAnalyzing)
        IconButton(
          icon: Icon(Icons.refresh_rounded, color: theme.primaryColor),
          onPressed: () => _analyzeMemory(forceRefresh: true),
          tooltip: 'Phân tích lại',
        ),
      if (_isAnalyzing)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C6EFF))
          ),
        ),
      const SizedBox(width: 4),
    ],
  );

  Widget _buildBody(ThemePalette p, ThemeProvider theme) {
    if (_isLoading) {
      return Center(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingOrb(color: theme.primaryColor),
                const SizedBox(height: 16),
                Text('Đang tải dữ liệu…', style: TextStyle(color: p.textSecondary, fontSize: 14)),
              ]
          )
      );
    }

    if (_data == null) return _buildEmptyState(p, theme);

    return _buildContent(p, theme);
  }

  Widget _buildEmptyState(ThemePalette p, ThemeProvider theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [
                        theme.primaryColor.withValues(alpha: 0.2),
                        theme.primaryColor.withValues(alpha: 0.05)
                      ]
                  ),
                  boxShadow: [
                    BoxShadow(color: theme.primaryColor.withValues(alpha: 0.2), blurRadius: 30)
                  ],
                ),
                child: Icon(Icons.psychology_rounded, color: theme.primaryColor, size: 44),
              ),
              const SizedBox(height: 28),
              Text(
                  'Chưa có phân tích',
                  style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5
                  )
              ),
              const SizedBox(height: 10),
              Text(
                  'Để AI phân tích mối quan hệ của bạn với ${widget.peerNickname}, nhấn nút bên dưới.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, fontSize: 14, height: 1.6)
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: p.dangerColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.dangerColor.withValues(alpha: 0.25))
                  ),
                  child: Text(_errorMessage!, style: TextStyle(color: p.dangerColor, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 32),
              _isAnalyzing
                  ? _PulsingOrb(color: theme.primaryColor)
                  : SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _analyzeMemory(forceRefresh: true),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text(
                      'Khởi chạy AI Memory',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ]
        ),
      ),
    );
  }

  Widget _buildContent(ThemePalette p, ThemeProvider theme) {
    final data = _data!;

    return FadeTransition(
      opacity: _fadeAc,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHealthScoreCard(data, p, theme),
          const SizedBox(height: 14),
          _buildInfoRow(data, p, theme),
          if (data.sharedTopics.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildTopicsSection(data.sharedTopics, p, theme)
          ],
          if (data.importantDates.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildDatesSection(data.importantDates, p, theme)
          ],
          if (data.memories.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildSectionHeader('Ký ức & Dấu mốc', Icons.timeline_rounded, p, theme),
            const SizedBox(height: 12),
            _buildMemoryTimeline(data.memories, p),
          ],
          const SizedBox(height: 24),
          _buildFooter(p, theme),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHealthScoreCard(_RelationshipData data, ThemePalette p, ThemeProvider theme) {
    final score = data.healthScore.clamp(0, 100);
    final scoreColor = score >= 75
        ? const Color(0xFF6EFFCB)
        : score >= 50
        ? theme.primaryColor
        : const Color(0xFFFF6E9C);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.divider, width: 0.6),
        boxShadow: [
          BoxShadow(color: scoreColor.withValues(alpha: 0.08), blurRadius: 30)
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Chỉ số quan hệ',
                                style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.6
                                )
                            ),
                            const SizedBox(height: 6),
                            AnimatedBuilder(
                                animation: _scoreAnim,
                                builder: (_, __) => Text(
                                  '${(score * _scoreAnim.value).round()}',
                                  style: TextStyle(
                                      color: scoreColor,
                                      fontSize: 56,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                      letterSpacing: -2
                                  ),
                                )
                            ),
                            Text(
                                '/100',
                                style: TextStyle(
                                    color: scoreColor.withValues(alpha: 0.5),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600
                                )
                            ),
                          ]
                      )
                  ),
                  _ScoreGauge(progress: score / 100, color: scoreColor, scoreAnim: _scoreAnim),
                ]
            ),
            const SizedBox(height: 18),
            AnimatedBuilder(
                animation: _scoreAnim,
                builder: (_, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (score / 100) * _scoreAnim.value,
                    backgroundColor: p.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                    minHeight: 6,
                  ),
                )
            ),
            if (data.summary.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                  data.summary,
                  style: TextStyle(color: p.textSecondary, fontSize: 13.5, height: 1.6)
              ),
            ],
            if (_lastUpdated != null) ...[
              const SizedBox(height: 12),
              Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 12, color: p.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                        'Cập nhật ${DateFormat('dd/MM/yyyy HH:mm').format(_lastUpdated!)}',
                        style: TextStyle(color: p.textSecondary, fontSize: 11)
                    ),
                  ]
              ),
            ],
          ]
      ),
    );
  }

  Widget _buildInfoRow(_RelationshipData data, ThemePalette p, ThemeProvider theme) {
    final styleLabel = {
      'formal': 'Trang trọng',
      'casual': 'Thân mật',
      'mixed': 'Hỗn hợp'
    }[data.communicationStyle] ?? data.communicationStyle;

    return Row(
        children: [
          Expanded(
              child: _InfoChip(
                  icon: data.relationshipType.icon,
                  label: 'Loại quan hệ',
                  value: data.relationshipType.label,
                  color: theme.primaryColor,
                  palette: p
              )
          ),
          const SizedBox(width: 10),
          Expanded(
              child: _InfoChip(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Phong cách',
                  value: styleLabel,
                  color: const Color(0xFFFF6E9C),
                  palette: p
              )
          ),
          const SizedBox(width: 10),
          Expanded(
              child: _InfoChip(
                  icon: Icons.thermostat_rounded,
                  label: 'Thân thiết',
                  value: '❤️' * data.closenessLevel.clamp(1, 5),
                  color: const Color(0xFF6EFFCB),
                  palette: p
              )
          ),
        ]
    );
  }

  Widget _buildTopicsSection(List<String> topics, ThemePalette p, ThemeProvider theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Chủ đề chung', Icons.tag_rounded, p, theme),
        const SizedBox(height: 10),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: topics.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.primaryColor.withValues(alpha: 0.25)),
              ),
              child: Text(
                  t,
                  style: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600
                  )
              ),
            )).toList()
        ),
      ],
    );
  }

  Widget _buildDatesSection(List<String> dates, ThemePalette p, ThemeProvider theme) {
    final colors = [theme.primaryColor, const Color(0xFFFF6E9C), const Color(0xFF6EFFCB)];

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Ngày quan trọng', Icons.calendar_today_rounded, p, theme),
          const SizedBox(height: 10),
          ...dates.asMap().entries.map((e) {
            final c = colors[e.key % colors.length];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.divider, width: 0.6)
              ),
              child: Row(
                  children: [
                    Container(
                        width: 4,
                        height: 32,
                        decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(2)
                        )
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Text(
                            e.value,
                            style: TextStyle(color: p.textPrimary, fontSize: 13.5, height: 1.4)
                        )
                    ),
                  ]
              ),
            );
          }),
        ]
    );
  }

  Widget _buildMemoryTimeline(List<_MemoryEntry> memories, ThemePalette p) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: memories.length,
      separatorBuilder: (_, __) => const SizedBox.shrink(),
      itemBuilder: (_, i) => _TimelineEntry(
          entry: memories[i],
          isLast: i == memories.length - 1,
          palette: p
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ThemePalette p, ThemeProvider theme) {
    return Row(
        children: [
          Icon(icon, size: 15, color: theme.primaryColor),
          const SizedBox(width: 8),
          Text(
              title,
              style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2
              )
          ),
        ]
    );
  }

  Widget _buildFooter(ThemePalette p, ThemeProvider theme) {
    return Column(
        children: [
          if (_isAnalyzing) ...[
            _PulsingOrb(color: theme.primaryColor),
            const SizedBox(height: 12),
            Text('AI đang phân tích…', style: TextStyle(color: p.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
          ],
          Row(
              children: [
                Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzing ? null : () => _analyzeMemory(forceRefresh: true),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Phân tích lại', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        disabledBackgroundColor: p.surfaceVariant,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    )
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _deleteMemory(theme),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: p.dangerColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.dangerColor.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.delete_outline_rounded, color: p.dangerColor, size: 20),
                  ),
                ),
              ]
          ),
        ]
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final ThemePalette palette;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.palette
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.divider, width: 0.6)
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
                children: [
                  Icon(icon, size: 12, color: color),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(
                          label,
                          style: TextStyle(
                              fontSize: 10,
                              color: color.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3
                          ),
                          overflow: TextOverflow.ellipsis
                      )
                  )
                ]
            ),
            const SizedBox(height: 6),
            Text(
                value,
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis
            ),
          ]
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final _MemoryEntry entry;
  final bool isLast;
  final ThemePalette palette;

  const _TimelineEntry({
    required this.entry,
    required this.isLast,
    required this.palette
  });

  @override
  Widget build(BuildContext context) {
    final color = entry.category.color;

    return IntrinsicHeight(
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
                width: 36,
                child: Column(
                    children: [
                      Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5)
                          ),
                          child: Icon(entry.category.icon, size: 14, color: color)
                      ),
                      if (!isLast)
                        Expanded(
                            child: Container(
                                width: 1.5,
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [color.withValues(alpha: 0.3), palette.divider]
                                    )
                                )
                            )
                        ),
                    ]
                )
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Container(
                  margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withValues(alpha: 0.2))
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6)
                          ),
                          child: Text(
                              entry.category.label,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4
                              )
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                            entry.content,
                            style: TextStyle(color: palette.textPrimary, fontSize: 13.5, height: 1.6)
                        ),
                      ]
                  ),
                )
            ),
          ]
      ),
    );
  }
}

class _ScoreGauge extends StatelessWidget {
  final double progress;
  final Color color;
  final Animation<double> scoreAnim;

  const _ScoreGauge({
    required this.progress,
    required this.color,
    required this.scoreAnim
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scoreAnim,
      builder: (_, __) => SizedBox(
          width: 72,
          height: 72,
          child: CustomPaint(
            painter: _GaugePainter(progress: progress * scoreAnim.value, color: color),
            child: Center(
                child: Icon(Icons.favorite_rounded, color: color.withValues(alpha: 0.7), size: 22)
            ),
          )
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;

  const _GaugePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const startAngle = -math.pi * 0.8;
    const sweepMax = math.pi * 1.6;

    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepMax,
        false,
        Paint()
          ..color = const Color(0xFF2A2A3A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
    );

    if (progress > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepMax * progress,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      );

      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepMax * progress,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress || old.color != color;
}

class _PulsingOrb extends StatefulWidget {
  final Color color;

  const _PulsingOrb({required this.color});

  @override
  State<_PulsingOrb> createState() => _PulsingOrbState();
}

class _PulsingOrbState extends State<_PulsingOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000)
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.05 + _ac.value * 0.1),
          boxShadow: [
            BoxShadow(
                color: widget.color.withValues(alpha: 0.2 + _ac.value * 0.2),
                blurRadius: 16 + _ac.value * 16
            )
          ],
        ),
        child: Icon(Icons.auto_awesome_rounded, color: widget.color, size: 22),
      ),
    );
  }
}
// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';





const _kBg = Color(0xFF0D0D14);
const _kSurface = Color(0xFF16161F);
const _kSurface2 = Color(0xFF1E1E2A);
const _kBorder = Color(0xFF2A2A3A);
const _kAccent = Color(0xFF7C6EFF); 
const _kAccent2 = Color(0xFFFF6E9C); 
const _kAccent3 = Color(0xFF6EFFCB); 
const _kTextPri = Color(0xFFF0F0FF);
const _kTextSec = Color(0xFF8888AA);
const _kTextDim = Color(0xFF55556A);


const _kCatColors = {
  'memory': Color(0xFF7C6EFF),
  'preference': Color(0xFFFF6E9C),
  'promise': Color(0xFFFFB86E),
  'milestone': Color(0xFF6EFFCB),
  'conflict': Color(0xFFFF6E6E),
  'gratitude': Color(0xFFFFE56E),
};





enum MemoryCategory {
  memory,
  preference,
  promise,
  milestone,
  conflict,
  gratitude;

  static MemoryCategory fromString(String? s) {
    return MemoryCategory.values.firstWhere(
      (e) => e.name == s,
      orElse: () => MemoryCategory.memory,
    );
  }

  String get label {
    switch (this) {
      case MemoryCategory.memory:
        return 'Kỷ niệm';
      case MemoryCategory.preference:
        return 'Sở thích';
      case MemoryCategory.promise:
        return 'Lời hứa';
      case MemoryCategory.milestone:
        return 'Dấu mốc';
      case MemoryCategory.conflict:
        return 'Mâu thuẫn';
      case MemoryCategory.gratitude:
        return 'Biết ơn';
    }
  }

  IconData get icon {
    switch (this) {
      case MemoryCategory.memory:
        return Icons.auto_awesome_rounded;
      case MemoryCategory.preference:
        return Icons.favorite_rounded;
      case MemoryCategory.promise:
        return Icons.handshake_rounded;
      case MemoryCategory.milestone:
        return Icons.flag_rounded;
      case MemoryCategory.conflict:
        return Icons.thunderstorm_rounded;
      case MemoryCategory.gratitude:
        return Icons.sentiment_very_satisfied_rounded;
    }
  }

  Color get color => _kCatColors[name] ?? _kAccent;
}

enum RelationshipType {
  friend,
  family,
  colleague,
  romantic,
  unknown;

  static RelationshipType fromString(String? s) => RelationshipType.values
      .firstWhere((e) => e.name == s, orElse: () => RelationshipType.unknown);

  String get label {
    switch (this) {
      case RelationshipType.friend:
        return 'Bạn bè';
      case RelationshipType.family:
        return 'Gia đình';
      case RelationshipType.colleague:
        return 'Đồng nghiệp';
      case RelationshipType.romantic:
        return 'Tình cảm';
      case RelationshipType.unknown:
        return 'Chưa xác định';
    }
  }

  IconData get icon {
    switch (this) {
      case RelationshipType.friend:
        return Icons.people_rounded;
      case RelationshipType.family:
        return Icons.family_restroom_rounded;
      case RelationshipType.colleague:
        return Icons.work_rounded;
      case RelationshipType.romantic:
        return Icons.favorite_rounded;
      case RelationshipType.unknown:
        return Icons.person_rounded;
    }
  }
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
  final int healthScore;
  final String summary;
  final RelationshipType relationshipType;
  final String communicationStyle;
  final int closenessLevel;
  final List<String> sharedTopics;
  final List<String> importantDates;
  final List<_MemoryEntry> memories;

  const _RelationshipData({
    required this.healthScore,
    required this.summary,
    required this.relationshipType,
    required this.communicationStyle,
    required this.closenessLevel,
    required this.sharedTopics,
    required this.importantDates,
    required this.memories,
  });

  factory _RelationshipData.fromMap(Map<String, dynamic> map) {
    final memories = (map['memories'] as List<dynamic>? ?? [])
        .map((e) => _MemoryEntry.fromMap(e as Map))
        .toList();
    final sharedTopics =
        (map['sharedTopics'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    final importantDates =
        (map['importantDates'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();

    return _RelationshipData(
      healthScore: (map['healthScore'] as num?)?.toInt() ?? 0,
      summary: map['summary'] as String? ?? '',
      relationshipType: RelationshipType.fromString(map['relationshipType'] as String?),
      communicationStyle: map['communicationStyle'] as String? ?? 'mixed',
      closenessLevel: (map['closenessLevel'] as num?)?.toInt() ?? 1,
      sharedTopics: sharedTopics,
      importantDates: importantDates,
      memories: memories,
    );
  }
}





class MemoryTimelinePage extends StatefulWidget {
  const MemoryTimelinePage({
    super.key,
    required this.peerId,
    required this.peerNickname,
    required this.currentUserId,
    required this.conversationId,
  });

  final String peerId;
  final String peerNickname;
  final String currentUserId;
  final String conversationId;

  @override
  State<MemoryTimelinePage> createState() => _MemoryTimelinePageState();
}

class _MemoryTimelinePageState extends State<MemoryTimelinePage> with TickerProviderStateMixin {
  
  bool _isLoading = true;
  bool _isAnalyzing = false;
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
    _scoreAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _scoreAnim = CurvedAnimation(parent: _scoreAc, curve: Curves.easeOutCubic);
    _fetchCachedMemory();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void dispose() {
    _fadeAc.dispose();
    _scoreAc.dispose();
    super.dispose();
  }

  

  Future<void> _fetchCachedMemory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
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
    
    if (!forceRefresh && _lastUpdated != null) {
      final days = DateTime.now().difference(_lastUpdated!).inDays;
      if (days < 7) {
        _showToast('Dữ liệu AI đã được cập nhật gần đây.');
        return;
      }
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

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

      final chatHistory = querySnapshot.docs
          .map((doc) {
            final msg = MessageChat.fromDocument(doc);
            final who = msg.idFrom == widget.currentUserId ? 'Tôi' : widget.peerNickname;
            return '$who: ${msg.content}';
          })
          .toList()
          .reversed
          .toList();

      final result = await AIBackendService().extractRelationshipMemory(
        chatHistory,
        conversationId: widget.conversationId,
      );

      if (result != null) {
        final dataMap = result.rawData;

        
        await FirebaseFirestore.instance
            .collection('relationship_memories')
            .doc(widget.conversationId)
            .set({
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

  Future<void> _deleteMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: 'Xóa dữ liệu Memory?',
        message: 'Toàn bộ phân tích AI về mối quan hệ này sẽ bị xóa vĩnh viễn.',
        confirmLabel: 'Xóa',
        confirmColor: _kAccent2,
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('relationship_memories')
          .doc(widget.conversationId)
          .delete();
      setState(() {
        _data = null;
        _lastUpdated = null;
      });
      _showToast('Đã xóa dữ liệu AI Memory.');
    } catch (e) {
      _showToast('Xóa thất bại: $e');
    }
  }

  void _showToast(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: _kSurface2,
      textColor: _kTextPri,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  
  
  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kTextPri, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.peerNickname,
            style: const TextStyle(
              color: _kTextPri,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const Text(
            'AI Relationship Memory',
            style: TextStyle(color: _kTextSec, fontSize: 11),
          ),
        ],
      ),
      actions: [
        if (_data != null && !_isAnalyzing)
          _IconBtn(
            icon: Icons.refresh_rounded,
            color: _kAccent,
            onTap: () => _analyzeMemory(forceRefresh: true),
            tooltip: 'Phân tích lại',
          ),
        if (_isAnalyzing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _kAccent,
              ),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoadingState();
    if (_data == null) return _buildEmptyState();
    return _buildContent();
  }

  

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingOrb(),
          SizedBox(height: 20),
          Text('Đang tải dữ liệu…', style: TextStyle(color: _kTextSec, fontSize: 14)),
        ],
      ),
    );
  }

  

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _GlowOrb(size: 100, color: _kAccent, glowRadius: 40),
            const SizedBox(height: 32),
            const Text(
              'Chưa có phân tích',
              style: TextStyle(
                color: _kTextPri,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Để AI phân tích mối quan hệ của bạn với ${widget.peerNickname}, '
              'nhấn nút bên dưới.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextSec, fontSize: 14, height: 1.6),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x22FF6E6E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x44FF6E6E)),
                ),
                child: Text(_errorMessage!,
                    style: const TextStyle(color: Color(0xFFFF6E6E), fontSize: 12)),
              ),
            ],
            const SizedBox(height: 32),
            _isAnalyzing
                ? const _PulsingOrb()
                : _GlowButton(
                    label: 'Khởi chạy AI Memory',
                    icon: Icons.auto_awesome_rounded,
                    onTap: () => _analyzeMemory(forceRefresh: true),
                  ),
          ],
        ),
      ),
    );
  }

  

  Widget _buildContent() {
    final data = _data!;
    return FadeTransition(
      opacity: _fadeAc,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.of(context).padding.top + kToolbarHeight + 8,
          16,
          32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            _buildHealthScoreCard(data),
            const SizedBox(height: 16),

            
            _buildInfoRow(data),
            const SizedBox(height: 16),

            
            if (data.sharedTopics.isNotEmpty) ...[
              _buildTopicsSection(data.sharedTopics),
              const SizedBox(height: 16),
            ],

            
            if (data.importantDates.isNotEmpty) ...[
              _buildDatesSection(data.importantDates),
              const SizedBox(height: 16),
            ],

            
            if (data.memories.isNotEmpty) ...[
              _buildSectionHeader('Ký ức & Dấu mốc', Icons.timeline_rounded),
              const SizedBox(height: 12),
              _buildMemoryTimeline(data.memories),
            ],

            const SizedBox(height: 32),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  

  Widget _buildHealthScoreCard(_RelationshipData data) {
    final score = data.healthScore.clamp(0, 100);
    final scoreColor = score >= 75
        ? _kAccent3
        : score >= 50
            ? _kAccent
            : _kAccent2;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: scoreColor.withValues(alpha: 0.08),
            blurRadius: 30,
            spreadRadius: 0,
          ),
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
                    const Text('Chỉ số quan hệ',
                        style: TextStyle(
                            color: _kTextSec,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8)),
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
                          letterSpacing: -2,
                        ),
                      ),
                    ),
                    Text('/100',
                        style: TextStyle(
                            color: scoreColor.withValues(alpha: 0.5),
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              _buildScoreGauge(score, scoreColor),
            ],
          ),
          const SizedBox(height: 20),
          
          AnimatedBuilder(
            animation: _scoreAnim,
            builder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (score / 100) * _scoreAnim.value,
                backgroundColor: _kBorder,
                valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                minHeight: 6,
              ),
            ),
          ),
          if (data.summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              data.summary,
              style: const TextStyle(
                color: _kTextSec,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
          if (_lastUpdated != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 12, color: _kTextDim),
                const SizedBox(width: 4),
                Text(
                  'Cập nhật ${DateFormat('dd/MM/yyyy HH:mm').format(_lastUpdated!)}',
                  style: const TextStyle(color: _kTextDim, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreGauge(int score, Color color) {
    return AnimatedBuilder(
      animation: _scoreAnim,
      builder: (_, __) => SizedBox(
        width: 72,
        height: 72,
        child: CustomPaint(
          painter: _ScoreGaugePainter(
            progress: (score / 100) * _scoreAnim.value,
            color: color,
          ),
          child: Center(
            child: Icon(Icons.favorite_rounded, color: color.withValues(alpha: 0.7), size: 22),
          ),
        ),
      ),
    );
  }

  

  Widget _buildInfoRow(_RelationshipData data) {
    final styleLabel = {
          'formal': 'Trang trọng',
          'casual': 'Thân mật',
          'mixed': 'Hỗn hợp',
        }[data.communicationStyle] ??
        data.communicationStyle;

    return Row(
      children: [
        Expanded(
          child: _InfoChip(
            icon: data.relationshipType.icon,
            label: 'Loại quan hệ',
            value: data.relationshipType.label,
            color: _kAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoChip(
            icon: Icons.chat_bubble_rounded,
            label: 'Phong cách',
            value: styleLabel,
            color: _kAccent2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoChip(
            icon: Icons.thermostat_rounded,
            label: 'Độ thân thiết',
            value: '❤️' * data.closenessLevel.clamp(1, 5),
            color: _kAccent3,
          ),
        ),
      ],
    );
  }

  

  Widget _buildTopicsSection(List<String> topics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Chủ đề chung', Icons.tag_rounded),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: topics.map((t) => _TopicChip(label: t)).toList(),
        ),
      ],
    );
  }

  

  Widget _buildDatesSection(List<String> dates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Ngày quan trọng', Icons.calendar_today_rounded),
        const SizedBox(height: 12),
        ...dates.asMap().entries.map((e) => _DateRow(
              index: e.key,
              label: e.value,
            )),
      ],
    );
  }

  

  Widget _buildMemoryTimeline(List<_MemoryEntry> memories) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: memories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 0),
      itemBuilder: (_, i) => _TimelineEntry(
        entry: memories[i],
        isLast: i == memories.length - 1,
        index: i,
      ),
    );
  }

  

  Widget _buildFooter() {
    return Column(
      children: [
        if (_isAnalyzing) ...[
          const _PulsingOrb(),
          const SizedBox(height: 12),
          const Text('AI đang phân tích…', style: TextStyle(color: _kTextSec, fontSize: 13)),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            Expanded(
              child: _GlowButton(
                label: 'Phân tích lại',
                icon: Icons.refresh_rounded,
                onTap: _isAnalyzing ? null : () => _analyzeMemory(forceRefresh: true),
                compact: true,
              ),
            ),
            const SizedBox(width: 12),
            _IconBtn(
              icon: Icons.delete_outline_rounded,
              color: _kAccent2,
              onTap: _deleteMemory,
              tooltip: 'Xóa dữ liệu',
              outlined: true,
            ),
          ],
        ),
      ],
    );
  }

  

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _kAccent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: _kTextPri,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}





class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
          ]),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _kTextPri,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  final String label;
  const _TopicChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _kAccent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final int index;
  final String label;
  const _DateRow({required this.index, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = [_kAccent, _kAccent2, _kAccent3];
    final c = colors[index % colors.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.04), blurRadius: 12),
        ],
      ),
      child: Row(children: [
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label, style: const TextStyle(color: _kTextPri, fontSize: 13, height: 1.5)),
        ),
      ]),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final _MemoryEntry entry;
  final bool isLast;
  final int index;

  const _TimelineEntry({
    required this.entry,
    required this.isLast,
    required this.index,
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
                    border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Icon(entry.category.icon, size: 14, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [color.withValues(alpha: 0.3), _kBorder],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.category.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.content,
                    style: const TextStyle(
                      color: _kTextPri,
                      fontSize: 13,
                      height: 1.6,
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
}

class _GlowButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;

  const _GlowButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 28, vertical: compact ? 12 : 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: onTap != null ? [_kAccent, const Color(0xFF9B6EFF)] : [_kSurface2, _kSurface2],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                      color: _kAccent.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, color: onTap != null ? Colors.white : _kTextDim, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: onTap != null ? Colors.white : _kTextDim,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 13 : 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;
  final bool outlined;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: outlined ? Border.all(color: color.withValues(alpha: 0.3)) : null,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  final double glowRadius;

  const _GlowOrb({required this.size, required this.color, required this.glowRadius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: glowRadius),
          BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: glowRadius * 2),
        ],
      ),
      child: Icon(Icons.psychology_rounded, color: color, size: size * 0.45),
    );
  }
}

class _PulsingOrb extends StatefulWidget {
  const _PulsingOrb();
  @override
  State<_PulsingOrb> createState() => _PulsingOrbState();
}

class _PulsingOrbState extends State<_PulsingOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
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
          color: _kAccent.withValues(alpha: 0.05 + _ac.value * 0.1),
          boxShadow: [
            BoxShadow(
              color: _kAccent.withValues(alpha: 0.2 + _ac.value * 0.2),
              blurRadius: 16 + _ac.value * 16,
            ),
          ],
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: _kAccent, size: 22),
      ),
    );
  }
}





class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: const TextStyle(
                  color: _kTextPri,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kTextSec, fontSize: 13, height: 1.5)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _kSurface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorder),
                      ),
                      child: const Center(
                        child: Text('Huỷ',
                            style: TextStyle(color: _kTextSec, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: confirmColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: confirmColor.withValues(alpha: 0.4)),
                      ),
                      child: Center(
                        child: Text(confirmLabel,
                            style: TextStyle(
                              color: confirmColor,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}





class _ScoreGaugePainter extends CustomPainter {
  final double progress;
  final Color color;

  const _ScoreGaugePainter({required this.progress, required this.color});

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
        ..color = _kBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
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
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3),
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
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ScoreGaugePainter old) => old.progress != progress || old.color != color;
}

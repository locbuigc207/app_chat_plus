import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PollOption {
  final String id;
  final String text;
  final List<String> votes;

  const PollOption({
    required this.id,
    required this.text,
    required this.votes,
  });

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        votes: List<String>.from(
          (json['votes'] as List?)?.map((e) => e.toString()) ?? [],
        ),
      );

  PollOption copyWith({List<String>? votes}) => PollOption(
        id: id,
        text: text,
        votes: votes ?? this.votes,
      );
}

class PollData {
  final String question;
  final List<PollOption> options;
  final bool isMultipleChoice;
  final bool isAnonymous;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  const PollData({
    required this.question,
    required this.options,
    this.isMultipleChoice = false,
    this.isAnonymous = false,
    this.expiresAt,
    this.createdAt,
  });

  factory PollData.fromJson(Map<String, dynamic> json) => PollData(
        question: json['question']?.toString() ?? 'Bình chọn',
        options: (json['options'] as List? ?? [])
            .map((o) => PollOption.fromJson(o as Map<String, dynamic>))
            .toList(),
        isMultipleChoice: json['isMultipleChoice'] as bool? ?? false,
        isAnonymous: json['isAnonymous'] as bool? ?? false,
        expiresAt:
            json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'] as String) : null,
        createdAt:
            json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  int get totalVotes => options.fold(0, (sum, opt) => sum + opt.votes.length);

  double percentageFor(PollOption option) {
    if (totalVotes == 0) return 0;
    return option.votes.length / totalVotes;
  }
}

class PollMessageWidget extends StatefulWidget {
  final String content;

  final String messageId;

  final String currentUserId;

  final Future<void> Function(String messageId, String optionId) onVote;

  final bool isSentByMe;

  const PollMessageWidget({
    super.key,
    required this.content,
    required this.messageId,
    required this.currentUserId,
    required this.onVote,
    this.isSentByMe = false,
  });

  @override
  State<PollMessageWidget> createState() => _PollMessageWidgetState();
}

class _PollMessageWidgetState extends State<PollMessageWidget> with TickerProviderStateMixin {
  late PollData _poll;
  bool _isVoting = false;
  bool _showResults = false;
  Timer? _expiryTimer;

  late AnimationController _entranceController;
  late Animation<double> _entranceFade;
  late Animation<Offset> _entranceSlide;

  final List<AnimationController> _barControllers = [];
  final List<Animation<double>> _barAnims = [];

  late AnimationController _confettiController;
  final List<_Particle> _particles = [];

  static const _optionPalette = [
    Color(0xFF6C63FF),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFF84CC16),
    Color(0xFFEC4899),
    Color(0xFFFF7849),
  ];

  @override
  void initState() {
    super.initState();
    _parsePoll();
    _initAnimations();
    _entranceController.forward();
    _scheduleExpiryTimer();
  }

  @override
  void didUpdateWidget(PollMessageWidget old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) {
      _parsePoll();
      _syncBarAnimations();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _confettiController.dispose();
    for (final c in _barControllers) {
      c.dispose();
    }
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _parsePoll() {
    try {
      _poll = PollData.fromJson(jsonDecode(widget.content) as Map<String, dynamic>);
    } catch (_) {
      _poll = const PollData(
        question: 'Không thể tải bình chọn',
        options: [],
      );
    }
    _showResults = _hasVotedAny || _poll.isExpired;
  }

  void _initAnimations() {
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _rebuildBarAnimations();

    if (_showResults) {
      for (final c in _barControllers) {
        c.forward();
      }
    }
  }

  void _rebuildBarAnimations() {
    for (final c in _barControllers) {
      c.dispose();
    }
    _barControllers.clear();
    _barAnims.clear();

    for (var i = 0; i < _poll.options.length; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 500 + i * 60),
      );
      final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
      _barControllers.add(ctrl);
      _barAnims.add(anim);
    }
  }

  void _syncBarAnimations() {
    if (_barControllers.length != _poll.options.length) {
      _rebuildBarAnimations();
    }

    if (_showResults) {
      for (final c in _barControllers) {
        c
          ..reset()
          ..forward();
      }
    }
  }

  void _scheduleExpiryTimer() {
    final exp = _poll.expiresAt;
    if (exp == null || _poll.isExpired) return;

    final remaining = exp.difference(DateTime.now());
    if (remaining.isNegative) return;

    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(() => _showResults = true);
    });

    Timer.periodic(const Duration(minutes: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_poll.isExpired) {
        t.cancel();
        setState(() => _showResults = true);
      } else {
        setState(() {});
      }
    });
  }

  bool _hasVotedFor(PollOption opt) => opt.votes.contains(widget.currentUserId);

  bool get _hasVotedAny => _poll.options.any((o) => _hasVotedFor(o));

  Future<void> _handleVote(String optionId) async {
    if (_poll.isExpired || _isVoting) return;

    HapticFeedback.selectionClick();
    setState(() => _isVoting = true);

    try {
      await widget.onVote(widget.messageId, optionId);

      if (mounted) {
        setState(() => _showResults = true);
        for (final c in _barControllers) {
          c
            ..reset()
            ..forward();
        }
        _playConfetti();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bình chọn thất bại, thử lại'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  void _playConfetti() {
    final rng = math.Random();
    _particles
      ..clear()
      ..addAll(List.generate(
        20,
        (_) => _Particle(
          color: _optionPalette[rng.nextInt(_optionPalette.length)],
          x: rng.nextDouble(),
          delay: rng.nextDouble() * 0.4,
          size: rng.nextDouble() * 5 + 4,
          angle: rng.nextDouble() * math.pi * 2,
        ),
      ));
    _confettiController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final maxW = math.min(MediaQuery.of(context).size.width * 0.82, 420.0);

    return FadeTransition(
      opacity: _entranceFade,
      child: SlideTransition(
        position: _entranceSlide,
        child: Align(
          alignment: widget.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: maxW,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: _bubbleRadius(),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
              border: Border.all(color: const Color(0xFFF3F4F6)),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ..._poll.options.asMap().entries.map(
                                (e) => _buildOption(e.key, e.value),
                              ),
                          const SizedBox(height: 6),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_particles.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _confettiController,
                        builder: (_, __) => CustomPaint(
                          painter: _ConfettiPainter(
                            particles: _particles,
                            progress: _confettiController.value,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BorderRadius _bubbleRadius() {
    return BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(widget.isSentByMe ? 20 : 4),
      bottomRight: Radius.circular(widget.isSentByMe ? 4 : 20),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF6C63FF),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll_rounded, color: Colors.white70, size: 14),
              const SizedBox(width: 5),
              Text(
                _poll.isExpired ? 'Đã kết thúc' : 'Bình chọn',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  letterSpacing: 0.3,
                ),
              ),
              if (_poll.isMultipleChoice) ...[
                const SizedBox(width: 6),
                _HeaderChip(label: 'Nhiều đáp án'),
              ],
              if (_poll.isAnonymous) ...[
                const SizedBox(width: 4),
                _HeaderChip(label: 'Ẩn danh'),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline_rounded, color: Colors.white70, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      '${_poll.totalVotes}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            _poll.question,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.35,
              letterSpacing: -0.2,
            ),
          ),
          if (_poll.expiresAt != null) ...[
            const SizedBox(height: 6),
            _ExpiryBadge(
              expiresAt: _poll.expiresAt!,
              isExpired: _poll.isExpired,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOption(int index, PollOption opt) {
    final hasVoted = _hasVotedFor(opt);
    final color = _optionPalette[index % _optionPalette.length];
    final pct = _poll.percentageFor(opt);
    final canTap = !_poll.isExpired && !_isVoting;

    final semanticsLabel = '${opt.text}: ${(pct * 100).round()}% (${opt.votes.length} phiếu)'
        '${hasVoted ? ', đã bình chọn' : ''}';

    return Semantics(
      label: semanticsLabel,
      button: canTap,
      child: GestureDetector(
        onTap: canTap ? () => _handleVote(opt.id) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(bottom: 7),
          height: 46,
          decoration: BoxDecoration(
            color: hasVoted ? color.withValues(alpha: 0.08) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasVoted ? color.withValues(alpha: 0.5) : const Color(0xFFE5E7EB),
              width: hasVoted ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                if (_showResults && index < _barAnims.length)
                  AnimatedBuilder(
                    animation: _barAnims[index],
                    builder: (_, __) {
                      return FractionallySizedBox(
                        widthFactor: pct * _barAnims[index].value,
                        alignment: Alignment.centerLeft,
                        heightFactor: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                hasVoted ? color.withValues(alpha: 0.22) : const Color(0xFFE5E7EB),
                          ),
                        ),
                      );
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    children: [
                      _VoteIndicator(
                        hasVoted: hasVoted,
                        isMultiple: _poll.isMultipleChoice,
                        isExpired: _poll.isExpired,
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          opt.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: hasVoted ? FontWeight.w700 : FontWeight.w500,
                            color: hasVoted ? color : const Color(0xFF374151),
                          ),
                        ),
                      ),
                      if (_isVoting && canTap) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        ),
                      ],
                      if (_showResults) ...[
                        const SizedBox(width: 6),
                        _ResultStats(
                          pct: pct,
                          voteCount: opt.votes.length,
                          isAnonymous: _poll.isAnonymous,
                          hasVoted: hasVoted,
                          color: color,
                        ),
                      ],
                      if (_poll.isExpired &&
                          opt.votes.length == _getMaxVotes() &&
                          _poll.totalVotes > 0) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.workspace_premium_rounded,
                            size: 16, color: Colors.amber.shade600),
                      ],
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

  int _getMaxVotes() {
    if (_poll.options.isEmpty) return 0;
    return _poll.options.map((o) => o.votes.length).reduce(math.max);
  }

  Widget _buildFooter() {
    return Row(
      children: [
        if (!_hasVotedAny && !_poll.isExpired) ...[
          GestureDetector(
            onTap: () => setState(() {
              _showResults = !_showResults;
              if (_showResults) {
                for (final c in _barControllers) {
                  c
                    ..reset()
                    ..forward();
                }
              }
            }),
            child: Text(
              _showResults ? 'Ẩn kết quả' : 'Xem kết quả',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        if (_hasVotedAny && !_poll.isExpired && !_poll.isMultipleChoice) ...[
          GestureDetector(
            onTap: () {
              final votedOpt = _poll.options.firstWhere(_hasVotedFor);
              _handleVote(votedOpt.id);
            },
            child: Text(
              'Thay đổi ›',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6C63FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const Spacer(),
        Text(
          _pollStatusText(),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
      ],
    );
  }

  String _pollStatusText() {
    if (_poll.isExpired) return 'Đã kết thúc';
    if (_poll.totalVotes == 0) return 'Chưa có phiếu';
    return '${_poll.totalVotes} lượt';
  }
}

class _VoteIndicator extends StatelessWidget {
  final bool hasVoted;
  final bool isMultiple;
  final bool isExpired;
  final Color color;

  const _VoteIndicator({
    required this.hasVoted,
    required this.isMultiple,
    required this.isExpired,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (isExpired && !hasVoted) {
      return Icon(Icons.radio_button_unchecked_rounded, size: 18, color: Colors.grey.shade300);
    }

    if (isMultiple) {
      return hasVoted
          ? Icon(Icons.check_box_rounded, size: 18, color: color)
          : Icon(Icons.check_box_outline_blank_rounded, size: 18, color: Colors.grey.shade400);
    }

    return hasVoted
        ? Icon(Icons.radio_button_checked_rounded, size: 18, color: color)
        : Icon(Icons.radio_button_unchecked_rounded, size: 18, color: Colors.grey.shade400);
  }
}

class _ResultStats extends StatelessWidget {
  final double pct;
  final int voteCount;
  final bool isAnonymous;
  final bool hasVoted;
  final Color color;

  const _ResultStats({
    required this.pct,
    required this.voteCount,
    required this.isAnonymous,
    required this.hasVoted,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${(pct * 100).round()}%',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: hasVoted ? color : Colors.grey.shade500,
          ),
        ),
        if (!isAnonymous)
          Text(
            '$voteCount',
            style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
          ),
      ],
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;

  const _HeaderChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ExpiryBadge extends StatefulWidget {
  final DateTime expiresAt;
  final bool isExpired;

  const _ExpiryBadge({required this.expiresAt, required this.isExpired});

  @override
  State<_ExpiryBadge> createState() => _ExpiryBadgeState();
}

class _ExpiryBadgeState extends State<_ExpiryBadge> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_updateRemaining);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateRemaining() {
    _remaining = widget.expiresAt.difference(DateTime.now());
  }

  String _label() {
    if (widget.isExpired || _remaining.isNegative) return 'Đã kết thúc';
    if (_remaining.inDays > 1) return 'Còn ${_remaining.inDays} ngày';
    if (_remaining.inDays == 1) return 'Còn 1 ngày';
    if (_remaining.inHours > 0) return 'Còn ${_remaining.inHours} giờ';
    if (_remaining.inMinutes > 0) return 'Còn ${_remaining.inMinutes} phút';
    return 'Còn ${_remaining.inSeconds}s';
  }

  bool get _isUrgent => !widget.isExpired && _remaining.inMinutes < 10 && !_remaining.isNegative;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          widget.isExpired
              ? Icons.lock_clock_rounded
              : (_isUrgent ? Icons.timer_rounded : Icons.timer_outlined),
          size: 12,
          color: _isUrgent ? Colors.amber.shade200 : Colors.white60,
        ),
        const SizedBox(width: 4),
        Text(
          _label(),
          style: TextStyle(
            color: _isUrgent ? Colors.amber.shade200 : Colors.white60,
            fontSize: 11,
            fontWeight: _isUrgent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _Particle {
  final Color color;
  final double x;
  final double delay;
  final double size;
  final double angle;

  const _Particle({
    required this.color,
    required this.x,
    required this.delay,
    required this.size,
    required this.angle,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  const _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final opacity = (1 - t).clamp(0.0, 1.0);
      final dx = p.x * size.width;
      final dy = -20 + t * size.height * 0.7;

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.angle + t * math.pi * 2);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.5,
          ),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

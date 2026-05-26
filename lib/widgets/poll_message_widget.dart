import 'dart:convert';

import 'package:flutter/material.dart';

/// Model cho một lựa chọn trong poll
class PollOption {
  final String id;
  final String text;
  final List<String> votes; // danh sách userId đã bình chọn

  const PollOption({
    required this.id,
    required this.text,
    required this.votes,
  });

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
        id: json['id'] as String,
        text: json['text'] as String,
        votes: List<String>.from(json['votes'] as List),
      );
}

/// Model chứa toàn bộ dữ liệu poll
class PollData {
  final String question;
  final List<PollOption> options;
  final bool isMultipleChoice;
  final bool isAnonymous;
  final DateTime? expiresAt;

  const PollData({
    required this.question,
    required this.options,
    this.isMultipleChoice = false,
    this.isAnonymous = false,
    this.expiresAt,
  });

  factory PollData.fromJson(Map<String, dynamic> json) => PollData(
        question: json['question'] as String,
        options: (json['options'] as List)
            .map((o) => PollOption.fromJson(o as Map<String, dynamic>))
            .toList(),
        isMultipleChoice: json['isMultipleChoice'] as bool? ?? false,
        isAnonymous: json['isAnonymous'] as bool? ?? false,
        expiresAt: json['expiresAt'] != null
            ? DateTime.tryParse(json['expiresAt'] as String)
            : null,
      );

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  int get totalVotes => options.fold(0, (sum, opt) => sum + opt.votes.length);
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Widget
// ─────────────────────────────────────────────────────────────────────────────

class PollMessageWidget extends StatefulWidget {
  /// Chuỗi JSON chứa question, options, isMultipleChoice, isAnonymous, expiresAt
  final String content;
  final String messageId;
  final String currentUserId;

  /// Gọi khi user bấm bình chọn. Trả về messageId + optionId.
  /// Nếu là multiple choice, optionId là id của lựa chọn được toggle.
  final Future<void> Function(String messageId, String optionId) onVote;

  /// Nếu true, widget hiển thị ở phía bên phải (tin nhắn của mình)
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

class _PollMessageWidgetState extends State<PollMessageWidget>
    with TickerProviderStateMixin {
  late PollData _poll;
  bool _isVoting = false;

  // Màu gradient cho từng option (theo thứ tự)
  static const List<List<Color>> _optionGradients = [
    [Color(0xFF6C63FF), Color(0xFF9B5DE5)],
    [Color(0xFF00B4D8), Color(0xFF00D4AA)],
    [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
    [Color(0xFFFFBE0B), Color(0xFFFB5607)],
    [Color(0xFF3A86FF), Color(0xFF8338EC)],
    [Color(0xFF06D6A0), Color(0xFF118AB2)],
    [Color(0xFFFF006E), Color(0xFF8338EC)],
    [Color(0xFFFFD166), Color(0xFFEF476F)],
    [Color(0xFF2EC4B6), Color(0xFFE71D36)],
    [Color(0xFFCBF3F0), Color(0xFF2EC4B6)],
  ];

  @override
  void initState() {
    super.initState();
    _parsePoll();
  }

  @override
  void didUpdateWidget(PollMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _parsePoll();
    }
  }

  void _parsePoll() {
    try {
      _poll =
          PollData.fromJson(jsonDecode(widget.content) as Map<String, dynamic>);
    } catch (e) {
      // fallback: empty poll
      _poll = const PollData(question: 'Lỗi tải bình chọn', options: []);
    }
  }

  bool _hasVotedFor(PollOption opt) => opt.votes.contains(widget.currentUserId);

  bool get _hasVotedAny => _poll.options.any((o) => _hasVotedFor(o));

  Future<void> _handleVote(String optionId) async {
    if (_poll.isExpired || _isVoting) return;

    setState(() => _isVoting = true);
    try {
      await widget.onVote(widget.messageId, optionId);
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showResults = _hasVotedAny || _poll.isExpired;

    return Align(
      alignment:
          widget.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.80,
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(widget.isSentByMe ? 18 : 4),
            bottomRight: Radius.circular(widget.isSentByMe ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._poll.options.asMap().entries.map((entry) {
                    final index = entry.key;
                    final opt = entry.value;
                    final gradientColors =
                        _optionGradients[index % _optionGradients.length];
                    return _PollOptionTile(
                      key: ValueKey(opt.id),
                      option: opt,
                      totalVotes: _poll.totalVotes,
                      hasVoted: _hasVotedFor(opt),
                      showResult: showResults,
                      isExpired: _poll.isExpired,
                      isAnonymous: _poll.isAnonymous,
                      isMultipleChoice: _poll.isMultipleChoice,
                      gradientColors: gradientColors,
                      isLoading: _isVoting,
                      onTap: () => _handleVote(opt.id),
                    );
                  }),
                  const SizedBox(height: 8),
                  _buildFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF9B5DE5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                _poll.isExpired ? 'Bình chọn đã kết thúc' : 'Bình chọn',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11, letterSpacing: 0.5),
              ),
              if (_poll.isMultipleChoice) ...[
                const SizedBox(width: 6),
                _Chip(label: 'Nhiều đáp án'),
              ],
              if (_poll.isAnonymous) ...[
                const SizedBox(width: 4),
                _Chip(label: 'Ẩn danh'),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _poll.question,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.3),
          ),
          if (_poll.expiresAt != null) ...[
            const SizedBox(height: 4),
            _ExpiryRow(expiresAt: _poll.expiresAt!, isExpired: _poll.isExpired),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final totalVotes = _poll.totalVotes;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.people_outline_rounded,
                size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              '$totalVotes lượt bình chọn',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        if (_hasVotedAny && !_poll.isExpired)
          GestureDetector(
            onTap: () {
              // Tìm option user đã vote đầu tiên và bỏ vote
              final votedOpt = _poll.options.firstWhere((o) => _hasVotedFor(o),
                  orElse: () => _poll.options.first);
              _handleVote(votedOpt.id);
            },
            child: Text(
              'Thay đổi',
              style: TextStyle(
                  fontSize: 12,
                  color: const Color(0xFF6C63FF),
                  fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Poll Option Tile
// ─────────────────────────────────────────────────────────────────────────────

class _PollOptionTile extends StatefulWidget {
  final PollOption option;
  final int totalVotes;
  final bool hasVoted;
  final bool showResult;
  final bool isExpired;
  final bool isAnonymous;
  final bool isMultipleChoice;
  final List<Color> gradientColors;
  final bool isLoading;
  final VoidCallback onTap;

  const _PollOptionTile({
    super.key,
    required this.option,
    required this.totalVotes,
    required this.hasVoted,
    required this.showResult,
    required this.isExpired,
    required this.isAnonymous,
    required this.isMultipleChoice,
    required this.gradientColors,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_PollOptionTile> createState() => _PollOptionTileState();
}

class _PollOptionTileState extends State<_PollOptionTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _barController;
  late Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _barAnim =
        CurvedAnimation(parent: _barController, curve: Curves.easeOutCubic);
    if (widget.showResult) _barController.forward();
  }

  @override
  void didUpdateWidget(_PollOptionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showResult && !oldWidget.showResult) {
      _barController.forward();
    } else if (!widget.showResult && oldWidget.showResult) {
      _barController.reverse();
    }
    if (widget.totalVotes != oldWidget.totalVotes ||
        widget.option.votes.length != oldWidget.option.votes.length) {
      _barController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _barController.dispose();
    super.dispose();
  }

  double get _percentage => widget.totalVotes == 0
      ? 0
      : widget.option.votes.length / widget.totalVotes;

  int get _percentInt => (_percentage * 100).round();

  @override
  Widget build(BuildContext context) {
    final bool canVote = !widget.isExpired && !widget.isLoading;

    return GestureDetector(
      onTap: canVote ? widget.onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 46,
          decoration: BoxDecoration(
            color: widget.hasVoted
                ? widget.gradientColors.first.withOpacity(0.08)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.hasVoted
                  ? widget.gradientColors.first.withOpacity(0.4)
                  : Colors.grey.shade200,
              width: widget.hasVoted ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                // Progress bar
                if (widget.showResult)
                  AnimatedBuilder(
                    animation: _barAnim,
                    builder: (context, child) {
                      return FractionallySizedBox(
                        widthFactor: _percentage * _barAnim.value,
                        heightFactor: 1,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: widget.hasVoted
                                  ? widget.gradientColors
                                  : [
                                      Colors.grey.shade200,
                                      Colors.grey.shade300,
                                    ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                // Content row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      // Check icon / radio
                      _VoteIcon(
                        hasVoted: widget.hasVoted,
                        isMultipleChoice: widget.isMultipleChoice,
                        color: widget.gradientColors.first,
                        isExpired: widget.isExpired,
                      ),
                      const SizedBox(width: 8),

                      // Label
                      Expanded(
                        child: Text(
                          widget.option.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: widget.hasVoted
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: widget.hasVoted
                                ? widget.gradientColors.first
                                : const Color(0xFF1A1A2E),
                          ),
                        ),
                      ),

                      // Right side: percentage or vote count
                      if (widget.showResult) ...[
                        const SizedBox(width: 8),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$_percentInt%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: widget.hasVoted
                                    ? widget.gradientColors.first
                                    : Colors.grey.shade600,
                              ),
                            ),
                            if (!widget.isAnonymous)
                              Text(
                                '${widget.option.votes.length} phiếu',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              ),
                          ],
                        ),
                      ],

                      if (widget.isLoading && canVote) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.gradientColors.first,
                          ),
                        ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _VoteIcon extends StatelessWidget {
  final bool hasVoted;
  final bool isMultipleChoice;
  final Color color;
  final bool isExpired;

  const _VoteIcon({
    required this.hasVoted,
    required this.isMultipleChoice,
    required this.color,
    required this.isExpired,
  });

  @override
  Widget build(BuildContext context) {
    if (isExpired && !hasVoted) {
      return Icon(Icons.radio_button_unchecked_rounded,
          size: 18, color: Colors.grey.shade400);
    }

    if (isMultipleChoice) {
      return hasVoted
          ? Icon(Icons.check_box_rounded, size: 18, color: color)
          : Icon(Icons.check_box_outline_blank_rounded,
              size: 18, color: Colors.grey.shade400);
    }

    return hasVoted
        ? Icon(Icons.radio_button_checked_rounded, size: 18, color: color)
        : Icon(Icons.radio_button_unchecked_rounded,
            size: 18, color: Colors.grey.shade400);
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

class _ExpiryRow extends StatelessWidget {
  final DateTime expiresAt;
  final bool isExpired;

  const _ExpiryRow({required this.expiresAt, required this.isExpired});

  String _timeLeft() {
    if (isExpired) return 'Đã kết thúc';
    final diff = expiresAt.difference(DateTime.now());
    if (diff.inDays > 0) return 'Còn ${diff.inDays} ngày';
    if (diff.inHours > 0) return 'Còn ${diff.inHours} giờ';
    if (diff.inMinutes > 0) return 'Còn ${diff.inMinutes} phút';
    return 'Sắp kết thúc';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isExpired ? Icons.lock_clock : Icons.timer_outlined,
          size: 12,
          color: Colors.white70,
        ),
        const SizedBox(width: 4),
        Text(
          _timeLeft(),
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';

/// AI-powered "generation gap" translator that rewrites a message
/// in the tone/style of a selected audience persona.
class TranslationDialog extends StatefulWidget {
  final String originalMessage;

  const TranslationDialog({
    super.key,
    required this.originalMessage,
  });

  @override
  State<TranslationDialog> createState() => _TranslationDialogState();
}

class _TranslationDialogState extends State<TranslationDialog>
    with SingleTickerProviderStateMixin {
  final AIBackendService _aiService = AIBackendService();

  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  String _selectedMode = 'elder';
  String? _translatedText;
  bool _isLoading = false;
  bool _copied = false;

  static const Map<String, _ModeInfo> _modes = {
    'elder': _ModeInfo(
      label: 'Người lớn tuổi',
      subtitle: 'Dễ hiểu, lễ phép, trang trọng',
      icon: Icons.elderly_rounded,
      color: Color(0xFF6366F1),
    ),
    'work': _ModeInfo(
      label: 'Công việc',
      subtitle: 'Chuyên nghiệp, súc tích, rõ ràng',
      icon: Icons.business_center_rounded,
      color: Color(0xFF0EA5E9),
    ),
    'student': _ModeInfo(
      label: 'Gen Z',
      subtitle: 'Trẻ trung, năng động, thân thiện',
      icon: Icons.emoji_emotions_rounded,
      color: Color(0xFFEC4899),
    ),
    'formal': _ModeInfo(
      label: 'Văn phong chính thức',
      subtitle: 'Hành chính, trang nghiêm',
      icon: Icons.gavel_rounded,
      color: Color(0xFF059669),
    ),
  };

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutBack,
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    setState(() {
      _isLoading = true;
      _translatedText = null;
      _copied = false;
    });

    final result = await _aiService.translateCommunication(
      widget.originalMessage,
      _selectedMode,
    );

    if (mounted) {
      setState(() {
        _translatedText = result ?? 'Có lỗi xảy ra khi dịch.';
        _isLoading = false;
      });
    }
  }

  Future<void> _copyResult() async {
    if (_translatedText == null) return;
    await Clipboard.setData(ClipboardData(text: _translatedText!));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _modes[_selectedMode]!;

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ─────────────────────────────────────────────
                _buildHeader(),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Mode selector ─────────────────────────────────
                      _buildModeSelector(),

                      const SizedBox(height: 16),

                      // ── Original message ──────────────────────────────
                      _buildOriginalCard(),

                      const SizedBox(height: 12),

                      // ── Result card ───────────────────────────────────
                      _buildResultCard(info),

                      const SizedBox(height: 20),

                      // ── Actions ───────────────────────────────────────
                      _buildActions(info),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dịch khoảng cách thế hệ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Chuyển đổi phong cách bằng AI',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8, top: 4),
          child: Text(
            'PHONG CÁCH',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1.0,
            ),
          ),
        ),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: _modes.entries.map((e) {
              final selected = _selectedMode == e.key;
              final info = e.value;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedMode = e.key;
                    _translatedText = null;
                    _copied = false;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? info.color.withOpacity(0.1)
                        : const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? info.color : const Color(0xFFE8EBF0),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(info.icon,
                          size: 20,
                          color:
                              selected ? info.color : const Color(0xFF9CA3AF)),
                      const SizedBox(height: 4),
                      Text(
                        info.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              selected ? info.color : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildOriginalCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EBF0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline_rounded,
                  size: 12, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 5),
              const Text(
                'TIN NHẮN GỐC',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.originalMessage,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF374151),
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(_ModeInfo info) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: info.color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: info.color.withOpacity(0.25), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 12, color: info.color),
                  const SizedBox(width: 5),
                  Text(
                    'KẾT QUẢ AI',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: info.color,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              if (_translatedText != null && !_isLoading)
                GestureDetector(
                  onTap: _copyResult,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _copied
                          ? Colors.green.withOpacity(0.1)
                          : info.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 12,
                          color: _copied ? Colors.green : info.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Đã sao chép' : 'Sao chép',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _copied ? Colors.green : info.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            _buildLoadingDots(info.color)
          else if (_translatedText != null)
            Text(
              _translatedText!,
              style: TextStyle(
                fontSize: 14,
                color: info.color,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Text(
              'Nhấn "Dịch AI" để chuyển đổi phong cách.',
              style: TextStyle(
                fontSize: 13,
                color: const Color(0xFF9CA3AF),
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingDots(Color color) {
    return _DotsLoader(color: color);
  }

  Widget _buildActions(_ModeInfo info) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE8EBF0), width: 1.5),
              ),
            ),
            child: const Text(
              'Đóng',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: !_isLoading
                  ? const LinearGradient(
                      colors: [Color(0xFF8A2387), Color(0xFFE94057)],
                    )
                  : null,
              color: _isLoading ? const Color(0xFFE8EBF0) : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isLoading ? null : _translate,
                borderRadius: BorderRadius.circular(14),
                child: Center(
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation(Color(0xFF9CA3AF)),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Dịch AI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        if (_translatedText != null && !_isLoading) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: info.color,
                boxShadow: [
                  BoxShadow(
                    color: info.color.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    Navigator.pop(context, _translatedText);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: const Center(
                    child: Text(
                      'Dùng câu này',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Mode metadata ────────────────────────────────────────────────────────────

class _ModeInfo {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _ModeInfo({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

// ── Loading dots ─────────────────────────────────────────────────────────────

class _DotsLoader extends StatefulWidget {
  final Color color;
  const _DotsLoader({required this.color});

  @override
  State<_DotsLoader> createState() => _DotsLoaderState();
}

class _DotsLoaderState extends State<_DotsLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Row(
          children: List.generate(3, (i) {
            final delay = i / 3;
            final t = ((_ctrl.value - delay) % 1.0);
            final opacity =
                (t < 0.5 ? t * 2 : 1.0 - (t - 0.5) * 2).clamp(0.3, 1.0);
            return Container(
              margin: const EdgeInsets.only(right: 6),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      ),
    );
  }
}

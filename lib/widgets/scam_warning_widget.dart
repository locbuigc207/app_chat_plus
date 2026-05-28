import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
//  ScamWarningWidget
//  Banner cảnh báo lừa đảo được nhúng dưới tin nhắn.
//  Hỗ trợ 3 cấp: WARNING_MONEY | WARNING_LINK | DANGER
//  + animation xuất hiện + nút thu gọn/mở rộng.
// ─────────────────────────────────────────────────────────────

enum _WarningLevel { money, link, danger, none }

class ScamWarningWidget extends StatefulWidget {
  /// 'WARNING_MONEY' | 'WARNING_LINK' | 'DANGER'
  final String status;

  /// Cho phép người dùng thu gọn banner (mặc định: true)
  final bool collapsible;

  const ScamWarningWidget({
    super.key,
    required this.status,
    this.collapsible = true,
  });

  @override
  State<ScamWarningWidget> createState() => _ScamWarningWidgetState();
}

class _ScamWarningWidgetState extends State<ScamWarningWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;
  bool _collapsed = false;

  // ── Parse status ──────────────────────────────────────────────
  _WarningLevel get _level {
    switch (widget.status) {
      case 'WARNING_MONEY':
        return _WarningLevel.money;
      case 'WARNING_LINK':
        return _WarningLevel.link;
      case 'DANGER':
        return _WarningLevel.danger;
      default:
        return _WarningLevel.none;
    }
  }

  // ── Visual config per level ──────────────────────────────────
  _LevelConfig get _config {
    switch (_level) {
      case _WarningLevel.money:
        return _LevelConfig(
          icon: Icons.account_balance_wallet_rounded,
          badgeLabel: 'CẢNH BÁO',
          title: 'Tin nhắn liên quan đến tiền bạc',
          body:
              'Có dấu hiệu mượn tiền hoặc chuyển khoản. Hãy gọi điện xác nhận danh tính trước khi thực hiện bất kỳ giao dịch nào!',
          mainColor: const Color(0xFFF57C00),
          bgColor: const Color(0xFFFFF8F0),
          borderColor: const Color(0xFFFFCC80),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF3E0), Color(0xFFFFFDE7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          tips: ['Gọi điện xác nhận', 'Không chuyển khoản vội'],
        );

      case _WarningLevel.link:
        return _LevelConfig(
          icon: Icons.link_off_rounded,
          badgeLabel: 'CẢNH BÁO',
          title: 'Phát hiện đường link đáng ngờ',
          body:
              'Không bấm vào đường link nếu không rõ nguồn gốc. Kẻ xấu có thể đánh cắp tài khoản hoặc cài mã độc vào thiết bị của bạn.',
          mainColor: const Color(0xFF6A1B9A),
          bgColor: const Color(0xFFF5F0FF),
          borderColor: const Color(0xFFCE93D8),
          gradient: const LinearGradient(
            colors: [Color(0xFFF3E5F5), Color(0xFFEDE7F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          tips: ['Không bấm link', 'Kiểm tra URL kỹ'],
        );

      case _WarningLevel.danger:
        return _LevelConfig(
          icon: Icons.gpp_bad_rounded,
          badgeLabel: 'NGUY HIỂM',
          title: 'Dấu hiệu lừa đảo nghiêm trọng!',
          body:
              'Tin nhắn có khả năng cao là lừa đảo chiếm đoạt tài sản. Đừng làm theo hướng dẫn. Hãy chặn liên hệ này và báo cáo ngay!',
          mainColor: const Color(0xFFC62828),
          bgColor: const Color(0xFFFFF5F5),
          borderColor: const Color(0xFFEF9A9A),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFEBEE), Color(0xFFFCE4EC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          tips: ['Chặn ngay', 'Báo cáo lừa đảo', 'Gọi 113 nếu cần'],
          isDanger: true,
        );

      case _WarningLevel.none:
        return _LevelConfig(
          icon: Icons.info,
          badgeLabel: '',
          title: '',
          body: '',
          mainColor: Colors.grey,
          bgColor: Colors.transparent,
          borderColor: Colors.transparent,
          gradient: const LinearGradient(
              colors: [Colors.transparent, Colors.transparent]),
          tips: [],
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<double>(begin: -12, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    if (_level != _WarningLevel.none) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_level == _WarningLevel.none) return const SizedBox.shrink();

    final cfg = _config;

    return FadeTransition(
      opacity: _fadeAnim,
      child: AnimatedBuilder(
        animation: _slideAnim,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _slideAnim.value),
          child: child,
        ),
        child: Container(
          margin: const EdgeInsets.only(top: 6, bottom: 4),
          decoration: BoxDecoration(
            gradient: cfg.gradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cfg.borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: cfg.mainColor.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Top accent bar ──────────────────────────────
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: cfg.mainColor,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                // ── Header row ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
                  child: Row(
                    children: [
                      // Icon container
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cfg.mainColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(cfg.icon, color: cfg.mainColor, size: 22),
                      ),
                      const SizedBox(width: 10),
                      // Badge + title
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cfg.mainColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                cfg.badgeLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              cfg.title,
                              style: TextStyle(
                                color: cfg.mainColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Collapse toggle
                      if (widget.collapsible)
                        GestureDetector(
                          onTap: () => setState(() => _collapsed = !_collapsed),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: cfg.mainColor.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: AnimatedRotation(
                              turns: _collapsed ? 0.5 : 0,
                              duration: const Duration(milliseconds: 250),
                              child: Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: cfg.mainColor,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Collapsible body ─────────────────────────────
                AnimatedCrossFade(
                  firstChild: const SizedBox(height: 0),
                  secondChild: _buildBody(cfg),
                  crossFadeState: _collapsed
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  duration: const Duration(milliseconds: 280),
                  sizeCurve: Curves.easeInOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(_LevelConfig cfg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: cfg.borderColor, height: 1),
          const SizedBox(height: 10),
          // Body text
          Text(
            cfg.body,
            style: TextStyle(
              color: cfg.mainColor.withOpacity(0.85),
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          // Tips chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: cfg.tips
                .map((tip) => _TipChip(tip: tip, color: cfg.mainColor))
                .toList(),
          ),
          // Extra CTA for danger
          if (cfg.isDanger) ...[
            const SizedBox(height: 12),
            _DangerActions(color: cfg.mainColor),
          ],
        ],
      ),
    );
  }
}

// ── Tip chip ─────────────────────────────────────────────────
class _TipChip extends StatelessWidget {
  final String tip;
  final Color color;
  const _TipChip({required this.tip, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            tip,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Danger action buttons ────────────────────────────────────
class _DangerActions extends StatelessWidget {
  final Color color;
  const _DangerActions({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionBtn(
            label: 'Chặn & Xoá',
            icon: Icons.block_rounded,
            color: color,
            onTap: () {},
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionBtn(
            label: 'Báo cáo',
            icon: Icons.flag_rounded,
            color: color,
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.30),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Level config data class ──────────────────────────────────
class _LevelConfig {
  final IconData icon;
  final String badgeLabel;
  final String title;
  final String body;
  final Color mainColor;
  final Color bgColor;
  final Color borderColor;
  final LinearGradient gradient;
  final List<String> tips;
  final bool isDanger;

  const _LevelConfig({
    required this.icon,
    required this.badgeLabel,
    required this.title,
    required this.body,
    required this.mainColor,
    required this.bgColor,
    required this.borderColor,
    required this.gradient,
    required this.tips,
    this.isDanger = false,
  });
}

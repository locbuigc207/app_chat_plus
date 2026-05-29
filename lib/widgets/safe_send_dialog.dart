import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum SafeSendLevel { warning, danger }

class SafeSendDialog extends StatefulWidget {
  final String title;
  final String content;
  final IconData icon;

  final SafeSendLevel level;

  final String confirmLabel;

  final String cancelLabel;

  const SafeSendDialog({
    super.key,
    required this.title,
    required this.content,
    required this.icon,
    this.level = SafeSendLevel.warning,
    this.confirmLabel = 'VÂNG, GỬI ĐI',
    this.cancelLabel = 'KHÔNG, TÔI BẤM NHẦM',
  });

  factory SafeSendDialog.money() => const SafeSendDialog(
        title: 'Xác nhận chuyển tiền?',
        content:
            'Tin nhắn của bạn có liên quan đến chuyển khoản hoặc mượn tiền.\nHãy chắc chắn bạn đang liên hệ đúng người!',
        icon: Icons.account_balance_wallet_rounded,
        level: SafeSendLevel.warning,
      );

  factory SafeSendDialog.link() => const SafeSendDialog(
        title: 'Gửi đường link lạ?',
        content:
            'Tin nhắn chứa đường link chưa được xác minh.\nNgười nhận có thể bị lừa đảo nếu bấm vào.',
        icon: Icons.link_off_rounded,
        level: SafeSendLevel.warning,
      );

  factory SafeSendDialog.danger() => const SafeSendDialog(
        title: 'NGUY HIỂM!',
        content: 'Nội dung này có dấu hiệu lừa đảo nghiêm trọng.\nBạn có chắc chắn muốn gửi không?',
        icon: Icons.gpp_bad_rounded,
        level: SafeSendLevel.danger,
        confirmLabel: 'TÔI HIỂU, VẪN GỬI',
        cancelLabel: 'DỪNG LẠI, KHÔNG GỬI',
      );

  @override
  State<SafeSendDialog> createState() => _SafeSendDialogState();
}

class _SafeSendDialogState extends State<SafeSendDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _iconBounce;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    _scaleAnim = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.elasticOut,
    );

    _fadeAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    );

    _iconBounce = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.15), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 0.95), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward();

    if (widget.level == SafeSendLevel.danger) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _primaryColor =>
      widget.level == SafeSendLevel.danger ? const Color(0xFFE53935) : const Color(0xFFF57C00);

  Color get _accentLight =>
      widget.level == SafeSendLevel.danger ? const Color(0xFFFFEBEE) : const Color(0xFFFFF3E0);

  Color get _confirmBg =>
      widget.level == SafeSendLevel.danger ? const Color(0xFFE53935) : const Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 4,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                  child: Column(
                    children: [
                      _buildTitle(),
                      const SizedBox(height: 12),
                      _buildContent(),
                      const SizedBox(height: 28),
                      _buildConfirmButton(),
                      const SizedBox(height: 12),
                      _buildCancelButton(),
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: _accentLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _iconBounce,
            builder: (_, child) => Transform.scale(
              scale: _iconBounce.value,
              child: child,
            ),
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryColor.withValues(alpha: 0.12),
                border: Border.all(color: _primaryColor.withValues(alpha: 0.30), width: 2.5),
              ),
              child: Icon(widget.icon, size: 48, color: _primaryColor),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: _primaryColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.level == SafeSendLevel.danger ? '⚠ MỨC NGUY HIỂM CAO' : '⚠ CẢNH BÁO',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      widget.title,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: _primaryColor,
        height: 1.25,
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        widget.content,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF455A64),
          height: 1.55,
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _confirmBg,
          foregroundColor: Colors.white,
          elevation: 3,
          shadowColor: _confirmBg.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(
          widget.level == SafeSendLevel.danger ? Icons.send_rounded : Icons.check_circle_rounded,
          size: 20,
        ),
        label: Text(
          widget.confirmLabel,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        onPressed: () {
          HapticFeedback.selectionClick();
          Navigator.pop(context, true);
        },
      ),
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: Colors.grey.shade700,
          backgroundColor: Colors.grey.shade100,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.cancel_outlined, size: 18),
        label: Text(
          widget.cancelLabel,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.pop(context, false);
        },
      ),
    );
  }
}

Future<bool> showSafeSendDialog(BuildContext context, SafeSendDialog dialog) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => dialog,
  );
  return result ?? false;
}

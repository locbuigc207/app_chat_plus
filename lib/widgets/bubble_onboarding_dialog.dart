// lib/widgets/bubble_onboarding_dialog.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bubble_permission_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BubbleOnboardingDialog
// ─────────────────────────────────────────────────────────────────────────────

/// Dialog hướng dẫn người dùng bật Bubble permission theo OEM.
///
/// Hiển thị các bước cụ thể được lấy từ [OemCompatHelper.getBubbleSetupSteps()]
/// qua Native → [BubblePermissionService._getBubbleSetupSteps()].
///
/// Trả về [true] khi người dùng xác nhận đã thực hiện xong (nút "Đã xong"),
/// [false] khi người dùng chọn "Để sau" hoặc đóng dialog.
///
/// Cách dùng:
/// ```dart
/// final granted = await BubblePermissionService.instance.requestIfNeeded(
///   onShowDialog: (status, oemName, steps) async {
///     return await showDialog<bool>(
///       context: context,
///       barrierDismissible: false,
///       builder: (_) => BubbleOnboardingDialog(
///         status: status,
///         oemName: oemName,
///         setupSteps: steps,
///       ),
///     ) ?? false;
///   },
/// );
/// ```
class BubbleOnboardingDialog extends StatefulWidget {
  final BubblePermissionStatus status;
  final String oemName;
  final List<String> setupSteps;

  const BubbleOnboardingDialog({
    super.key,
    required this.status,
    required this.oemName,
    required this.setupSteps,
  });

  @override
  State<BubbleOnboardingDialog> createState() => _BubbleOnboardingDialogState();
}

class _BubbleOnboardingDialogState extends State<BubbleOnboardingDialog>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  bool _isOpeningSettings = false;
  bool _isCheckingPermission = false;
  bool _settingsOpened = false;
  late AnimationController _checkAnim;
  late Animation<double> _checkScale;

  // Ánh xạ status → icon và màu
  static const Map<BubblePermissionStatus, IconData> _statusIcons = {
    BubblePermissionStatus.notificationDisabled:
        Icons.notifications_off_outlined,
    BubblePermissionStatus.bubbleChannelDisabled: Icons.chat_bubble_outline,
    BubblePermissionStatus.batteryNotWhitelisted: Icons.battery_alert_outlined,
    BubblePermissionStatus.unknown: Icons.help_outline,
  };

  static const Map<BubblePermissionStatus, Color> _statusColors = {
    BubblePermissionStatus.notificationDisabled: Color(0xFFE53935),
    BubblePermissionStatus.bubbleChannelDisabled: Color(0xFF6366F1),
    BubblePermissionStatus.batteryNotWhitelisted: Color(0xFFFF8F00),
    BubblePermissionStatus.unknown: Color(0xFF757575),
  };

  @override
  void initState() {
    super.initState();
    _checkAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _checkScale = CurvedAnimation(parent: _checkAnim, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _checkAnim.dispose();
    super.dispose();
  }

  // ─── Getters ──────────────────────────────────────────────────────────

  Color get _accentColor =>
      _statusColors[widget.status] ?? const Color(0xFF6366F1);

  IconData get _headerIcon =>
      _statusIcons[widget.status] ?? Icons.chat_bubble_outline;

  String get _title => switch (widget.status) {
    BubblePermissionStatus.notificationDisabled => 'Bật thông báo cho ứng dụng',
    BubblePermissionStatus.bubbleChannelDisabled => 'Bật bong bóng chat',
    BubblePermissionStatus.batteryNotWhitelisted => 'Đảm bảo nhận tin nhắn',
    _ => 'Bật bong bóng chat',
  };

  String get _subtitle {
    final oemNote = widget.oemName != 'Android'
        ? ' trên ${widget.oemName}'
        : '';
    return switch (widget.status) {
      BubblePermissionStatus.notificationDisabled =>
        'Thông báo bị tắt$oemNote. Bật để nhận tin nhắn kịp thời.',
      BubblePermissionStatus.bubbleChannelDisabled =>
        'Bong bóng chat chưa được bật$oemNote. '
            'Làm theo các bước dưới đây:',
      BubblePermissionStatus.batteryNotWhitelisted =>
        'Ứng dụng đang bị giới hạn pin$oemNote, '
            'có thể khiến bạn không nhận được tin nhắn khi màn hình tắt.',
      _ => 'Làm theo các bước dưới đây để bật bong bóng chat:',
    };
  }

  bool get _hasMultipleSteps => widget.setupSteps.length > 1;

  bool get _isLastStep => _currentStep >= widget.setupSteps.length - 1;

  String? get _settingsActionLabel {
    if (widget.setupSteps.isEmpty) return null;
    return switch (widget.status) {
      BubblePermissionStatus.notificationDisabled => 'Mở cài đặt thông báo',
      BubblePermissionStatus.batteryNotWhitelisted => 'Mở cài đặt pin',
      _ => 'Mở cài đặt',
    };
  }

  // ─── Actions ─────────────────────────────────────────────────────────

  Future<void> _openSettings() async {
    if (_isOpeningSettings) return;
    setState(() => _isOpeningSettings = true);

    try {
      switch (widget.status) {
        case BubblePermissionStatus.notificationDisabled:
          await BubblePermissionService.instance.openBubbleSettings();
        case BubblePermissionStatus.batteryNotWhitelisted:
          if (_currentStep == 0) {
            await BubblePermissionService.instance.openBatteryWhitelist();
          } else {
            await BubblePermissionService.instance.openAutoStartSettings();
          }
        default:
          await BubblePermissionService.instance.openBubbleSettings();
      }
      setState(() => _settingsOpened = true);
    } finally {
      if (mounted) setState(() => _isOpeningSettings = false);
    }
  }

  Future<void> _checkPermission() async {
    if (_isCheckingPermission) return;
    setState(() => _isCheckingPermission = true);

    // Delay nhỏ để user có thời gian quay về từ Settings
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    final isEnabled = await BubblePermissionService.instance.isChannelEnabled();

    if (!mounted) return;
    setState(() => _isCheckingPermission = false);

    if (isEnabled) {
      _checkAnim.forward();
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop(true);
    } else {
      // Chưa được bật — nhắc lại
      _showNotYetSnackBar();
    }
  }

  void _showNotYetSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Chưa bật được bong bóng. Hãy thử lại theo hướng dẫn.',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF323232),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _nextStep() {
    if (!_isLastStep) {
      setState(() {
        _currentStep++;
        _settingsOpened = false;
      });
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _settingsOpened = false;
      });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(isDark),
              _buildBody(theme, isDark),
              _buildActions(theme, isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _accentColor.withAlpha(isDark ? 40 : 20),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        children: [
          // Animated check overlay hoặc status icon
          ScaleTransition(
            scale: _checkScale,
            child: AnimatedBuilder(
              animation: _checkAnim,
              builder: (_, __) {
                if (_checkAnim.value > 0.5) {
                  return Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF4CAF50),
                      size: 40,
                    ),
                  );
                }
                return Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _accentColor.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_headerIcon, color: _accentColor, size: 36),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: isDark
                  ? Colors.white.withAlpha(178)
                  : const Color(0xFF555577),
              height: 1.5,
            ),
          ),
          // OEM badge
          if (widget.oemName != 'Android') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _accentColor.withAlpha(isDark ? 60 : 25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accentColor.withAlpha(80)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.phone_android_rounded,
                    size: 12,
                    color: _accentColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.oemName,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _accentColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Body — step list ────────────────────────────────────────────────────

  Widget _buildBody(ThemeData theme, bool isDark) {
    if (widget.setupSteps.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step counter nếu nhiều bước
          if (_hasMultipleSteps) ...[
            _buildStepIndicator(isDark),
            const SizedBox(height: 16),
          ],
          // Nội dung bước hiện tại
          _buildCurrentStep(isDark),
          // Dot indicator
          if (_hasMultipleSteps) ...[
            const SizedBox(height: 20),
            _buildDotIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildStepIndicator(bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _accentColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Bước ${_currentStep + 1}/${widget.setupSteps.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _isLastStep ? 'Bước cuối cùng' : 'Tiếp tục theo hướng dẫn',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? Colors.white.withAlpha(120)
                  : const Color(0xFF888888),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStep(bool isDark) {
    final step = widget.setupSteps[_currentStep];
    // Tô sáng các chuỗi quan trọng (trong dấu → và tên màn hình)
    final parts = _splitStepText(step);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(_currentStep),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withAlpha(12)
              : _accentColor.withAlpha(12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accentColor.withAlpha(isDark ? 60 : 40)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: _accentColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${_currentStep + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: parts
                      .map(
                        (p) => TextSpan(
                          text: p.text,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.55,
                            fontWeight: p.isHighlight
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: p.isHighlight
                                ? _accentColor
                                : (isDark
                                      ? Colors.white.withAlpha(220)
                                      : const Color(0xFF222244)),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDotIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.setupSteps.length, (i) {
        final isActive = i == _currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 20 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: isActive ? _accentColor : _accentColor.withAlpha(70),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Widget _buildActions(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          // Nút mở Settings (chỉ hiện nếu có label)
          if (_settingsActionLabel != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isOpeningSettings ? null : _openSettings,
                icon: _isOpeningSettings
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withAlpha(200),
                        ),
                      )
                    : Icon(
                        _settingsOpened
                            ? Icons.settings_rounded
                            : Icons.open_in_new_rounded,
                        size: 18,
                      ),
                label: Text(
                  _isOpeningSettings
                      ? 'Đang mở...'
                      : (_settingsOpened
                            ? 'Mở lại cài đặt'
                            : _settingsActionLabel!),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _accentColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Row: nút điều hướng bước + Đã xong / Để sau
          Row(
            children: [
              // Nút quay lại (chỉ khi đang ở bước > 0)
              if (_hasMultipleSteps && _currentStep > 0) ...[
                SizedBox(
                  height: 42,
                  child: OutlinedButton(
                    onPressed: _prevStep,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: BorderSide(color: _accentColor.withAlpha(100)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: _accentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Nút "Để sau"
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark
                          ? Colors.white.withAlpha(150)
                          : const Color(0xFF888888),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Để sau', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Nút Tiếp theo / Đã xong
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 42,
                  child: _hasMultipleSteps && !_isLastStep
                      ? _buildNextButton()
                      : _buildDoneButton(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    return OutlinedButton.icon(
      onPressed: _nextStep,
      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      label: const Text(
        'Tiếp theo',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _accentColor,
        side: BorderSide(color: _accentColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildDoneButton() {
    return FilledButton.icon(
      onPressed: _isCheckingPermission ? null : _checkPermission,
      icon: _isCheckingPermission
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.check_rounded, size: 16),
      label: Text(
        _isCheckingPermission ? 'Đang kiểm tra...' : 'Đã xong',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: _accentColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── Text Parser ─────────────────────────────────────────────────────────

  /// Tách chuỗi hướng dẫn ra thành các đoạn thường và đoạn nổi bật.
  /// Các phần sau dấu → và tên màn hình (in hoa đầu) được tô đậm.
  List<_TextPart> _splitStepText(String text) {
    final List<_TextPart> parts = [];
    // Split tại dấu → để tô màu từng segment sau mũi tên
    final segments = text.split('→');
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        parts.add(const _TextPart('→ ', false));
      }
      final seg = segments[i].trim();
      if (seg.isEmpty) continue;

      if (i == segments.length - 1 && segments.length > 1) {
        // Segment cuối cùng sau dấu → là điểm đến — tô đậm
        parts.add(_TextPart(seg, true));
      } else if (i == 0) {
        parts.add(_TextPart(seg, false));
      } else {
        // Segment giữa — tô đậm vừa phải
        parts.add(_TextPart(seg, true));
      }
    }
    return parts.isEmpty ? [_TextPart(text, false)] : parts;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────────────────────

class _TextPart {
  final String text;
  final bool isHighlight;
  const _TextPart(this.text, this.isHighlight);
}

// ─────────────────────────────────────────────────────────────────────────────
// BubblePermissionBanner
// ─────────────────────────────────────────────────────────────────────────────

/// Banner nhỏ hiển thị nội tuyến khi bubble permission bị mất/chưa bật.
/// Dùng trong HomeScreen hoặc nơi phù hợp để không intrusive.
///
/// Cách dùng:
/// ```dart
/// StreamBuilder<BubblePermissionStatus>(
///   stream: BubblePermissionService.instance.statusStream,
///   builder: (ctx, snap) {
///     final status = snap.data ?? BubblePermissionStatus.unknown;
///     if (status.isReady || status.isHardBlocked) return const SizedBox.shrink();
///     return BubblePermissionBanner(status: status);
///   },
/// )
/// ```
class BubblePermissionBanner extends StatelessWidget {
  final BubblePermissionStatus status;
  final VoidCallback? onTap;

  const BubblePermissionBanner({super.key, required this.status, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (status.isReady || status.isHardBlocked) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentColor = Color(0xFF6366F1);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? accentColor.withAlpha(30) : accentColor.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              color: accentColor,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Bong bóng chat chưa hoạt động',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                  Text(
                    status.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withAlpha(150)
                          : const Color(0xFF666688),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: accentColor.withAlpha(180),
            ),
          ],
        ),
      ),
    );
  }
}

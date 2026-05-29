import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/auto_delete_provider.dart';

class AutoDeleteSettingsDialog extends StatefulWidget {
  final String conversationId;
  final AutoDeleteProvider provider;

  const AutoDeleteSettingsDialog({
    super.key,
    required this.conversationId,
    required this.provider,
  });

  @override
  State<AutoDeleteSettingsDialog> createState() => _AutoDeleteSettingsDialogState();
}

class _AutoDeleteSettingsDialogState extends State<AutoDeleteSettingsDialog> {
  AutoDeleteDuration _selectedDuration = AutoDeleteDuration.never;
  final _customCtrl = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  static const _options = [
    (
      AutoDeleteDuration.never,
      Icons.all_inclusive_rounded,
      'Không bao giờ',
      'Tin nhắn được giữ mãi mãi'
    ),
    (AutoDeleteDuration.oneDay, Icons.today_rounded, 'Sau 24 giờ', 'Tin nhắn tự xóa sau 1 ngày'),
    (
      AutoDeleteDuration.sevenDays,
      Icons.date_range_rounded,
      'Sau 7 ngày',
      'Tin nhắn tự xóa sau 1 tuần'
    ),
    (
      AutoDeleteDuration.thirtyDays,
      Icons.calendar_month_rounded,
      'Sau 30 ngày',
      'Tin nhắn tự xóa sau 1 tháng'
    ),
    (AutoDeleteDuration.custom, Icons.tune_rounded, 'Tuỳ chỉnh', 'Chọn số giờ theo ý muốn'),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await widget.provider.getAutoDeleteSettings(widget.conversationId);
    if (!mounted) return;

    if (settings != null && settings.enabled == true) {
      final duration = settings.duration as int?;
      if (duration != null) {
        AutoDeleteDuration d = AutoDeleteDuration.custom;
        if (duration == 24 * 3600000) {
          d = AutoDeleteDuration.oneDay;
        } else if (duration == 7 * 24 * 3600000) {
          d = AutoDeleteDuration.sevenDays;
        } else if (duration == 30 * 24 * 3600000) {
          d = AutoDeleteDuration.thirtyDays;
        } else {
          d = AutoDeleteDuration.custom;
          _customCtrl.text = (duration ~/ 3600000).toString();
        }
        setState(() => _selectedDuration = d);
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (_selectedDuration == AutoDeleteDuration.custom) {
      final hours = int.tryParse(_customCtrl.text);
      if (hours == null || hours <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng nhập số giờ hợp lệ')),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    final customHours =
        _selectedDuration == AutoDeleteDuration.custom ? int.tryParse(_customCtrl.text) : null;

    final success = await widget.provider.setAutoDelete(
      conversationId: widget.conversationId,
      duration: _selectedDuration,
      customHours: customHours,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Đã cập nhật cài đặt tự xóa'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lưu thất bại, thử lại sau')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_delete_rounded, color: Colors.red, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tự xóa tin nhắn',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87),
                        ),
                        Text(
                          'Chọn thời gian tự động xóa',
                          style: TextStyle(
                              fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: isDark ? Colors.white38 : Colors.grey.shade400),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(
                height: 1,
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade100),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Column(
                    children: [
                      ..._options.map((opt) {
                        final (duration, icon, label, subtitle) = opt;
                        return _buildOption(isDark, duration, icon, label, subtitle);
                      }),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        child: _selectedDuration == AutoDeleteDuration.custom
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.07)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: ColorConstants.primaryColor.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 14),
                                      const Icon(Icons.schedule_rounded,
                                          size: 18, color: ColorConstants.primaryColor),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          controller: _customCtrl,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          style: TextStyle(
                                              color: isDark ? Colors.white : Colors.black87),
                                          decoration: InputDecoration(
                                            hintText: 'Số giờ (vd: 48)',
                                            hintStyle: TextStyle(color: Colors.grey.shade400),
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(vertical: 14),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(right: 14),
                                        child: Text('giờ',
                                            style: TextStyle(color: Colors.grey.shade500)),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            Divider(
                height: 1,
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Huỷ',
                          style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ColorConstants.primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Lưu', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
      bool isDark, AutoDeleteDuration duration, IconData icon, String label, String subtitle) {
    final isSelected = _selectedDuration == duration;

    return InkWell(
      onTap: () => setState(() => _selectedDuration = duration),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:
              isSelected ? ColorConstants.primaryColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? ColorConstants.primaryColor.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected
                    ? ColorConstants.primaryColor.withValues(alpha: 0.15)
                    : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 19, color: isSelected ? ColorConstants.primaryColor : Colors.grey.shade500),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? ColorConstants.primaryColor
                              : (isDark ? Colors.white : Colors.black87))),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade500)),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isSelected
                  ? Container(
                      key: const ValueKey('check'),
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: ColorConstants.primaryColor),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
                    )
                  : Container(
                      key: const ValueKey('empty'),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

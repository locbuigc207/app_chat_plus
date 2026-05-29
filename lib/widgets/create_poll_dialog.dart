import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CreatePollDialog extends StatefulWidget {
  final void Function(
    String question,
    List<String> options, {
    bool isMultipleChoice,
    bool isAnonymous,
    DateTime? expiresAt,
  }) onCreate;

  const CreatePollDialog({super.key, required this.onCreate});

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> with SingleTickerProviderStateMixin {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<FocusNode> _optionFocusNodes = [FocusNode(), FocusNode()];
  final _scrollController = ScrollController();

  bool _isMultipleChoice = false;
  bool _isAnonymous = false;
  bool _hasExpiry = false;
  DateTime? _expiresAt;
  bool _questionHasError = false;
  bool _optionHasError = false;

  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  static const int _maxOptions = 10;
  static const _primary = Color(0xFF6C63FF);
  static const _primaryLight = Color(0xFFEEEDFE);
  static const _textDark = Color(0xFF1A1A2E);
  static const _textMuted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);
  static const _surface = Color(0xFFF9FAFB);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _questionController.dispose();
    _scrollController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    for (final f in _optionFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= _maxOptions) {
      _showSnack('Tối đa $_maxOptions lựa chọn', isError: true);
      return;
    }
    setState(() {
      _optionControllers.add(TextEditingController());
      _optionFocusNodes.add(FocusNode());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      _optionFocusNodes.last.requestFocus();
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      _showSnack('Cần ít nhất 2 lựa chọn', isError: true);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _optionControllers[index].dispose();
      _optionFocusNodes[index].dispose();
      _optionControllers.removeAt(index);
      _optionFocusNodes.removeAt(index);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    HapticFeedback.selectionClick();
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final c = _optionControllers.removeAt(oldIndex);
      final f = _optionFocusNodes.removeAt(oldIndex);
      _optionControllers.insert(newIndex, c);
      _optionFocusNodes.insert(newIndex, f);
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(message, style: const TextStyle(fontSize: 14)),
            ],
          ),
          backgroundColor: isError ? const Color(0xFFEF4444) : _primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Chọn ngày kết thúc',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primary,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
      helpText: 'Chọn giờ kết thúc',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    setState(() {
      _expiresAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 23,
        time?.minute ?? 59,
      );
    });
  }

  void _handleCreate() {
    final question = _questionController.text.trim();
    final options =
        _optionControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

    bool hasError = false;
    if (question.isEmpty) {
      setState(() => _questionHasError = true);
      _showSnack('Vui lòng nhập câu hỏi bình chọn', isError: true);
      hasError = true;
    }
    if (options.length < 2) {
      setState(() => _optionHasError = true);
      _showSnack('Cần ít nhất 2 lựa chọn hợp lệ', isError: true);
      hasError = true;
    }
    if (hasError) return;

    HapticFeedback.mediumImpact();
    widget.onCreate(
      question,
      options,
      isMultipleChoice: _isMultipleChoice,
      isAnonymous: _isAnonymous,
      expiresAt: _hasExpiry ? _expiresAt : null,
    );

    Navigator.of(context).pop();
  }

  Future<void> _dismissDialog() async {
    await _animController.reverse();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: mq.padding.top + 12,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: mq.size.height * 0.92,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.12),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  Flexible(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          _buildSectionLabel(
                            icon: Icons.help_outline_rounded,
                            label: 'Câu hỏi',
                          ),
                          const SizedBox(height: 8),
                          _buildQuestionField(),
                          const SizedBox(height: 24),
                          _buildOptionsSectionHeader(),
                          const SizedBox(height: 10),
                          _buildOptionsList(),
                          const SizedBox(height: 8),
                          _buildAddOptionButton(),
                          const SizedBox(height: 24),
                          _buildSectionLabel(
                            icon: Icons.tune_rounded,
                            label: 'Cài đặt',
                          ),
                          const SizedBox(height: 10),
                          _buildSettingsCard(),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
      decoration: const BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.poll_rounded,
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
                  'Tạo bình chọn',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Thu thập ý kiến từ mọi người trong nhóm',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _dismissDialog,
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
            splashRadius: 20,
            tooltip: 'Đóng',
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textDark,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionField() {
    return TextField(
      controller: _questionController,
      maxLines: 3,
      minLines: 1,
      maxLength: 200,
      onChanged: (_) {
        if (_questionHasError) setState(() => _questionHasError = false);
      },
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: _textDark,
        height: 1.4,
      ),
      decoration: InputDecoration(
        hintText: 'Nhập câu hỏi bình chọn…',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor:
            _questionHasError ? const Color(0xFFFEF2F2) : _primaryLight.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _questionHasError ? const Color(0xFFEF4444) : Colors.transparent,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _questionHasError ? const Color(0xFFEF4444) : _primary,
            width: 1.5,
          ),
        ),
        counterStyle: const TextStyle(fontSize: 11, color: _textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildOptionsSectionHeader() {
    final count = _optionControllers.length;
    return Row(
      children: [
        const Icon(Icons.format_list_bulleted_rounded, size: 16, color: _primary),
        const SizedBox(width: 6),
        const Text(
          'Lựa chọn',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textDark,
          ),
        ),
        const Spacer(),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: count >= _maxOptions ? const Color(0xFFFEF3C7) : _primaryLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count / $_maxOptions',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: count >= _maxOptions ? const Color(0xFFD97706) : _primary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Kéo để sắp xếp',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
      ],
    );
  }

  Widget _buildOptionsList() {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _optionControllers.length,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (_, child) => Material(
            elevation: 6 * animation.value,
            shadowColor: _primary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
          child: child,
        );
      },
      onReorder: _onReorder,
      itemBuilder: (ctx, index) {
        return _OptionTile(
          key: ValueKey('option_${_optionControllers[index].hashCode}_$index'),
          index: index,
          controller: _optionControllers[index],
          focusNode: _optionFocusNodes[index],
          totalOptions: _optionControllers.length,
          hasError: _optionHasError,
          onRemove: () => _removeOption(index),
          onChanged: (_) {
            if (_optionHasError) setState(() => _optionHasError = false);
          },
          onSubmitted: (_) {
            if (index < _optionControllers.length - 1) {
              _optionFocusNodes[index + 1].requestFocus();
            } else {
              _addOption();
            }
          },
        );
      },
    );
  }

  Widget _buildAddOptionButton() {
    if (_optionControllers.length >= _maxOptions) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _addOption,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: _primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
          color: _primaryLight.withValues(alpha: 0.4),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline_rounded, color: _primary, size: 18),
            SizedBox(width: 6),
            Text(
              'Thêm lựa chọn',
              style: TextStyle(
                color: _primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          _SettingTile(
            icon: Icons.check_box_outlined,
            iconBg: const Color(0xFFEEEDFE),
            iconColor: _primary,
            title: 'Chọn nhiều đáp án',
            subtitle: 'Cho phép bình chọn nhiều lựa chọn cùng lúc',
            value: _isMultipleChoice,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _isMultipleChoice = v);
            },
          ),
          _buildDivider(),
          _SettingTile(
            icon: Icons.visibility_off_outlined,
            iconBg: const Color(0xFFE0F2FE),
            iconColor: const Color(0xFF0284C7),
            title: 'Bình chọn ẩn danh',
            subtitle: 'Không hiện danh sách người đã bình chọn',
            value: _isAnonymous,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _isAnonymous = v);
            },
          ),
          _buildDivider(),
          _SettingTile(
            icon: Icons.timer_outlined,
            iconBg: const Color(0xFFFEF2F2),
            iconColor: const Color(0xFFEF4444),
            title: 'Đặt thời hạn',
            subtitle: _hasExpiry && _expiresAt != null
                ? _formatExpiry(_expiresAt!)
                : 'Tự động đóng bình chọn theo giờ',
            value: _hasExpiry,
            onChanged: (v) async {
              HapticFeedback.selectionClick();
              setState(() => _hasExpiry = v);
              if (v) {
                await _pickExpiryDate();

                if (_expiresAt == null && mounted) {
                  setState(() => _hasExpiry = false);
                }
              } else {
                setState(() => _expiresAt = null);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => Divider(
        height: 1,
        indent: 14,
        endIndent: 14,
        color: _border,
      );

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _dismissDialog,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: _border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Hủy',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _CreateButton(onTap: _handleCreate),
          ),
        ],
      ),
    );
  }

  String _formatExpiry(DateTime dt) {
    final weekdays = ['', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return '${weekdays[dt.weekday]}, '
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _OptionTile extends StatefulWidget {
  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int totalOptions;
  final bool hasError;
  final VoidCallback onRemove;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _OptionTile({
    super.key,
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.totalOptions,
    required this.hasError,
    required this.onRemove,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  static const _primary = Color(0xFF6C63FF);
  static const _primaryLight = Color(0xFFEEEDFE);

  static const _indexColors = [
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

  Color get _indexColor => _indexColors[widget.index % _indexColors.length];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.drag_indicator_rounded,
                color: Colors.grey.shade300,
                size: 22,
              ),
            ),
          ),
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _indexColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${widget.index + 1}',
              style: TextStyle(
                color: _indexColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              maxLength: 100,
              textInputAction: TextInputAction.next,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Lựa chọn ${widget.index + 1}',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: widget.hasError && widget.controller.text.isEmpty
                    ? const Color(0xFFFEF2F2)
                    : _primaryLight.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _indexColor, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: widget.hasError && widget.controller.text.isEmpty
                      ? const BorderSide(color: Color(0xFFEF4444), width: 1.5)
                      : BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                counterText: '',
                suffixIcon: widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
                        onPressed: () {
                          widget.controller.clear();
                          widget.onChanged('');
                        },
                        splashRadius: 14,
                      )
                    : null,
              ),
            ),
          ),
          if (widget.totalOptions > 2) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: widget.onRemove,
              icon: Icon(
                Icons.remove_circle_outline_rounded,
                size: 20,
                color: Colors.grey.shade400,
              ),
              splashRadius: 16,
              tooltip: 'Xóa lựa chọn',
            ),
          ] else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF6C63FF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateButton extends StatefulWidget {
  final VoidCallback onTap;

  const _CreateButton({required this.onTap});

  @override
  State<_CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<_CreateButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () => _controller.reverse(),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.poll_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Tạo bình chọn',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

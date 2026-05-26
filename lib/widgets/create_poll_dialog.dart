import 'package:flutter/material.dart';

class CreatePollDialog extends StatefulWidget {
  final Function(String question, List<String> options,
      {bool isMultipleChoice, bool isAnonymous, DateTime? expiresAt}) onCreate;

  const CreatePollDialog({super.key, required this.onCreate});

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<FocusNode> _focusNodes = [FocusNode(), FocusNode()];
  final _formKey = GlobalKey<FormState>();

  bool _isMultipleChoice = false;
  bool _isAnonymous = false;
  bool _hasExpiry = false;
  DateTime? _expiresAt;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  static const int _maxOptions = 10;
  static const Color _primaryColor = Color(0xFF6C63FF);
  static const Color _accentColor = Color(0xFF00D4AA);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= _maxOptions) {
      _showSnack('Tối đa $_maxOptions lựa chọn');
      return;
    }
    setState(() {
      _optionControllers.add(TextEditingController());
      _focusNodes.add(FocusNode());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes.last.requestFocus();
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      _showSnack('Cần ít nhất 2 lựa chọn');
      return;
    }
    setState(() {
      _optionControllers[index].dispose();
      _focusNodes[index].dispose();
      _optionControllers.removeAt(index);
      _focusNodes.removeAt(index);
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _primaryColor),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      );
      setState(() {
        _expiresAt = pickedTime != null
            ? DateTime(picked.year, picked.month, picked.day, pickedTime.hour,
                pickedTime.minute)
            : DateTime(picked.year, picked.month, picked.day, 23, 59);
      });
    }
  }

  void _create() {
    final question = _questionController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (question.isEmpty) {
      _showSnack('Vui lòng nhập câu hỏi');
      return;
    }
    if (options.length < 2) {
      _showSnack('Cần ít nhất 2 lựa chọn hợp lệ');
      return;
    }

    widget.onCreate(
      question,
      options,
      isMultipleChoice: _isMultipleChoice,
      isAnonymous: _isAnonymous,
      expiresAt: _hasExpiry ? _expiresAt : null,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return FadeTransition(
      opacity: _fadeAnim,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
            horizontal: 16, vertical: mediaQuery.padding.top + 16),
        child: Container(
          constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.88, maxWidth: 500),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withOpacity(0.15),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildQuestionField(),
                        const SizedBox(height: 20),
                        _buildOptionsSection(),
                        const SizedBox(height: 20),
                        _buildSettingsSection(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryColor, Color(0xFF9B5DE5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.poll_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tạo bình chọn',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                Text('Hỏi ý kiến mọi người trong nhóm',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('Câu hỏi',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 8),
        TextFormField(
          controller: _questionController,
          maxLines: 2,
          minLines: 1,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: 'Nhập câu hỏi bình chọn...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: const Icon(Icons.help_outline_rounded,
                color: _primaryColor, size: 20),
            filled: true,
            fillColor: const Color(0xFFF5F4FF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _primaryColor, width: 1.5),
            ),
            counterStyle: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildOptionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Lựa chọn',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E))),
            const Spacer(),
            Text('${_optionControllers.length}/$_maxOptions',
                style: TextStyle(
                    fontSize: 12,
                    color: _optionControllers.length >= _maxOptions
                        ? Colors.orange
                        : Colors.grey)),
          ],
        ),
        const SizedBox(height: 10),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _optionControllers.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final c = _optionControllers.removeAt(oldIndex);
              final f = _focusNodes.removeAt(oldIndex);
              _optionControllers.insert(newIndex, c);
              _focusNodes.insert(newIndex, f);
            });
          },
          itemBuilder: (ctx, index) {
            return _OptionTile(
              key: ValueKey('opt_$index'),
              index: index,
              controller: _optionControllers[index],
              focusNode: _focusNodes[index],
              canRemove: _optionControllers.length > 2,
              onRemove: () => _removeOption(index),
              onSubmitted: (_) {
                if (index < _optionControllers.length - 1) {
                  _focusNodes[index + 1].requestFocus();
                } else {
                  _addOption();
                }
              },
            );
          },
        ),
        const SizedBox(height: 8),
        if (_optionControllers.length < _maxOptions)
          GestureDetector(
            onTap: _addOption,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                border: Border.all(
                    color: _primaryColor.withOpacity(0.4), width: 1.5),
                borderRadius: BorderRadius.circular(12),
                color: _primaryColor.withOpacity(0.04),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline_rounded,
                      color: _primaryColor, size: 18),
                  SizedBox(width: 6),
                  Text('Thêm lựa chọn',
                      style: TextStyle(
                          color: _primaryColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          _ToggleTile(
            icon: Icons.check_box_outlined,
            iconColor: _primaryColor,
            title: 'Chọn nhiều đáp án',
            subtitle: 'Cho phép bình chọn nhiều lựa chọn',
            value: _isMultipleChoice,
            onChanged: (v) => setState(() => _isMultipleChoice = v),
          ),
          Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Colors.grey.shade200),
          _ToggleTile(
            icon: Icons.visibility_off_outlined,
            iconColor: const Color(0xFF00B4D8),
            title: 'Bình chọn ẩn danh',
            subtitle: 'Không hiển thị ai đã bình chọn',
            value: _isAnonymous,
            onChanged: (v) => setState(() => _isAnonymous = v),
          ),
          Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Colors.grey.shade200),
          _ToggleTile(
            icon: Icons.timer_outlined,
            iconColor: const Color(0xFFFF6B6B),
            title: 'Đặt thời hạn',
            subtitle: _hasExpiry && _expiresAt != null
                ? _formatExpiry(_expiresAt!)
                : 'Tự động đóng bình chọn',
            value: _hasExpiry,
            onChanged: (v) async {
              setState(() => _hasExpiry = v);
              if (v) await _pickExpiryDate();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Hủy',
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryColor, Color(0xFF9B5DE5)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Tạo bình chọn',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatExpiry(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<String> onSubmitted;

  const _OptionTile({
    super.key,
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.canRemove,
    required this.onRemove,
    required this.onSubmitted,
  });

  static const _primaryColor = Color(0xFF6C63FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Drag handle
          const Icon(Icons.drag_indicator_rounded,
              color: Colors.grey, size: 20),
          const SizedBox(width: 6),
          // Number badge
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                  color: _primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLength: 100,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'Lựa chọn ${index + 1}',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF5F4FF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _primaryColor, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                counterText: '',
                suffixIcon: canRemove
                    ? IconButton(
                        icon: Icon(Icons.cancel_rounded,
                            color: Colors.grey.shade400, size: 18),
                        onPressed: onRemove,
                        splashRadius: 16,
                      )
                    : null,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E))),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF6C63FF),
      ),
    );
  }
}

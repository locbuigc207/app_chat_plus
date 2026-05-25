import 'package:flutter/material.dart';

class CreatePollDialog extends StatefulWidget {
  final Function(String question, List<String> options) onCreate;

  const CreatePollDialog({super.key, required this.onCreate});

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _create() {
    final question = _questionController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (question.isNotEmpty && options.length >= 2) {
      widget.onCreate(question, options);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tạo bình chọn mới'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _questionController,
              decoration: const InputDecoration(labelText: 'Câu hỏi'),
            ),
            const SizedBox(height: 16),
            ...List.generate(_optionControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  controller: _optionControllers[index],
                  decoration: InputDecoration(
                    labelText: 'Lựa chọn ${index + 1}',
                    suffixIcon: index > 1
                        ? IconButton(
                            icon: const Icon(Icons.remove_circle,
                                color: Colors.red),
                            onPressed: () => setState(
                                () => _optionControllers.removeAt(index)),
                          )
                        : null,
                  ),
                ),
              );
            }),
            TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add),
              label: const Text('Thêm lựa chọn'),
            )
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        ElevatedButton(onPressed: _create, child: const Text('Tạo')),
      ],
    );
  }
}

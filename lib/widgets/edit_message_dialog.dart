// lib/widgets/edit_message_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class EditMessageDialog extends StatefulWidget {
  final String originalContent;
  final Function(String) onSave;

  const EditMessageDialog({
    super.key,
    required this.originalContent,
    required this.onSave,
  });

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.originalContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Edit Message',
        style: TextStyle(color: ColorConstants.primaryColor),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 5,
        decoration: const InputDecoration(
          hintText: 'Enter message...',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_controller.text.trim().isNotEmpty) {
              widget.onSave(_controller.text.trim());
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
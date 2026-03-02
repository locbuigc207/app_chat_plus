// lib/widgets/auto_delete_settings_dialog.dart (COMPLETE FIXED)
import 'package:flutter/material.dart';
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
  State<AutoDeleteSettingsDialog> createState() =>
      _AutoDeleteSettingsDialogState();
}

class _AutoDeleteSettingsDialogState extends State<AutoDeleteSettingsDialog> {
  AutoDeleteDuration _selectedDuration = AutoDeleteDuration.never;
  final _customHoursController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings =
    await widget.provider.getAutoDeleteSettings(widget.conversationId);
    if (settings != null && settings['enabled'] == true) {
      final duration = settings['duration'] as int?;
      if (duration != null) {
        setState(() {
          if (duration == 24 * 60 * 60 * 1000) {
            _selectedDuration = AutoDeleteDuration.oneDay;
          } else if (duration == 7 * 24 * 60 * 60 * 1000) {
            _selectedDuration = AutoDeleteDuration.sevenDays;
          } else if (duration == 30 * 24 * 60 * 60 * 1000) {
            _selectedDuration = AutoDeleteDuration.thirtyDays;
          } else {
            _selectedDuration = AutoDeleteDuration.custom;
            _customHoursController.text =
                (duration ~/ (60 * 60 * 1000)).toString();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Auto-Delete Messages',
        style: TextStyle(color: ColorConstants.primaryColor),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AutoDeleteDuration>(
              title: const Text('Never'),
              value: AutoDeleteDuration.never,
              groupValue: _selectedDuration,
              onChanged: (value) {
                setState(() => _selectedDuration = value!);
              },
            ),
            RadioListTile<AutoDeleteDuration>(
              title: const Text('After 24 hours'),
              value: AutoDeleteDuration.oneDay,
              groupValue: _selectedDuration,
              onChanged: (value) {
                setState(() => _selectedDuration = value!);
              },
            ),
            RadioListTile<AutoDeleteDuration>(
              title: const Text('After 7 days'),
              value: AutoDeleteDuration.sevenDays,
              groupValue: _selectedDuration,
              onChanged: (value) {
                setState(() => _selectedDuration = value!);
              },
            ),
            RadioListTile<AutoDeleteDuration>(
              title: const Text('After 30 days'),
              value: AutoDeleteDuration.thirtyDays,
              groupValue: _selectedDuration,
              onChanged: (value) {
                setState(() => _selectedDuration = value!);
              },
            ),
            RadioListTile<AutoDeleteDuration>(
              title: const Text('Custom'),
              value: AutoDeleteDuration.custom,
              groupValue: _selectedDuration,
              onChanged: (value) {
                setState(() => _selectedDuration = value!);
              },
            ),
            if (_selectedDuration == AutoDeleteDuration.custom)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _customHoursController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Hours',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            int? customHours;
            if (_selectedDuration == AutoDeleteDuration.custom) {
              customHours = int.tryParse(_customHoursController.text);
              if (customHours == null || customHours <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please enter valid hours')),
                );
                return;
              }
            }

            final success = await widget.provider.setAutoDelete(
              conversationId: widget.conversationId,
              duration: _selectedDuration,
              customHours: customHours,
            );

            if (success) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Auto-delete settings updated')),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _customHoursController.dispose();
    super.dispose();
  }
}
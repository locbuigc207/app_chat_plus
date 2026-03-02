// lib/widgets/schedule_message_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:intl/intl.dart';

class ScheduleMessageDialog extends StatelessWidget {
  const ScheduleMessageDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return _ScheduleMessageContent();
  }
}

class _ScheduleMessageContent extends StatefulWidget {
  const _ScheduleMessageContent();

  @override
  State<_ScheduleMessageContent> createState() =>
      _ScheduleMessageContentState();
}

class _ScheduleMessageContentState extends State<_ScheduleMessageContent> {
  final _messageController = TextEditingController();
  DateTime? _scheduledTime;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time == null || !mounted) return;

    setState(() {
      _scheduledTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _handleSchedule() {
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a message')),
      );
      return;
    }

    if (_scheduledTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select time')),
      );
      return;
    }

    // ✅ Return data và đóng dialog
    Navigator.of(context).pop({
      'message': _messageController.text.trim(),
      'time': _scheduledTime,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.schedule_send, color: ColorConstants.primaryColor),
          SizedBox(width: 8),
          Text('Schedule Message'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Message:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: ColorConstants.primaryColor,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter your message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Schedule Time:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: ColorConstants.primaryColor,
              ),
            ),
            SizedBox(height: 8),
            InkWell(
              onTap: _pickDateTime,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: ColorConstants.greyColor2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today,
                        color: ColorConstants.primaryColor),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _scheduledTime != null
                            ? DateFormat('MMM dd, yyyy HH:mm')
                                .format(_scheduledTime!)
                            : 'Select date & time',
                        style: TextStyle(
                          color: _scheduledTime != null
                              ? ColorConstants.primaryColor
                              : ColorConstants.greyColor,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 16),
                  ],
                ),
              ),
            ),
            if (_scheduledTime != null) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Message will be sent in ${_scheduledTime!.difference(DateTime.now()).inMinutes} minutes',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _handleSchedule,
          style: ElevatedButton.styleFrom(
            backgroundColor: ColorConstants.primaryColor,
          ),
          child: Text('Schedule', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

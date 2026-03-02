// lib/widgets/pin_input_dialog.dart (WITH CONFIRM BUTTON)
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class PINInputDialog extends StatefulWidget {
  final String title;
  final Function(String pin) onComplete;
  final String? errorMessage;
  final int? remainingAttempts;

  const PINInputDialog({
    super.key,
    required this.title,
    required this.onComplete,
    this.errorMessage,
    this.remainingAttempts,
  });

  @override
  State<PINInputDialog> createState() => _PINInputDialogState();
}

class _PINInputDialogState extends State<PINInputDialog> {
  String _pin = '';
  final int _pinLength = 4;
  bool _isLoading = false;

  void _onNumberPressed(String number) {
    if (_pin.length < _pinLength && !_isLoading) {
      setState(() {
        _pin += number;
      });
    }
  }

  void _onDeletePressed() {
    if (_pin.isNotEmpty && !_isLoading) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  void _onConfirmPressed() {
    if (_pin.length == _pinLength && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
      widget.onComplete(_pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_isLoading,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lock Icon
              Icon(
                Icons.lock_outline,
                size: 48,
                color: ColorConstants.primaryColor,
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: ColorConstants.primaryColor,
                ),
              ),

              // Error Message
              if (widget.errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.errorMessage!,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Remaining Attempts
              if (widget.remainingAttempts != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${widget.remainingAttempts} attempt${widget.remainingAttempts! != 1 ? 's' : ''} remaining',
                  style: TextStyle(
                    color: widget.remainingAttempts! <= 2
                        ? Colors.red
                        : ColorConstants.greyColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // PIN Display (dots)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index < _pin.length
                          ? ColorConstants.primaryColor
                          : ColorConstants.greyColor2,
                      border: Border.all(
                        color: index < _pin.length
                            ? ColorConstants.primaryColor
                            : ColorConstants.greyColor2,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 32),

              // Number Pad
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: 12,
                itemBuilder: (context, index) {
                  if (index == 9) {
                    return const SizedBox.shrink();
                  } else if (index == 10) {
                    return _buildNumberButton('0');
                  } else if (index == 11) {
                    return _buildDeleteButton();
                  } else {
                    return _buildNumberButton('${index + 1}');
                  }
                },
              ),

              const SizedBox(height: 24),

              // Confirm Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _pin.length == _pinLength && !_isLoading
                      ? _onConfirmPressed
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ColorConstants.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: ColorConstants.greyColor2,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Confirm',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // Cancel button
              TextButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: ColorConstants.greyColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberButton(String number) {
    return InkWell(
      onTap: () => _onNumberPressed(number),
      borderRadius: BorderRadius.circular(40),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ColorConstants.greyColor2,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: ColorConstants.primaryColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return InkWell(
      onTap: _onDeletePressed,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ColorConstants.greyColor2,
            width: 2,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.backspace_outlined,
            color: ColorConstants.primaryColor,
          ),
        ),
      ),
    );
  }
}

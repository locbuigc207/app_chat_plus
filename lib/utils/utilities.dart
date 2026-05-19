import 'package:flutter/material.dart';

class Utilities {
  static bool isKeyboardShowing(BuildContext context) {
    return MediaQuery.of(context).viewInsets.bottom > 0;
  }

  static void closeKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }
}

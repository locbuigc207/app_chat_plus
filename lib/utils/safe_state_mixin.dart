import 'package:flutter/material.dart';

mixin SafeStateMixin<T extends StatefulWidget> on State<T> {
  bool _safeDisposed = false;

  bool get isDisposed => _safeDisposed;

  @override
  void dispose() {
    _safeDisposed = true;
    super.dispose();
  }

  void safeSetState(VoidCallback fn) {
    if (!_safeDisposed && mounted) {
      setState(fn);
    }
  }

  void ifMounted(VoidCallback fn) {
    if (!_safeDisposed && mounted) fn();
  }
}

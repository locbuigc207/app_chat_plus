// lib/utils/bubble_testing_utils.dart
// ✅ GIAI ĐOẠN 5: TESTING & DEBUGGING UTILITIES

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 🧪 Testing utilities cho Bubble functionality
class BubbleTestingUtils {
  static const MethodChannel _bubbleChannel =
      MethodChannel('bubble_chat_channel');

  // ========================================
  // BUBBLE STATE CHECKS
  // ========================================

  /// Check if app is running in bubble mode
  static Future<bool> isRunningInBubble() async {
    try {
      final result = await _bubbleChannel.invokeMethod<bool>('getBubbleMode');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ Error checking bubble mode: $e');
      return false;
    }
  }

  /// Get current user info from bubble
  static Future<Map<String, dynamic>?> getBubbleUserInfo() async {
    try {
      final result = await _bubbleChannel.invokeMethod<Map>('getUserInfo');
      return result?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('❌ Error getting user info: $e');
      return null;
    }
  }

  // ========================================
  // TEST ACTIONS
  // ========================================

  /// Test minimize action
  static Future<bool> testMinimize() async {
    try {
      debugPrint('🧪 Testing minimize...');
      final result = await _bubbleChannel.invokeMethod<bool>('minimize');
      debugPrint(result == true ? '✅ Minimize OK' : '❌ Minimize failed');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ Minimize error: $e');
      return false;
    }
  }

  /// Test close action
  static Future<bool> testClose() async {
    try {
      debugPrint('🧪 Testing close...');
      final result = await _bubbleChannel.invokeMethod<bool>('close');
      debugPrint(result == true ? '✅ Close OK' : '❌ Close failed');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ Close error: $e');
      return false;
    }
  }

  // ========================================
  // DEBUG WIDGETS
  // ========================================

  /// Show bubble debug overlay
  static Widget buildDebugOverlay(BuildContext context) {
    return Positioned(
      top: 60,
      right: 10,
      child: FutureBuilder<bool>(
        future: isRunningInBubble(),
        builder: (context, snapshot) {
          final isBubble = snapshot.data ?? false;

          return Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isBubble ? Colors.orange : Colors.grey,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isBubble ? Icons.bubble_chart : Icons.chat,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 4),
                Text(
                  isBubble ? 'BUBBLE' : 'NORMAL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Show test buttons overlay
  static Widget buildTestButtonsOverlay() {
    return Positioned(
      bottom: 80,
      right: 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'test_minimize',
            onPressed: testMinimize,
            backgroundColor: Colors.blue,
            child: Icon(Icons.remove, size: 20),
            tooltip: 'Test Minimize',
          ),
          SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'test_close',
            onPressed: testClose,
            backgroundColor: Colors.red,
            child: Icon(Icons.close, size: 20),
            tooltip: 'Test Close',
          ),
          SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'test_info',
            onPressed: () async {
              final info = await getBubbleUserInfo();
              debugPrint('📋 User info: $info');
            },
            backgroundColor: Colors.green,
            child: Icon(Icons.info, size: 20),
            tooltip: 'Get Info',
          ),
        ],
      ),
    );
  }
}

// ========================================
// USAGE EXAMPLE IN CHATPAGE
// ========================================

/// Add to ChatPage build method for testing:
///
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   return Stack(
///     children: [
///       // Existing ChatPage UI
///       _buildExistingUI(),
///
///       // ✅ Debug overlay (only in debug mode)
///       if (kDebugMode) ...[
///         BubbleTestingUtils.buildDebugOverlay(context),
///         BubbleTestingUtils.buildTestButtonsOverlay(),
///       ],
///     ],
///   );
/// }
/// ```

// ========================================
// LOG FORMATTER
// ========================================

/// Pretty print logs for bubble operations
class BubbleLogger {
  static const String _prefix = '🎈 BUBBLE';

  static void info(String message) {
    debugPrint('$_prefix ℹ️ $message');
  }

  static void success(String message) {
    debugPrint('$_prefix ✅ $message');
  }

  static void warning(String message) {
    debugPrint('$_prefix ⚠️ $message');
  }

  static void error(String message, [dynamic error]) {
    debugPrint('$_prefix ❌ $message');
    if (error != null) {
      debugPrint('$_prefix    Details: $error');
    }
  }

  static void navigation(String from, String to) {
    debugPrint('$_prefix 🧭 Navigation: $from → $to');
  }

  static void channelCall(String method, [Map<String, dynamic>? args]) {
    debugPrint('$_prefix 📞 Channel call: $method');
    if (args != null) {
      debugPrint('$_prefix    Args: $args');
    }
  }
}

// ========================================
// BUBBLE MODE DETECTOR WIDGET
// ========================================

/// Widget that adapts based on bubble mode
class BubbleModeAware extends StatefulWidget {
  final Widget Function(BuildContext context, bool isBubble) builder;

  const BubbleModeAware({
    super.key,
    required this.builder,
  });

  @override
  State<BubbleModeAware> createState() => _BubbleModeAwareState();
}

class _BubbleModeAwareState extends State<BubbleModeAware> {
  bool _isBubbleMode = false;

  @override
  void initState() {
    super.initState();
    _checkBubbleMode();
  }

  Future<void> _checkBubbleMode() async {
    final isBubble = await BubbleTestingUtils.isRunningInBubble();
    if (mounted) {
      setState(() {
        _isBubbleMode = isBubble;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _isBubbleMode);
  }
}

// ========================================
// EXAMPLE USAGE
// ========================================

/// Example: Show different UI based on bubble mode
///
/// ```dart
/// BubbleModeAware(
///   builder: (context, isBubble) {
///     return Container(
///       padding: isBubble
///         ? EdgeInsets.all(8)  // Compact in bubble
///         : EdgeInsets.all(16), // Spacious in normal
///       child: Text(
///         isBubble ? 'Bubble Mode' : 'Normal Mode',
///       ),
///     );
///   },
/// )
/// ```

// ========================================
// PERFORMANCE MONITOR
// ========================================

/// Monitor bubble performance
class BubblePerformanceMonitor {
  static final Stopwatch _stopwatch = Stopwatch();

  static void startMeasure(String operation) {
    _stopwatch.reset();
    _stopwatch.start();
    BubbleLogger.info('⏱️ Started: $operation');
  }

  static void endMeasure(String operation) {
    _stopwatch.stop();
    final duration = _stopwatch.elapsedMilliseconds;

    if (duration > 1000) {
      BubbleLogger.warning('⏱️ Slow operation: $operation (${duration}ms)');
    } else {
      BubbleLogger.success('⏱️ Completed: $operation (${duration}ms)');
    }
  }
}

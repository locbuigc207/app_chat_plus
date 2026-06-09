import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/services/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OBSERVER
// ═══════════════════════════════════════════════════════════════════════════

class BubbleLifecycleObserver with WidgetsBindingObserver {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final BubbleLifecycleObserver instance = BubbleLifecycleObserver._();
  BubbleLifecycleObserver._();

  // ── Dependencies ──────────────────────────────────────────────────────────
  final _service = UnifiedBubbleService();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _attached = false;
  bool _initialized = false;
  AppLifecycleState _lastState = AppLifecycleState.resumed;

  // Currently open conversation — set by BubbleChatPageMixin
  String? _activeChatUserId;

  // Debounce resume events (some devices fire resume twice rapidly)
  Timer? _resumeDebounce;
  DateTime _lastResumeAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ─── Stream for state changes ─────────────────────────────────────────────
  final _stateCtrl = StreamController<AppLifecycleState>.broadcast();
  Stream<AppLifecycleState> get lifecycleStream => _stateCtrl.stream;
  AppLifecycleState get currentState => _lastState;
  bool get isForegrounded => _lastState == AppLifecycleState.resumed;

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    debugPrint('✅ BubbleLifecycleObserver initialized');
  }

  void attach() {
    if (_attached) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
    debugPrint('✅ BubbleLifecycleObserver attached');
  }

  void detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
    debugPrint('✅ BubbleLifecycleObserver detached');
  }

  // ─── Active conversation tracking ────────────────────────────────────────

  /// Call when a chat page is opened.
  void onChatOpened(String userId) {
    _activeChatUserId = userId;
    // Clear unread for this conversation
    _service.clearUnread(userId);
    debugPrint('💬 Chat opened: $userId');
  }

  /// Call when a chat page is closed.
  void onChatClosed(String userId) {
    if (_activeChatUserId == userId) _activeChatUserId = null;
    debugPrint('💬 Chat closed: $userId');
  }

  bool isChatActive(String userId) => _activeChatUserId == userId;

  // ═════════════════════════════════════════════════════════════════════
  // LIFECYCLE CALLBACKS
  // ═════════════════════════════════════════════════════════════════════

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == _lastState) return;
    final prev = _lastState;
    _lastState = state;
    _stateCtrl.add(state);

    debugPrint('📱 AppLifecycle: ${prev.name} → ${state.name}');

    switch (state) {
      case AppLifecycleState.resumed:
        _onResumed();
        break;

      case AppLifecycleState.paused:
        _onPaused();
        break;

      case AppLifecycleState.inactive:
        // Transitional state — do nothing
        break;

      case AppLifecycleState.detached:
        _onDetached();
        break;

      case AppLifecycleState.hidden:
        // Android 14+ hidden state (picture-in-picture, split screen)
        _onHidden();
        break;
    }
  }

  // ─── Foreground (resumed) ─────────────────────────────────────────────────

  void _onResumed() {
    // Debounce — ignore if resumed within last 800 ms
    final now = DateTime.now();
    if (now.difference(_lastResumeAt).inMilliseconds < 800) return;
    _lastResumeAt = now;

    _resumeDebounce?.cancel();
    _resumeDebounce = Timer(const Duration(milliseconds: 300), () {
      // Clear unread for currently active chat
      if (_activeChatUserId != null) {
        _service.clearUnread(_activeChatUserId!);
      }
      // Auto-hide bubbles for open conversations
      _autoHideActiveChatBubble();
      debugPrint('▶️ App resumed — bubble sync complete');
    });
  }

  void _autoHideActiveChatBubble() {
    if (_activeChatUserId == null) return;
    // If the user has the chat page open, the bubble is redundant
    if (_service.isBubbleActive(_activeChatUserId!)) {
      // Don't fully hide — just clear unread so badge disappears
      _service.clearUnread(_activeChatUserId!);
    }
  }

  // ─── Background (paused) ─────────────────────────────────────────────────

  void _onPaused() {
    _resumeDebounce?.cancel();
    // Bubbles remain active in background — native service takes over
    debugPrint('⏸️ App paused — bubbles handed to native layer');
  }

  // ─── Detached (killed) ────────────────────────────────────────────────────

  void _onDetached() {
    debugPrint('💥 App detached');
    // FCM service will handle incoming messages from this point
  }

  // ─── Hidden (API 34+) ─────────────────────────────────────────────────────

  void _onHidden() {
    debugPrint('🙈 App hidden (PiP / split screen)');
    // Keep bubbles — user may be using another app
  }

  // ═════════════════════════════════════════════════════════════════════
  // MEMORY PRESSURE
  // ═════════════════════════════════════════════════════════════════════

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    debugPrint('⚠️ Memory pressure — bubble system conserving');
    // The Glide LRU cache on the Android side will auto-evict bitmaps
  }

  // ═════════════════════════════════════════════════════════════════════
  // ACCESSIBILITY
  // ═════════════════════════════════════════════════════════════════════

  @override
  void didChangeAccessibilityFeatures() {
    super.didChangeAccessibilityFeatures();
    // If TalkBack is on, reduce animation intensity
    final isTalkBack =
        WidgetsBinding.instance.accessibilityFeatures.accessibleNavigation;
    debugPrint('♿ Accessibility: TalkBack=${isTalkBack}');
  }

  // ═════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═════════════════════════════════════════════════════════════════════

  void dispose() {
    detach();
    _resumeDebounce?.cancel();
    _stateCtrl.close();
    _initialized = false;
    debugPrint('✅ BubbleLifecycleObserver disposed');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVENIENCE MIXIN FOR ROOT WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Add to your root StatefulWidget to automatically attach/detach the observer.
///
/// ```dart
/// class _AppState extends State<App> with BubbleLifecycleMixin {
///   @override Widget build(BuildContext ctx) => MaterialApp(…);
/// }
/// ```
mixin BubbleLifecycleMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    BubbleLifecycleObserver.instance.attach();
  }

  @override
  void dispose() {
    BubbleLifecycleObserver.instance.detach();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LIFECYCLE STATE BANNER (debug / dev only)
// ═══════════════════════════════════════════════════════════════════════════

/// Shows the current app lifecycle state as a small overlay — useful for
/// testing that bubbles behave correctly on lifecycle changes.
class LifecycleStateBanner extends StatefulWidget {
  const LifecycleStateBanner({super.key});

  @override
  State<LifecycleStateBanner> createState() => _LifecycleStateBannerState();
}

class _LifecycleStateBannerState extends State<LifecycleStateBanner> {
  StreamSubscription<AppLifecycleState>? _sub;
  AppLifecycleState _state = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    _sub = BubbleLifecycleObserver.instance.lifecycleStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static Color _color(AppLifecycleState s) => switch (s) {
        AppLifecycleState.resumed => Colors.green,
        AppLifecycleState.paused => Colors.orange,
        AppLifecycleState.inactive => Colors.amber,
        AppLifecycleState.detached => Colors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color(_state).withOpacity(0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '📱 ${_state.name}',
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

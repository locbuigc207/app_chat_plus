// lib/widgets/bubble_integration_demo.dart
// Comprehensive example showing how to wire the whole bubble system.
// Drop BubbleSystemWrapper at the root of your app (inside MaterialApp),
// then call BubbleManager.of(context) from any widget to interact.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// APP ROOT WRAPPER
// ═══════════════════════════════════════════════════════════════════════════

/// Wrap your entire app widget tree with this.
/// It wires BubbleManager, provides UnifiedBubbleService via Provider, and
/// ensures the overlay system is initialized before any child renders.
class BubbleSystemWrapper extends StatelessWidget {
  final Widget child;
  const BubbleSystemWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Provider<UnifiedBubbleService>(
      create: (_) => UnifiedBubbleService(),
      dispose: (_, svc) => svc.dispose(),
      child: BubbleManager(child: child),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRIGGER BUTTON — show bubble when message arrives
// ═══════════════════════════════════════════════════════════════════════════

/// Example: call this when a new message arrives for [userId].
Future<void> onIncomingMessage({
  required BuildContext context,
  required String userId,
  required String userName,
  required String avatarUrl,
  required String message,
}) async {
  final ctrl = BubbleManager.of(context);
  if (ctrl == null) return;

  // Request permission if needed (Android <11 only)
  if (!await ctrl.hasPermission()) {
    await ctrl.requestPermission();
  }

  // Show / update the bubble
  await ctrl.showBubble(
    userId: userId,
    userName: userName,
    avatarUrl: avatarUrl,
    lastMessage: message,
    isOnline: true,
  );

  // Also update contextual mode from the message text
  ContextualBubbleService.instance.updateContext(
    conversationId: userId,
    message: message,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// BUBBLE STATUS BAR WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Shows a row of active bubble avatars at the bottom of any screen.
/// Tapping one opens the mini-chat overlay for that user.
class BubbleStatusBar extends StatelessWidget {
  const BubbleStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<UnifiedBubbleService>();
    return StreamBuilder<Map<String, BubbleData>>(
      stream: svc.activeBubblesStream,
      initialData: svc.activeBubbles,
      builder: (ctx, snap) {
        final bubbles = snap.data?.values.toList() ?? [];
        if (bubbles.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -3)),
            ],
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: bubbles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _BubbleAvatar(data: bubbles[i]),
          ),
        );
      },
    );
  }
}

class _BubbleAvatar extends StatelessWidget {
  final BubbleData data;
  const _BubbleAvatar({required this.data});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        BubbleManager.of(context)?.showMiniChat(
          userId: data.userId,
          userName: data.userName,
          avatarUrl: data.avatarUrl,
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage:
                data.avatarUrl.isNotEmpty ? NetworkImage(data.avatarUrl) : null,
            child: data.avatarUrl.isEmpty
                ? Text(data.userName.isNotEmpty
                    ? data.userName[0].toUpperCase()
                    : '?')
                : null,
          ),
          if (data.unreadCount > 0)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                child: Text(
                  data.unreadCount > 9 ? '9+' : '${data.unreadCount}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          if (data.isOnline)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2)),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXTUAL HEADER DEMO
// ═══════════════════════════════════════════════════════════════════════════

/// Shows how the BubbleAdaptiveHeader morphs when [message] is analysed.
class ContextualHeaderDemo extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String peerAvatar;

  const ContextualHeaderDemo({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  });

  @override
  State<ContextualHeaderDemo> createState() => _ContextualHeaderDemoState();
}

class _ContextualHeaderDemoState extends State<ContextualHeaderDemo> {
  BubbleContext _ctx = const BubbleContext();
  final _testMessages = [
    "Hey, what's up?", // Sửa thành nháy kép
    'Deadline for the Q3 report is Friday 17:00 ⏰',
    '📍 Tôi đang ở đây: maps.google.com/xyz',
    '🔒 Nhắn riêng nhé, bảo mật',
    '🎵 Check out this track on Spotify',
    "🎨 Let's work on the Figma file together", // Sửa thành nháy kép
  ];

  void _testMessage(String msg) {
    final next = ContextualBubbleService.analyzeMessage(message: msg);
    setState(() => _ctx = next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Adaptive header
        BubbleAdaptiveHeader(
          bubbleCtx: _ctx,
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          isPeerOnline: true,
          onMinimize: () {},
          onClose: () {},
        ),
        const SizedBox(height: 12),
        // Mode chip
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blueGrey.shade200),
            ),
            child: Text(
              'Mode: ${_ctx.mode.name}'
              '${_ctx.detectedTopic != null ? " · ${_ctx.detectedTopic}" : ""}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Test messages
        ..._testMessages.map((msg) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: OutlinedButton(
                onPressed: () => _testMessage(msg),
                child: Text(
                  msg,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PERMISSION SETUP PAGE
// ═══════════════════════════════════════════════════════════════════════════

/// Show this page the first time the user enables chat bubbles.
class BubblePermissionPage extends StatelessWidget {
  const BubblePermissionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kích hoạt bong bóng chat')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Feature illustration
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2979FF), Color(0xFF1565C0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF2979FF).withOpacity(0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Colors.white, size: 56),
              ),
            ),
            const SizedBox(height: 32),
            const Text('Bong bóng chat',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              'Chat với bạn bè ngay cả khi đang dùng app khác. '
              'Bong bóng hiện lên trên màn hình để bạn không bỏ lỡ tin nhắn nào.',
              style: TextStyle(
                  fontSize: 15, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 32),
            _FeatureRow(
                icon: Icons.picture_in_picture_alt_rounded,
                label: 'Mini chat nổi — chat không rời app'),
            _FeatureRow(
                icon: Icons.notifications_active_rounded,
                label: 'Badge số tin chưa đọc'),
            _FeatureRow(
                icon: Icons.lock_rounded,
                label: 'Bảo mật đầu cuối trong mọi chế độ'),
            _FeatureRow(
                icon: Icons.auto_awesome_rounded,
                label: 'Giao diện thích ứng theo ngữ cảnh'),
            const Spacer(),
            // Permission gate
            BubblePermissionGate(
              child: const _PermissionGranted(),
              permissionDeniedWidget: _PermissionRequest(
                onRequest: () async {
                  final ctrl = BubbleManager.of(context);
                  await ctrl?.requestPermission();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF2979FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF2979FF), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _PermissionGranted extends StatelessWidget {
  const _PermissionGranted();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              color: Colors.green.shade600, size: 28),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('Quyền đã được cấp! Bong bóng chat sẵn sàng.',
                  style: TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _PermissionRequest extends StatelessWidget {
  final VoidCallback onRequest;
  const _PermissionRequest({required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onRequest,
        icon: const Icon(Icons.settings_rounded),
        label: const Text('Cấp quyền hiển thị nổi',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2979FF),
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: const Color(0xFF2979FF).withOpacity(0.4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN DEMO — put in main.dart for standalone testing
// ═══════════════════════════════════════════════════════════════════════════

void runBubbleDemo() {
  runApp(
    const BubbleSystemWrapper(
      child: MaterialApp(
        title: 'Bubble Demo',
        debugShowCheckedModeBanner: false,
        home: _DemoHome(),
      ),
    ),
  );
}

class _DemoHome extends StatelessWidget {
  const _DemoHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Bubble System'),
        backgroundColor: const Color(0xFF2979FF),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Active bubbles panel
            const Text('Bubble đang hoạt động',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            ActiveBubblesPanel(service: context.read<UnifiedBubbleService>()),
            const SizedBox(height: 24),
            // Simulate incoming message
            ElevatedButton.icon(
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Giả lập tin nhắn đến'),
              onPressed: () => onIncomingMessage(
                context: context,
                userId: 'user_demo_001',
                userName: 'Nguyễn Văn A',
                avatarUrl: '',
                message: 'Deadline cuối tuần này anh nhé! ⏰',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2979FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.clear_all_rounded),
              label: const Text('Xoá tất cả bubbles'),
              onPressed: () => BubbleManager.of(context)?.hideAll(),
            ),
            const SizedBox(height: 24),
            // Header demo
            const Text('Contextual Header Demo',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            ContextualHeaderDemo(
                peerId: 'demo_user', peerName: 'Trần Thị B', peerAvatar: ''),
          ],
        ),
      ),
      bottomNavigationBar: const BubbleStatusBar(),
    );
  }
}

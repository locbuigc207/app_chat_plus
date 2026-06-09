import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final String _currentUserId;
  late final FriendProvider _friendProvider;
  late final FirebaseFirestore _firebaseFirestore;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
    _friendProvider = FriendProvider(
      firebaseFirestore: context.read<HomeProvider>().firebaseFirestore,
    );
    _firebaseFirestore = context.read<HomeProvider>().firebaseFirestore;
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 7) return DateFormat('dd/MM/yyyy').format(dt);
      if (diff.inDays > 0) return '${diff.inDays} ngày trước';
      if (diff.inHours > 0) return '${diff.inHours} giờ trước';
      if (diff.inMinutes > 0) return '${diff.inMinutes} phút trước';
      return 'Vừa xong';
    } catch (_) {
      return '';
    }
  }

  Future<void> _accept(String requestId, String requesterId) async {
    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);

    final ok = await _friendProvider.acceptFriendRequest(requestId, _currentUserId, requesterId);

    if (mounted) setState(() => _isLoading = false);

    Fluttertoast.showToast(
      msg: ok ? '✅ Đã chấp nhận lời mời kết bạn!' : '❌ Không thể chấp nhận, thử lại',
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
      textColor: Colors.white,
    );
  }

  Future<void> _reject(String requestId) async {
    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);

    try {
      await _firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .doc(requestId)
          .update({FirestoreConstants.status: 'rejected'});

      Fluttertoast.showToast(
          msg: 'Đã từ chối lời mời',
          backgroundColor: Colors.grey.shade800,
          textColor: Colors.white
      );
    } catch (_) {
      Fluttertoast.showToast(
          msg: 'Có lỗi xảy ra',
          backgroundColor: Colors.red.shade700,
          textColor: Colors.white
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          backgroundColor: p.appBarBackground,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: theme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
              'Lời mời kết bạn',
              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)
          ),
          centerTitle: true,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_alt_rounded, size: 14, color: theme.primaryColor),
                    const SizedBox(width: 4),
                    Text(
                        'Bạn bè',
                        style: TextStyle(color: theme.primaryColor, fontSize: 12, fontWeight: FontWeight.w600)
                    ),
                  ]
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: _firebaseFirestore
                  .collection(FirestoreConstants.pathFriendRequestCollection)
                  .where(FirestoreConstants.receiverId, isEqualTo: _currentUserId)
                  .orderBy(FirestoreConstants.createdAt, descending: true)
                  .snapshots(),
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _NotifSkeleton(palette: p);
                }

                if (snapshot.hasError) {
                  return _ErrorState(error: '${snapshot.error}', palette: p);
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _EmptyState(palette: p, primary: theme.primaryColor);
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: docs.length,
                  itemBuilder: (_, i) => _RequestCard(
                    requestDoc: docs[i],
                    firebaseFirestore: _firebaseFirestore,
                    palette: p,
                    primary: theme.primaryColor,
                    index: i,
                    timeFormatter: _formatTimestamp,
                    onAccept: _accept,
                    onReject: _reject,
                  ),
                );
              },
            ),
            if (_isLoading) const Positioned.fill(child: LoadingView()),
          ],
        ),
      ),
    );
  }
}

// ─── Request Card ─────────────────────────────────────────────────────────────

class _RequestCard extends StatefulWidget {
  final QueryDocumentSnapshot requestDoc;
  final FirebaseFirestore firebaseFirestore;
  final ThemePalette palette;
  final Color primary;
  final int index;
  final String Function(String) timeFormatter;
  final Future<void> Function(String, String) onAccept;
  final Future<void> Function(String) onReject;

  const _RequestCard({
    required this.requestDoc,
    required this.firebaseFirestore,
    required this.palette,
    required this.primary,
    required this.index,
    required this.timeFormatter,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _localLoading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: 320 + widget.index * 60));
    _slide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 60), () => mounted ? _ctrl.forward() : null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = FriendRequest.fromDocument(widget.requestDoc);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: FutureBuilder<DocumentSnapshot>(
          future: widget.firebaseFirestore
              .collection(FirestoreConstants.pathUserCollection)
              .doc(request.requesterId).get(),
          builder: (_, userSnap) {
            if (!userSnap.hasData) return _CardSkeleton(palette: widget.palette);

            final requester = UserChat.fromDocument(userSnap.data!);
            final colorIdx = requester.nickname.isEmpty
                ? 0
                : requester.nickname.codeUnitAt(0) % ColorConstants.avatarColors.length;
            final avatarColor = ColorConstants.avatarColors[colorIdx];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: widget.palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: widget.palette.divider, width: 0.6),
                boxShadow: [
                  BoxShadow(
                      color: widget.palette.shadow,
                      blurRadius: 12,
                      offset: const Offset(0, 3)
                  )
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: avatarColor.withValues(alpha: 0.12),
                            border: Border.all(color: avatarColor.withValues(alpha: 0.3), width: 1.5),
                          ),
                          child: ClipOval(
                              child: requester.photoUrl.isNotEmpty
                                  ? Image.network(
                                  requester.photoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                      child: Text(
                                          requester.nickname.isNotEmpty ? requester.nickname[0].toUpperCase() : '?',
                                          style: TextStyle(color: avatarColor, fontSize: 20, fontWeight: FontWeight.w700)
                                      )
                                  )
                              )
                                  : Center(
                                  child: Text(
                                      requester.nickname.isNotEmpty ? requester.nickname[0].toUpperCase() : '?',
                                      style: TextStyle(color: avatarColor, fontSize: 20, fontWeight: FontWeight.w700)
                                  )
                              )
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    requester.nickname.isEmpty ? 'Người dùng' : requester.nickname,
                                    style: TextStyle(
                                        color: widget.palette.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15
                                    )
                                ),
                                const SizedBox(height: 3),
                                Text(
                                    'Muốn kết bạn với bạn',
                                    style: TextStyle(color: widget.palette.textSecondary, fontSize: 13)
                                ),
                              ]
                          ),
                        ),
                        Text(
                            widget.timeFormatter(request.createdAt),
                            style: TextStyle(color: widget.palette.textSecondary, fontSize: 11)
                        ),
                      ],
                    ),
                    if (request.status == 'pending') ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                              child: _ActionBtn(
                                label: 'Từ chối',
                                icon: Icons.close_rounded,
                                color: Colors.red.shade400,
                                filled: false,
                                loading: _localLoading,
                                onTap: () async {
                                  setState(() => _localLoading = true);
                                  await widget.onReject(request.id);
                                  if (mounted) setState(() => _localLoading = false);
                                },
                              )
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _ActionBtn(
                                label: 'Chấp nhận',
                                icon: Icons.check_rounded,
                                color: Colors.green.shade600,
                                filled: true,
                                loading: _localLoading,
                                onTap: () async {
                                  setState(() => _localLoading = true);
                                  await widget.onAccept(request.id, request.requesterId);
                                  if (mounted) setState(() => _localLoading = false);
                                },
                              )
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      _StatusBadge(accepted: request.status == 'accepted'),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled, loading;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    required this.loading,
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 42,
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Center(
            child: loading
                ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: filled ? Colors.white : color)
            )
                : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: filled ? Colors.white : color, size: 16),
                  const SizedBox(width: 6),
                  Text(
                      label,
                      style: TextStyle(
                          color: filled ? Colors.white : color,
                          fontWeight: FontWeight.w600,
                          fontSize: 13
                      )
                  ),
                ]
            )
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool accepted;

  const _StatusBadge({required this.accepted});

  @override
  Widget build(BuildContext context) {
    final color = accepted ? Colors.green.shade600 : Colors.red.shade400;
    final label = accepted ? 'Đã chấp nhận' : 'Đã từ chối';
    final icon = accepted ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(
                label,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)
            ),
          ]
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemePalette palette;
  final Color primary;

  const _EmptyState({required this.palette, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.07), shape: BoxShape.circle),
              child: Icon(Icons.notifications_none_rounded, size: 42, color: primary.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 20),
            Text(
                'Chưa có lời mời nào',
                style: TextStyle(color: palette.textSecondary, fontSize: 17, fontWeight: FontWeight.w600)
            ),
            const SizedBox(height: 8),
            Text(
                'Khi ai đó gửi lời mời kết bạn,\nbạn sẽ thấy ở đây',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary, fontSize: 13, height: 1.5)
            ),
          ]
      ),
    );
  }
}

class _NotifSkeleton extends StatefulWidget {
  final ThemePalette palette;

  const _NotifSkeleton({required this.palette});

  @override
  State<_NotifSkeleton> createState() => _NotifSkeletonState();
}

class _NotifSkeletonState extends State<_NotifSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final c = Color.lerp(widget.palette.surface, widget.palette.surfaceVariant, _anim.value)!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
                children: List.generate(
                    5,
                        (_) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(18)),
                      child: Column(
                          children: [
                            Row(
                                children: [
                                  CircleAvatar(radius: 26, backgroundColor: widget.palette.divider),
                                  const SizedBox(width: 14),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                                height: 13,
                                                width: 120,
                                                decoration: BoxDecoration(color: widget.palette.divider, borderRadius: BorderRadius.circular(6))
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
                                                height: 10,
                                                width: 160,
                                                decoration: BoxDecoration(color: widget.palette.divider.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(5))
                                            ),
                                          ]
                                      )
                                  ),
                                ]
                            ),
                            const SizedBox(height: 14),
                            Row(
                                children: [
                                  Expanded(
                                      child: Container(
                                          height: 38,
                                          decoration: BoxDecoration(color: widget.palette.divider.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12))
                                      )
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Container(
                                          height: 38,
                                          decoration: BoxDecoration(color: widget.palette.divider.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12))
                                      )
                                  ),
                                ]
                            ),
                          ]
                      ),
                    )
                )
            ),
          );
        }
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  final ThemePalette palette;

  const _CardSkeleton({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18)),
      child: Row(
          children: [
            CircleAvatar(radius: 26, backgroundColor: palette.divider),
            const SizedBox(width: 14),
            Expanded(
                child: Container(
                    height: 12,
                    decoration: BoxDecoration(color: palette.divider, borderRadius: BorderRadius.circular(6))
                )
            ),
          ]
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final ThemePalette palette;

  const _ErrorState({required this.error, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: palette.textSecondary),
              const SizedBox(height: 16),
              Text(
                  error,
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center
              ),
            ]
        ),
      ),
    );
  }
}
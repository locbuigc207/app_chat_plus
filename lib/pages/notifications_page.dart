import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationsPage — friend request inbox
// ─────────────────────────────────────────────────────────────────────────────

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
      if (diff.inDays > 0) {
        return '${diff.inDays} ngày trước';
      }
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
    final ok = await _friendProvider.acceptFriendRequest(
        requestId, _currentUserId, requesterId);
    setState(() => _isLoading = false);
    if (ok) {
      Fluttertoast.showToast(msg: 'Đã chấp nhận lời mời kết bạn!');
    } else {
      Fluttertoast.showToast(msg: 'Không thể chấp nhận, thử lại');
    }
  }

  Future<void> _reject(String requestId) async {
    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);
    try {
      await _firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .doc(requestId)
          .update({FirestoreConstants.status: 'rejected'});
      Fluttertoast.showToast(msg: 'Đã từ chối lời mời');
    } catch (_) {
      Fluttertoast.showToast(msg: 'Có lỗi xảy ra');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? ColorConstants.backgroundDark : const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: isDark ? ColorConstants.surfaceDark : Colors.white,
        elevation: 0,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white70 : ColorConstants.primaryColor,
              size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Lời mời kết bạn',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1A1D2E),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
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
                return const _NotifSkeleton();
              }

              if (snapshot.hasError) {
                return _ErrorState(error: '${snapshot.error}');
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _EmptyNotifState(isDark: isDark);
              }

              final docs = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: docs.length,
                itemBuilder: (_, i) => _RequestCard(
                  requestDoc: docs[i],
                  firebaseFirestore: _firebaseFirestore,
                  isDark: isDark,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Request Card
// ─────────────────────────────────────────────────────────────────────────────

class _RequestCard extends StatefulWidget {
  final QueryDocumentSnapshot requestDoc;
  final FirebaseFirestore firebaseFirestore;
  final bool isDark;
  final int index;
  final String Function(String) timeFormatter;
  final Future<void> Function(String, String) onAccept;
  final Future<void> Function(String) onReject;

  const _RequestCard({
    required this.requestDoc,
    required this.firebaseFirestore,
    required this.isDark,
    required this.index,
    required this.timeFormatter,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _localLoading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 320 + widget.index * 60),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 60),
        () => mounted ? _ctrl.forward() : null);
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
              .doc(request.requesterId)
              .get(),
          builder: (_, userSnap) {
            if (!userSnap.hasData) {
              return _CardSkeleton(isDark: widget.isDark);
            }

            final requester = UserChat.fromDocument(userSnap.data!);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color:
                    widget.isDark ? ColorConstants.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.isDark
                      ? Colors.white.withOpacity(0.07)
                      : Colors.black.withOpacity(0.05),
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withOpacity(widget.isDark ? 0.18 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header row ─────────────────────────────────────────
                    Row(
                      children: [
                        _NotifAvatar(
                            url: requester.photoUrl, name: requester.nickname),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                requester.nickname.isEmpty
                                    ? 'Người dùng'
                                    : requester.nickname,
                                style: TextStyle(
                                  color: widget.isDark
                                      ? Colors.white
                                      : const Color(0xFF1A1D2E),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Muốn kết bạn với bạn',
                                style: TextStyle(
                                  color: widget.isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          widget.timeFormatter(request.createdAt),
                          style: const TextStyle(
                              color: ColorConstants.greyColor, fontSize: 11),
                        ),
                      ],
                    ),

                    // ── Status / Actions ───────────────────────────────────
                    if (request.status == 'pending') ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionBtn(
                              label: 'Từ chối',
                              icon: Icons.close_rounded,
                              color: const Color(0xFFEF5350),
                              filled: false,
                              loading: _localLoading,
                              onTap: () async {
                                setState(() => _localLoading = true);
                                await widget.onReject(request.id);
                                if (mounted) {
                                  setState(() => _localLoading = false);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ActionBtn(
                              label: 'Chấp nhận',
                              icon: Icons.check_rounded,
                              color: const Color(0xFF43A047),
                              filled: true,
                              loading: _localLoading,
                              onTap: () async {
                                setState(() => _localLoading = true);
                                await widget.onAccept(
                                    request.id, request.requesterId);
                                if (mounted) {
                                  setState(() => _localLoading = false);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      _StatusBadge(
                        accepted: request.status == 'accepted',
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _NotifAvatar extends StatelessWidget {
  final String url;
  final String name;

  const _NotifAvatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final colorIndex = name.isEmpty
        ? 0
        : name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final color = ColorConstants.avatarColors[colorIndex];
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(color))
            : _placeholder(color),
      ),
    );
  }

  Widget _placeholder(Color color) {
    return Container(
      color: color.withOpacity(0.1),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              color: color, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final bool loading;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
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
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: filled ? Colors.white : color),
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
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
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
    final color = accepted ? const Color(0xFF43A047) : const Color(0xFFEF5350);
    final label = accepted ? 'Đã chấp nhận' : 'Đã từ chối';
    final icon = accepted ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// State widgets
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyNotifState extends StatelessWidget {
  final bool isDark;
  const _EmptyNotifState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: ColorConstants.primaryColor.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_none_rounded,
                size: 42, color: ColorConstants.primaryColor.withOpacity(0.4)),
          ),
          const SizedBox(height: 20),
          Text(
            'Chưa có lời mời nào',
            style: TextStyle(
              color: isDark ? Colors.white54 : ColorConstants.greyColor,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Khi ai đó gửi lời mời kết bạn,\nbạn sẽ thấy ở đây',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: ColorConstants.greyColor, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _NotifSkeleton extends StatefulWidget {
  const _NotifSkeleton();

  @override
  State<_NotifSkeleton> createState() => _NotifSkeletonState();
}

class _NotifSkeletonState extends State<_NotifSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final c = isDark
            ? Color.lerp(ColorConstants.surfaceDark2, const Color(0xFF2E3448),
                _anim.value)!
            : Color.lerp(
                const Color(0xFFF0F2FF), const Color(0xFFE0E4F5), _anim.value)!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: List.generate(
              5,
              (_) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                            radius: 26, backgroundColor: c.withOpacity(0.5)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                  height: 13,
                                  width: 120,
                                  decoration: BoxDecoration(
                                      color: c.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(6))),
                              const SizedBox(height: 8),
                              Container(
                                  height: 10,
                                  width: 160,
                                  decoration: BoxDecoration(
                                      color: c.withOpacity(0.4),
                                      borderRadius: BorderRadius.circular(5))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                            child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                    color: c.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(12)))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                    color: c.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(12)))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  final bool isDark;
  const _CardSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = isDark ? ColorConstants.surfaceDark2 : const Color(0xFFF0F2FF);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: c, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          CircleAvatar(radius: 26, backgroundColor: c.withOpacity(0.5)),
          const SizedBox(width: 14),
          Expanded(
              child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                      color: c.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6)))),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: ColorConstants.greyColor),
            const SizedBox(height: 16),
            Text(error,
                style: const TextStyle(
                    color: ColorConstants.greyColor, fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

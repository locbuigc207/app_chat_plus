import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/game_match.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/pages/game_setup_page.dart';
import 'package:flutter_chat_demo/pages/match_room_page.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart'; // Bổ sung thư viện AuthProvider
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/services/game_firebase_service.dart';
import 'package:provider/provider.dart';

// ─── Design tokens ────────────────────────────────────────────────────────
abstract final class _C {
  static const bg = Color(0xFF0D0F14);
  static const surface = Color(0xFF141720);
  static const card = Color(0xFF181D2A);
  static const accent = Color(0xFF4F8EF7);
  static const live = Color(0xFF00E676);
  static const wait = Color(0xFFFFD740);
  static const text1 = Color(0xFFEEF2FF);
  static const text2 = Color(0xFF8B93B0);
  static const divider = Color(0xFF252A3A);
  static const caroGrad = [Color(0xFF667EEA), Color(0xFF764BA2)];
  static const chessGrad = [Color(0xFF11998E), Color(0xFF38EF7D)];
}

// =========================================================
// GAME CENTER HUB PAGE
// =========================================================

class GameCenterHubPage extends StatelessWidget {
  final String groupId;
  final String groupName;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const GameCenterHubPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final primary = context.watch<ThemeProvider>().primaryColor;

    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _C.bg,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildAppBar(context, primary),
            _buildBanner(primary),
            _buildGamesGrid(context, primary),
            _buildLiveSection(context, primary),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context, Color primary) {
    return SliverAppBar(
      backgroundColor: _C.bg,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      expandedHeight: 120,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: primary),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Game Center',
              style: TextStyle(
                color: _C.text1,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              groupName,
              style: const TextStyle(
                color: _C.text2,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Banner ────────────────────────────────────────────────────────────────

  Widget _buildBanner(Color primary) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              primary.withValues(alpha: 0.15),
              primary.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  Icon(Icons.sports_esports_rounded, color: primary, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thách đấu với thành viên',
                    style: TextStyle(
                      color: _C.text1,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Chọn game & thiết lập trận đấu ngay',
                    style: TextStyle(color: _C.text2, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Games Grid ────────────────────────────────────────────────────────────

  Widget _buildGamesGrid(BuildContext context, Color primary) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
        ),
        delegate: SliverChildListDelegate([
          _GameCard(
            title: 'Caro',
            subtitle: 'Gomoku / Tic-tac-toe',
            emoji: '⭕',
            gradient: _C.caroGrad,
            onTap: () {
              HapticFeedback.mediumImpact();
              _openSetup(context, GameType.caro);
            },
          ),
          _GameCard(
            title: 'Cờ Vua',
            subtitle: 'Chess classic',
            emoji: '♟️',
            gradient: _C.chessGrad,
            onTap: () {
              HapticFeedback.mediumImpact();
              _openSetup(context, GameType.chess);
            },
          ),
        ]),
      ),
    );
  }

  void _openSetup(BuildContext context, GameType type) {
    String validUserName = currentUserName;

// KHẮC PHỤC LỖI 18: Tự chữa lỗi nếu thông tin tên hiển thị bị kẹt do xử lý bất đồng bộ
    if (validUserName == 'Bạn' || validUserName.trim().isEmpty) {
      try {
        final authProvider = context.read<AuthProvider>();

        // Sử dụng currentUserName (đã định nghĩa trong AuthProvider)
        // hoặc lấy trực tiếp từ Firebase User làm phương án dự phòng
        validUserName = authProvider.currentUserName ??
            authProvider.firebaseAuth.currentUser?.displayName ??
            authProvider.userFirebaseId ??
            'Người dùng';
      } catch (_) {
        // Dự phòng lỗi unmounted/not found provider
        validUserName = 'Người dùng';
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameSetupPage(
          groupId: groupId,
          groupName: groupName,
          currentUserId: currentUserId,
          currentUserName: validUserName, // Gán tên chính xác
          currentUserAvatar: currentUserAvatar,
          preSelectedGameType: type,
        ),
      ),
    );
  }

  // ── Live Matches ──────────────────────────────────────────────────────────

  Widget _buildLiveSection(BuildContext context, Color primary) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Row(
              children: [
                const _LiveDot(),
                const SizedBox(width: 8),
                const Text(
                  'Đang diễn ra',
                  style: TextStyle(
                    color: _C.text1,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Trực tiếp',
                    style: TextStyle(
                      color: primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          StreamBuilder<List<GameMatch>>(
            stream: GameFirebaseService().watchLiveMatchesInGroup(groupId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(
                        color: _C.live, strokeWidth: 2),
                  ),
                );
              }

              final matches = snap.data ?? [];
              if (matches.isEmpty) {
                return const _EmptyLive();
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: matches.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _LiveMatchCard(
                  match: matches[i],
                  currentUserId: currentUserId,
                  primary: primary,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MatchRoomPage(
                          matchId: matches[i].matchId,
                          currentUserId: currentUserId,
                          currentUserName: currentUserName,
                          currentUserAvatar: currentUserAvatar,
                          groupId: groupId,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// =========================================================
// GAME CARD
// =========================================================

class _GameCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _GameCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.reverse(),
      onTapUp: (_) {
        _press.forward();
        widget.onTap();
      },
      onTapCancel: () => _press.forward(),
      child: ScaleTransition(
        scale: _press,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: widget.gradient.first.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.emoji, style: const TextStyle(fontSize: 34)),
                const Spacer(),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
// LIVE MATCH CARD
// =========================================================

class _LiveMatchCard extends StatelessWidget {
  final GameMatch match;
  final String currentUserId;
  final Color primary;
  final VoidCallback onTap;

  const _LiveMatchCard({
    required this.match,
    required this.currentUserId,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = match.isPlaying;
    final statusColor = isLive ? _C.live : _C.wait;
    final isInvolved =
        match.player1Id == currentUserId || match.player2Id == currentUserId;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isInvolved ? primary.withValues(alpha: 0.4) : _C.divider,
            width: isInvolved ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          children: [
            // Game type icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: match.gameType == GameType.caro
                      ? _C.caroGrad
                      : _C.chessGrad,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  match.gameType.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.hasOpponent
                        ? '${match.player1Name} vs ${match.player2Name}'
                        : '${match.player1Name} đang chờ...',
                    style: const TextStyle(
                      color: _C.text1,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.6),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isLive
                            ? 'Live • ${match.spectatorCount} đang xem'
                            : 'Chờ đối thủ',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // CTA
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (isLive ? _C.live : primary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (isLive ? _C.live : primary).withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                isLive ? 'Xem' : 'Vào bàn',
                style: TextStyle(
                  color: isLive ? _C.live : primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Supporting widgets ───────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _pulse,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: _C.live,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _EmptyLive extends StatelessWidget {
  const _EmptyLive();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Center(
        child: Column(
          children: [
            Text('🎮', style: TextStyle(fontSize: 36)),
            SizedBox(height: 10),
            Text(
              'Chưa có trận nào đang diễn ra',
              style: TextStyle(
                color: _C.text2,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Hãy là người đầu tiên thách đấu!',
              style: TextStyle(color: _C.text2, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

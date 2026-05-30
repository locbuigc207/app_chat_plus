import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/app_constants.dart';
import 'package:flutter_chat_demo/models/game_match.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/pages/match_room_page.dart';
import 'package:flutter_chat_demo/providers/chat_provider.dart';
import 'package:flutter_chat_demo/providers/game_state_provider.dart';
import 'package:flutter_chat_demo/services/chat_bubble_service.dart';
import 'package:flutter_chat_demo/services/game_firebase_service.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

// ─── Design tokens ────────────────────────────────────────────────────────
abstract final class _C {
  static const bg = Color(0xFF0D0F14);
  static const surface = Color(0xFF141720);
  static const card = Color(0xFF181D2A);
  static const accent = Color(0xFF4F8EF7);
  static const danger = Color(0xFFFF5A5A);
  static const text1 = Color(0xFFEEF2FF);
  static const text2 = Color(0xFF8B93B0);
  static const divider = Color(0xFF252A3A);
  static const caroGrad = [Color(0xFF667EEA), Color(0xFF764BA2)];
  static const chessGrad = [Color(0xFF11998E), Color(0xFF38EF7D)];
}

// =========================================================
// GAME SETUP PAGE
// =========================================================

class GameSetupPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final GameType? preSelectedGameType;

  /// Nếu khởi tạo từ thách đấu đích danh, truyền target user info
  final String? targetUserId;
  final String? targetUserName;

  const GameSetupPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    this.preSelectedGameType,
    this.targetUserId,
    this.targetUserName,
  });

  @override
  State<GameSetupPage> createState() => _GameSetupPageState();
}

class _GameSetupPageState extends State<GameSetupPage> {
  // ── State ─────────────────────────────────────────────────────────────────
  late GameType _gameType;
  int _timeControlIndex = 0; // index vào AppConstants.chessTimeControls
  int _turnTimerIndex = 0; // index vào AppConstants.caroTurnTimers
  ChessSide _side = ChessSide.random;
  int _boardMode = 0; // 0 = vô hạn, 1 = 3×3
  bool _isOpenChallenge = true; // false = đích danh

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _gameType = widget.preSelectedGameType ?? GameType.caro;
    if (widget.targetUserId != null) {
      _isOpenChallenge = false;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGameTypeSelector(),
            const SizedBox(height: 20),
            if (_gameType == GameType.chess) ...[
              _buildTimeControl(),
              const SizedBox(height: 20),
              _buildSideSelector(),
              const SizedBox(height: 20),
            ],
            if (_gameType == GameType.caro) ...[
              _buildCaroBoardMode(),
              const SizedBox(height: 20),
              _buildCaroTurnTimer(),
              const SizedBox(height: 20),
            ],
            _buildChallengeType(),
            const SizedBox(height: 32),
            _buildCTA(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: _C.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: _C.accent,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Thiết lập trận ${_gameType.displayName}',
          style: const TextStyle(
            color: _C.text1,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  // ── Game type ─────────────────────────────────────────────────────────────

  Widget _buildGameTypeSelector() => _Section(
        title: 'Chọn game',
        child: Row(
          children: [
            Expanded(
              child: _TypeChip(
                label: '⭕  Caro',
                selected: _gameType == GameType.caro,
                gradient: _C.caroGrad,
                onTap: () => setState(() => _gameType = GameType.caro),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TypeChip(
                label: '♟️  Cờ Vua',
                selected: _gameType == GameType.chess,
                gradient: _C.chessGrad,
                onTap: () => setState(() => _gameType = GameType.chess),
              ),
            ),
          ],
        ),
      );

  // ── Chess time control ────────────────────────────────────────────────────

  Widget _buildTimeControl() => _Section(
        title: 'Thời gian',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(
            AppConstants.chessTimeControlLabels.length,
            (i) => _OptionChip(
              label: AppConstants.chessTimeControlLabels[i],
              selected: _timeControlIndex == i,
              onTap: () => setState(() => _timeControlIndex = i),
            ),
          ),
        ),
      );

  // ── Chess side ────────────────────────────────────────────────────────────

  Widget _buildSideSelector() => _Section(
        title: 'Phe chơi',
        child: Row(
          children: [
            Expanded(
              child: _SideChip(
                label: '⬜  Trắng',
                selected: _side == ChessSide.white,
                onTap: () => setState(() => _side = ChessSide.white),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SideChip(
                label: '🎲  Ngẫu nhiên',
                selected: _side == ChessSide.random,
                onTap: () => setState(() => _side = ChessSide.random),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SideChip(
                label: '⬛  Đen',
                selected: _side == ChessSide.black,
                onTap: () => setState(() => _side = ChessSide.black),
              ),
            ),
          ],
        ),
      );

  // ── Caro board mode ───────────────────────────────────────────────────────

  Widget _buildCaroBoardMode() => _Section(
        title: 'Loại bàn cờ',
        child: Row(
          children: [
            Expanded(
              child: _OptionChip(
                label: '∞  Vô hạn (Gomoku)',
                selected: _boardMode == 0,
                onTap: () => setState(() => _boardMode = 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OptionChip(
                label: '3×3  Classic',
                selected: _boardMode == 1,
                onTap: () => setState(() => _boardMode = 1),
              ),
            ),
          ],
        ),
      );

  // ── Caro turn timer ───────────────────────────────────────────────────────

  Widget _buildCaroTurnTimer() => _Section(
        title: 'Thời gian mỗi nước',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(
            AppConstants.caroTurnTimerLabels.length,
            (i) => _OptionChip(
              label: AppConstants.caroTurnTimerLabels[i],
              selected: _turnTimerIndex == i,
              onTap: () => setState(() => _turnTimerIndex = i),
            ),
          ),
        ),
      );

  // ── Challenge type ────────────────────────────────────────────────────────

  Widget _buildChallengeType() => _Section(
        title: 'Kiểu thách đấu',
        child: Column(
          children: [
            _ChallengeRow(
              icon: Icons.public_rounded,
              title: 'Thách đấu mở',
              subtitle: 'Ai bấm vào đầu tiên sẽ là đối thủ',
              selected: _isOpenChallenge,
              onTap: () => setState(() => _isOpenChallenge = true),
            ),
            const SizedBox(height: 8),
            _ChallengeRow(
              icon: Icons.person_pin_rounded,
              title: widget.targetUserName != null
                  ? 'Thách đấu @${widget.targetUserName}'
                  : 'Thách đấu đích danh',
              subtitle: widget.targetUserId != null
                  ? 'Đã chọn: ${widget.targetUserName}'
                  : 'Chọn thành viên trong nhóm',
              selected: !_isOpenChallenge,
              onTap: () => setState(() => _isOpenChallenge = false),
            ),
          ],
        ),
      );

  // ── CTA ───────────────────────────────────────────────────────────────────

  Widget _buildCTA() => SizedBox(
        width: double.infinity,
        height: 52,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: _C.accent,
                  strokeWidth: 2,
                ),
              )
            : ElevatedButton(
                onPressed: _onCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _isOpenChallenge
                      ? 'Gửi thách đấu mở 🎮'
                      : 'Thách đấu ${widget.targetUserName ?? "đích danh"} 🎯',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      );

  // ── Create match ──────────────────────────────────────────────────────────

  Future<void> _onCreate() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final matchId = const Uuid().v4();
      final boardSize =
          _gameType == GameType.caro ? (_boardMode == 1 ? 3 : 0) : 0;
      final turnTimer = _gameType == GameType.caro
          ? AppConstants.caroTurnTimers[_turnTimerIndex]
          : 0;
      final timeControl = _gameType == GameType.chess
          ? AppConstants.chessTimeControls[_timeControlIndex]
          : 0;

      // 1. Tạo GameMatch document
      final match = GameStateProvider.buildNewMatch(
        matchId: matchId,
        gameType: _gameType,
        player1Id: widget.currentUserId,
        player1Name: widget.currentUserName,
        player1Avatar: widget.currentUserAvatar,
        sourceGroupId: widget.groupId,
        player1Side: _side,
        timeControlSeconds: timeControl,
        turnTimerSeconds: turnTimer,
        boardSize: boardSize,
        targetUserId: _isOpenChallenge ? null : widget.targetUserId,
        targetUserName: _isOpenChallenge ? null : widget.targetUserName,
      );

      await GameFirebaseService().createMatch(match);

      // 2. Gửi tin nhắn invite vào nhóm
      final chatProvider = context.read<ChatProvider>();
      final timeControlLabel = _gameType == GameType.chess
          ? AppConstants.chessTimeControlLabels[_timeControlIndex]
          : (turnTimer > 0
              ? AppConstants.caroTurnTimerLabels[_turnTimerIndex]
              : '');

      final payload = GameInvitePayload(
        matchId: matchId,
        gameType: _gameType,
        matchStatus: MatchStatus.waiting,
        challengerName: widget.currentUserName,
        challengerAvatar: widget.currentUserAvatar,
        targetUserId: _isOpenChallenge ? null : widget.targetUserId,
        targetUserName: _isOpenChallenge ? null : widget.targetUserName,
        timeControlSeconds: timeControl,
        boardSize: boardSize,
      );

      final msgId = await chatProvider.sendGameInviteMessage(
        groupChatId: widget.groupId,
        currentUserId: widget.currentUserId,
        payload: payload,
      );

      // 3. Link tin nhắn invite với match document
      await GameFirebaseService().linkInviteMessage(matchId, msgId);

      // 4. Push notification nếu thách đấu đích danh
      if (!_isOpenChallenge && widget.targetUserId != null) {
        await ChatBubbleService().sendGameChallengeNotification(
          targetUserId: widget.targetUserId!,
          challengerName: widget.currentUserName,
          challengerAvatar: widget.currentUserAvatar,
          matchId: matchId,
          groupId: widget.groupId,
          gameType: _gameType.name,
          timeControlLabel: timeControlLabel,
        );
      }

      if (!mounted) return;

      // 5. Navigate vào phòng đấu
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MatchRoomPage(
            matchId: matchId,
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            currentUserAvatar: widget.currentUserAvatar,
            groupId: widget.groupId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể tạo trận: $e'),
            backgroundColor: _C.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// =========================================================
// REUSABLE SMALL WIDGETS
// =========================================================

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _C.text2,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      );
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            gradient: selected ? LinearGradient(colors: gradient) : null,
            color: selected ? null : _C.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.transparent : _C.divider,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _C.text2,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _C.accent.withOpacity(0.15) : _C.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _C.accent : _C.divider,
              width: selected ? 1.5 : 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _C.accent : _C.text2,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _SideChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SideChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          decoration: BoxDecoration(
            color: selected ? _C.accent.withOpacity(0.15) : _C.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _C.accent : _C.divider,
              width: selected ? 1.5 : 0.8,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? _C.accent : _C.text2,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
}

class _ChallengeRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChallengeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? _C.accent.withOpacity(0.08) : _C.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _C.accent.withOpacity(0.5) : _C.divider,
              width: selected ? 1.5 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? _C.accent : _C.text2, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected ? _C.text1 : _C.text2,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _C.text2,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    color: _C.accent, size: 20),
            ],
          ),
        ),
      );
}

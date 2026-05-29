import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class TicTacToeMessageWidget extends StatefulWidget {
  final String content;
  final String messageId;
  final String groupId;
  final String currentUserId;

  const TicTacToeMessageWidget({
    super.key,
    required this.content,
    required this.messageId,
    required this.groupId,
    required this.currentUserId,
  });

  @override
  State<TicTacToeMessageWidget> createState() => _TicTacToeMessageWidgetState();
}

class _TicTacToeMessageWidgetState extends State<TicTacToeMessageWidget>
    with TickerProviderStateMixin {
  late AnimationController _winLineController;
  late AnimationController _boardAppear;
  late AnimationController _cellBounce;
  late Animation<double> _winLineDraw;
  late Animation<double> _boardScale;

  final List<AnimationController> _cellControllers = [];
  int? _lastTappedIndex;
  List<int> _winningLine = [];

  @override
  void initState() {
    super.initState();

    _winLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _boardAppear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _cellBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _winLineDraw = CurvedAnimation(
      parent: _winLineController,
      curve: Curves.easeOut,
    );
    _boardScale = CurvedAnimation(
      parent: _boardAppear,
      curve: Curves.elasticOut,
    );

    for (int i = 0; i < 9; i++) {
      _cellControllers.add(AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      ));
    }

    final state = jsonDecode(widget.content) as Map<String, dynamic>;
    final board = List<String>.from(state['board'] ?? List.filled(9, ''));
    final line = _getWinningLine(board);
    if (line != null) {
      _winningLine = line;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _winLineController.forward();
      });
    }
  }

  @override
  void dispose() {
    _winLineController.dispose();
    _boardAppear.dispose();
    _cellBounce.dispose();
    for (final c in _cellControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _onCellTapped(int index, Map<String, dynamic> gameState) async {
    List<dynamic> board = List.from(gameState['board']);
    String turn = gameState['turn'] ?? '';
    String winner = gameState['winner'] ?? '';
    String playerX = gameState['playerX'] ?? '';
    String playerO = gameState['playerO'] ?? '';

    if (winner.isNotEmpty || board[index].toString().isNotEmpty) return;

    if (playerX.isEmpty) {
      playerX = widget.currentUserId;
      turn = widget.currentUserId;
    } else if (playerO.isEmpty && playerX != widget.currentUserId) {
      playerO = widget.currentUserId;
    }

    if (turn != widget.currentUserId) return;

    final mySymbol = (widget.currentUserId == playerX) ? 'X' : 'O';
    board[index] = mySymbol;

    if (index < _cellControllers.length) {
      _cellControllers[index].forward(from: 0);
    }
    setState(() => _lastTappedIndex = index);

    final newWinner = _checkWinner(board);
    final winLine = _getWinningLine(board);

    final nextTurn =
        (widget.currentUserId == playerX) ? (playerO.isEmpty ? playerX : playerO) : playerX;

    final newState = {
      'board': board,
      'turn': newWinner.isNotEmpty ? '' : nextTurn,
      'winner': newWinner,
      'playerX': playerX,
      'playerO': playerO,
    };

    await FirebaseFirestore.instance
        .collection('messages')
        .doc(widget.groupId)
        .collection(widget.groupId)
        .doc(widget.messageId)
        .update({'content': jsonEncode(newState)});

    if (winLine != null) {
      setState(() => _winningLine = winLine);
      _winLineController.forward(from: 0);
    }
  }

  String _checkWinner(List<dynamic> b) {
    final line = _getWinningLine(b);
    if (line != null) return b[line[0]].toString();
    if (!b.contains('')) return 'Hòa';
    return '';
  }

  List<int>? _getWinningLine(List<dynamic> b) {
    const lines = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (final l in lines) {
      if (b[l[0]] != '' && b[l[0]] == b[l[1]] && b[l[1]] == b[l[2]]) {
        return l;
      }
    }
    return null;
  }

  bool _isMyturn(Map<String, dynamic> state) {
    return (state['turn'] ?? '') == widget.currentUserId;
  }

  String _mySymbol(Map<String, dynamic> state) {
    if (state['playerX'] == widget.currentUserId) return 'X';
    if (state['playerO'] == widget.currentUserId) return 'O';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('messages')
          .doc(widget.groupId)
          .collection(widget.groupId)
          .doc(widget.messageId)
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, dynamic> gameState;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          gameState = jsonDecode(data['content']) as Map<String, dynamic>;
        } else {
          gameState = jsonDecode(widget.content) as Map<String, dynamic>;
        }

        final board = List<String>.from(gameState['board'] ?? List.filled(9, ''));
        final winner = gameState['winner'] ?? '';
        final myTurn = _isMyturn(gameState);
        final symbol = _mySymbol(gameState);

        return ScaleTransition(
          scale: _boardScale,
          child: Container(
            width: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F3460).withValues(alpha: 0.55),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(winner, myTurn, symbol, gameState),
                  _buildGrid(board, winner, gameState),
                  _buildFooter(gameState, winner),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(String winner, bool myTurn, String symbol, Map<String, dynamic> state) {
    String statusText;
    Color statusColor;

    if (winner == 'Hòa') {
      statusText = '🤝 Hòa nhau!';
      statusColor = const Color(0xFFFFD700);
    } else if (winner.isNotEmpty) {
      final isIWon = (winner == 'X' && state['playerX'] == widget.currentUserId) ||
          (winner == 'O' && state['playerO'] == widget.currentUserId);
      statusText = isIWon ? '🏆 Bạn thắng!' : '💀 Bạn thua!';
      statusColor = isIWon ? const Color(0xFF00E676) : const Color(0xFFFF5252);
    } else if (symbol.isEmpty) {
      statusText = '👀 Đang chờ...';
      statusColor = Colors.white60;
    } else if (myTurn) {
      statusText = 'Lượt của bạn ($symbol)';
      statusColor = const Color(0xFF64FFDA);
    } else {
      statusText = 'Đợi đối thủ...';
      statusColor = Colors.white38;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF0F3460), width: 1.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.7), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Text(
            'Cờ 3×3',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<String> board, String winner, Map<String, dynamic> gameState) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Stack(
        children: [
          Column(
            children: List.generate(3, (row) {
              return Row(
                children: List.generate(3, (col) {
                  final index = row * 3 + col;
                  final isWinCell = _winningLine.contains(index);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3.5),
                      child: _buildCell(index, board[index], winner, isWinCell, gameState),
                    ),
                  );
                }),
              );
            }),
          ),
          if (_winningLine.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _winLineDraw,
                  builder: (_, __) => CustomPaint(
                    painter: _WinLinePainter(
                      winLine: _winningLine,
                      progress: _winLineDraw.value,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(
      int index, String value, String winner, bool isWinCell, Map<String, dynamic> gameState) {
    final canTap = winner.isEmpty && value.isEmpty && _isMyturn(gameState);

    return GestureDetector(
      onTap: canTap ? () => _onCellTapped(index, gameState) : null,
      child: AnimatedBuilder(
        animation: _cellControllers[index],
        builder: (_, __) {
          final t = _cellControllers[index].value;
          final scale = 1.0 + sin(t * pi) * 0.18;
          return Transform.scale(
            scale: scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isWinCell
                    ? const Color(0xFF0F3460)
                    : value.isNotEmpty
                        ? const Color(0xFF0A0A1A)
                        : canTap
                            ? const Color(0xFF0D0D22)
                            : const Color(0xFF0A0A1A),
                border: Border.all(
                  color: isWinCell
                      ? const Color(0xFF64FFDA).withValues(alpha: 0.6)
                      : const Color(0xFF0F3460).withValues(alpha: 0.6),
                  width: isWinCell ? 1.8 : 1.2,
                ),
                boxShadow: isWinCell
                    ? [
                        BoxShadow(
                          color: const Color(0xFF64FFDA).withValues(alpha: 0.18),
                          blurRadius: 10,
                        )
                      ]
                    : canTap
                        ? [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.04),
                              blurRadius: 4,
                            )
                          ]
                        : [],
              ),
              child: Center(
                child: value.isEmpty
                    ? (canTap
                        ? const Icon(Icons.add, color: Colors.white12, size: 20)
                        : const SizedBox())
                    : _buildSymbol(value, isWinCell),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSymbol(String symbol, bool isWinCell) {
    if (symbol == 'X') {
      return CustomPaint(
        size: const Size(28, 28),
        painter: _XPainter(
          color: isWinCell ? const Color(0xFFFF8A80) : const Color(0xFFFF5252),
          strokeWidth: 3.0,
        ),
      );
    } else {
      return CustomPaint(
        size: const Size(28, 28),
        painter: _OPainter(
          color: isWinCell ? const Color(0xFF80D8FF) : const Color(0xFF40C4FF),
          strokeWidth: 3.0,
        ),
      );
    }
  }

  Widget _buildFooter(Map<String, dynamic> state, String winner) {
    final playerX = state['playerX'] ?? '';
    final playerO = state['playerO'] ?? '';
    final isX = playerX == widget.currentUserId;
    final isO = playerO == widget.currentUserId;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF0F3460), width: 1.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildPlayerChip('X', playerX, isX, const Color(0xFFFF5252)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'VS',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          _buildPlayerChip('O', playerO, isO, const Color(0xFF40C4FF)),
        ],
      ),
    );
  }

  Widget _buildPlayerChip(String symbol, String userId, bool isMe, Color color) {
    final isEmpty = userId.isEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isMe ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMe ? color.withValues(alpha: 0.4) : Colors.white12,
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            symbol,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isEmpty ? '?' : (isMe ? 'Bạn' : 'Đối thủ'),
            style: TextStyle(
              color: isEmpty ? Colors.white24 : Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _XPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _XPainter({required this.color, this.strokeWidth = 3.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final pad = size.width * 0.1;
    canvas.drawLine(Offset(pad, pad), Offset(size.width - pad, size.height - pad), paint);
    canvas.drawLine(Offset(size.width - pad, pad), Offset(pad, size.height - pad), paint);
  }

  @override
  bool shouldRepaint(_XPainter old) => old.color != color || old.strokeWidth != strokeWidth;
}

class _OPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _OPainter({required this.color, this.strokeWidth = 3.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) * 0.78;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_OPainter old) => old.color != color || old.strokeWidth != strokeWidth;
}

class _WinLinePainter extends CustomPainter {
  final List<int> winLine;
  final double progress;

  _WinLinePainter({required this.winLine, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (winLine.isEmpty || progress <= 0) return;

    final cellW = size.width / 3;
    final cellH = size.height / 3;

    Offset cellCenter(int idx) {
      final row = idx ~/ 3;
      final col = idx % 3;
      return Offset(col * cellW + cellW / 2, row * cellH + cellH / 2);
    }

    final start = cellCenter(winLine.first);
    final end = cellCenter(winLine.last);

    final current = Offset.lerp(start, end, progress)!;

    final paint = Paint()
      ..color = const Color(0xFF64FFDA).withValues(alpha: 0.85)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawLine(start, current, paint);
  }

  @override
  bool shouldRepaint(_WinLinePainter old) => old.progress != progress || old.winLine != winLine;
}

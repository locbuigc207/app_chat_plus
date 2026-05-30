import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/providers/game_state_provider.dart';

// ─── Design tokens (khớp dark theme của group_chat_page) ─────────────────
abstract final class _C {
  static const bg = Color(0xFF0D0F14);
  static const gridLine = Color(0xFF1E2340);
  static const gridLineSub = Color(0xFF151828);
  static const cellX = Color(0xFFFF5252);
  static const cellO = Color(0xFF40C4FF);
  static const cellXGlow = Color(0x40FF5252);
  static const cellOGlow = Color(0x4040C4FF);
  static const lastMoveRing = Color(0xFF64FFDA);
  static const winLineColor = Color(0xFF64FFDA);
  static const hintColor = Color(0xFF2A3050);
  static const coordColor = Color(0xFF3A4060);
}

// ─── Cell size constant ───────────────────────────────────────────────────
const double _kCellSize = 44.0;
const double _kStroke = 2.0;
const double _kPieceR = 14.0;

// =========================================================
// CARO INFINITE BOARD
// =========================================================

/// Bàn cờ Caro vô hạn (Gomoku) với InteractiveViewer (pan + zoom).
///
/// Dùng cho:
///   - [boardSize] == 0 → bàn vô hạn (Gomoku 5-liên)
///   - [boardSize] == 3 → bàn 3×3 cố định (Tic-tac-toe, không cần scroll)
///
/// [onTap]   : callback khi player tap ô hợp lệ (row, col)
/// [isMyTurn]: khóa tương tác khi không phải lượt mình
class CaroInfiniteBoard extends StatefulWidget {
  final Map<String, String> board; // key: 'row,col', value: 'X'|'O'
  final CaroCell? lastMove;
  final List<CaroCell> winLine;
  final bool isMyTurn;
  final bool isGameOver;
  final int boardSize; // 0 = vô hạn, 3 = 3x3
  final void Function(int row, int col) onTap;
  final String mySymbol; // 'X' hoặc 'O'

  const CaroInfiniteBoard({
    super.key,
    required this.board,
    required this.onTap,
    required this.isMyTurn,
    required this.isGameOver,
    required this.mySymbol,
    this.lastMove,
    this.winLine = const [],
    this.boardSize = 0,
  });

  @override
  State<CaroInfiniteBoard> createState() => _CaroInfiniteBoardState();
}

class _CaroInfiniteBoardState extends State<CaroInfiniteBoard>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transform;
  late final AnimationController _winAnim;
  late Animation<double> _winProgress;

  // Kích thước grid (ô) hiển thị cho bàn vô hạn
  static const int _visibleGrid = 21; // 21×21 ô trung tâm
  // Offset để row/col 0 nằm ở giữa grid (-10..+10)
  static const int _origin = 10;

  @override
  void initState() {
    super.initState();
    _transform = TransformationController();
    _winAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _winProgress = CurvedAnimation(parent: _winAnim, curve: Curves.easeOut);

    // Center board on init
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerBoard());
  }

  @override
  void didUpdateWidget(CaroInfiniteBoard old) {
    super.didUpdateWidget(old);
    // Khi có win line mới → animate
    if (widget.winLine.isNotEmpty && old.winLine.isEmpty) {
      _winAnim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    _winAnim.dispose();
    super.dispose();
  }

  void _centerBoard() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final boardPx = _visibleGrid * _kCellSize;
    final dx = (size.width - boardPx) / 2;
    final dy = (size.height - boardPx) / 2 - 60;
    _transform.value = Matrix4.identity()..translate(dx, dy.clamp(0.0, dy));
  }

  // ── Coordinate helpers ────────────────────────────────────────────────────

  /// Chuyển tap position → (row, col) trong hệ tọa độ game.
  (int row, int col)? _tapToCell(Offset local) {
    final m = _transform.value;
    final inv = Matrix4.inverted(m);
    final transformed = MatrixUtils.transformPoint(inv, local);
    final gridCol = (transformed.dx / _kCellSize).floor();
    final gridRow = (transformed.dy / _kCellSize).floor();

    if (widget.boardSize == 3) {
      if (gridRow < 0 || gridRow >= 3 || gridCol < 0 || gridCol >= 3) {
        return null;
      }
      return (gridRow, gridCol);
    }

    // Vô hạn: chuyển về game coordinates
    final gameRow = gridRow - _origin;
    final gameCol = gridCol - _origin;
    return (gameRow, gameCol);
  }

  /// Chuyển (row, col) game → pixel top-left trên canvas.
  Offset _cellToPixel(int row, int col) {
    if (widget.boardSize == 3) {
      return Offset(col * _kCellSize, row * _kCellSize);
    }
    return Offset(
      (col + _origin) * _kCellSize,
      (row + _origin) * _kCellSize,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.boardSize == 3) {
      return _buildFixed3x3();
    }
    return _buildInfinite();
  }

  // ── 3×3 fixed ─────────────────────────────────────────────────────────────

  Widget _buildFixed3x3() {
    const size = 3 * _kCellSize;
    return Center(
      child: GestureDetector(
        onTapUp: (d) {
          if (!widget.isMyTurn || widget.isGameOver) return;
          final cell = _tapToCell(d.localPosition);
          if (cell != null) {
            HapticFeedback.lightImpact();
            widget.onTap(cell.$1, cell.$2);
          }
        },
        child: AnimatedBuilder(
          animation: _winProgress,
          builder: (_, __) => CustomPaint(
            size: const Size(size, size),
            painter: _BoardPainter(
              board: widget.board,
              lastMove: widget.lastMove,
              winLine: widget.winLine,
              winProgress: _winProgress.value,
              boardSize: 3,
              origin: 0,
              cellSize: _kCellSize,
              mySymbol: widget.mySymbol,
              isMyTurn: widget.isMyTurn && !widget.isGameOver,
            ),
          ),
        ),
      ),
    );
  }

  // ── Infinite ──────────────────────────────────────────────────────────────

  Widget _buildInfinite() {
    final boardPx = _visibleGrid * _kCellSize;
    return ClipRect(
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 0.4,
        maxScale: 2.5,
        constrained: false,
        child: GestureDetector(
          onTapUp: (d) {
            if (!widget.isMyTurn || widget.isGameOver) return;
            final cell = _tapToCell(d.localPosition);
            if (cell != null) {
              HapticFeedback.lightImpact();
              widget.onTap(cell.$1, cell.$2);
            }
          },
          child: AnimatedBuilder(
            animation: _winProgress,
            builder: (_, __) => CustomPaint(
              size: Size(boardPx, boardPx),
              painter: _BoardPainter(
                board: widget.board,
                lastMove: widget.lastMove,
                winLine: widget.winLine,
                winProgress: _winProgress.value,
                boardSize: 0,
                origin: _origin,
                cellSize: _kCellSize,
                mySymbol: widget.mySymbol,
                isMyTurn: widget.isMyTurn && !widget.isGameOver,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
// BOARD PAINTER
// =========================================================

class _BoardPainter extends CustomPainter {
  final Map<String, String> board;
  final CaroCell? lastMove;
  final List<CaroCell> winLine;
  final double winProgress;
  final int boardSize; // 0 = infinite, 3 = 3x3
  final int origin;
  final double cellSize;
  final String mySymbol;
  final bool isMyTurn;

  const _BoardPainter({
    required this.board,
    required this.lastMove,
    required this.winLine,
    required this.winProgress,
    required this.boardSize,
    required this.origin,
    required this.cellSize,
    required this.mySymbol,
    required this.isMyTurn,
  });

  // ── Grid lines ────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawPieces(canvas);
    if (winLine.isNotEmpty) _drawWinLine(canvas);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final cols = boardSize == 3 ? 3 : (size.width / cellSize).ceil() + 1;
    final rows = boardSize == 3 ? 3 : (size.height / cellSize).ceil() + 1;

    final mainPaint = Paint()
      ..color = _C.gridLine
      ..strokeWidth = 0.8;
    final subPaint = Paint()
      ..color = _C.gridLineSub
      ..strokeWidth = 0.4;

    for (int c = 0; c <= cols; c++) {
      final x = c * cellSize;
      // Thick line every 5
      final paint = (c % 5 == 0) ? mainPaint : subPaint;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int r = 0; r <= rows; r++) {
      final y = r * cellSize;
      final paint = (r % 5 == 0) ? mainPaint : subPaint;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Center dot
    if (boardSize == 0) {
      canvas.drawCircle(
        Offset(origin * cellSize, origin * cellSize),
        3,
        Paint()..color = _C.gridLine,
      );
    }
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

  void _drawPieces(Canvas canvas) {
    for (final entry in board.entries) {
      final parts = entry.key.split(',');
      if (parts.length != 2) continue;
      final row = int.tryParse(parts[0]);
      final col = int.tryParse(parts[1]);
      if (row == null || col == null) continue;

      final px = boardSize == 3
          ? Offset(col * cellSize + cellSize / 2, row * cellSize + cellSize / 2)
          : Offset(
              (col + origin) * cellSize + cellSize / 2,
              (row + origin) * cellSize + cellSize / 2,
            );

      final isLast = lastMove?.row == row && lastMove?.col == col;
      _drawPiece(canvas, px, entry.value, isLast);
    }
  }

  void _drawPiece(Canvas canvas, Offset center, String symbol, bool isLast) {
    final isX = symbol == 'X';
    final color = isX ? _C.cellX : _C.cellO;
    final glow = isX ? _C.cellXGlow : _C.cellOGlow;

    // Glow
    if (isLast) {
      canvas.drawCircle(center, _kPieceR + 8, Paint()..color = glow);
    }

    // Shadow
    canvas.drawCircle(
      center + const Offset(0, 2),
      _kPieceR,
      Paint()..color = Colors.black38,
    );

    if (isX) {
      _drawX(canvas, center, color);
    } else {
      _drawO(canvas, center, color);
    }

    // Last move ring
    if (isLast) {
      canvas.drawCircle(
        center,
        _kPieceR + 4,
        Paint()
          ..color = _C.lastMoveRing
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawX(Canvas canvas, Offset center, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _kStroke + 0.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final r = _kPieceR * 0.65;
    canvas.drawLine(
      Offset(center.dx - r, center.dy - r),
      Offset(center.dx + r, center.dy + r),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + r, center.dy - r),
      Offset(center.dx - r, center.dy + r),
      paint,
    );
  }

  void _drawO(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(
      center,
      _kPieceR * 0.7,
      Paint()
        ..color = color
        ..strokeWidth = _kStroke + 0.5
        ..style = PaintingStyle.stroke,
    );
  }

  // ── Win line ──────────────────────────────────────────────────────────────

  void _drawWinLine(Canvas canvas) {
    if (winLine.length < 2 || winProgress <= 0) return;

    final first = winLine.first;
    final last = winLine.last;

    Offset cellCenter(CaroCell c) => boardSize == 3
        ? Offset(
            c.col * cellSize + cellSize / 2, c.row * cellSize + cellSize / 2)
        : Offset(
            (c.col + origin) * cellSize + cellSize / 2,
            (c.row + origin) * cellSize + cellSize / 2,
          );

    final start = cellCenter(first);
    final end = cellCenter(last);
    final current = Offset.lerp(start, end, winProgress)!;

    // Glow pass
    canvas.drawLine(
      start,
      current,
      Paint()
        ..color = _C.winLineColor.withOpacity(0.3)
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Core
    canvas.drawLine(
      start,
      current,
      Paint()
        ..color = _C.winLineColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.board != board ||
      old.lastMove != lastMove ||
      old.winLine != winLine ||
      old.winProgress != winProgress ||
      old.isMyTurn != isMyTurn;
}

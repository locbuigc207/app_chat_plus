// lib/widgets/chess_board_widget.dart
//
// Classic wooden chess board — full feature set:
//   • Realtime 2-player via Firestore (GameStateProvider)
//   • Piece drag + tap to move
//   • Legal move highlight (dot/circle overlay)
//   • Last move highlight (amber wash)
//   • King in check highlight (red pulse)
//   • Promotion dialog (Queen / Rook / Bishop / Knight)
//   • Chess clock display (integrated, driven by provider)
//   • Move history panel (collapsible, algebraic notation)
//   • Flip board for black player
//   • Unicode chess pieces — no asset dependency
//   • En passant, castling, 50-move draw detection via `chess` package

import 'dart:async';

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Design tokens — Classic Wooden ──────────────────────────────────────────
abstract final class _CW {
  // Board squares
  static const lightSquare = Color(0xFFF0D9B5);
  static const darkSquare = Color(0xFFB58863);
  static const lightSquareH = Color(0xFFCDD16E); // last-move light
  static const darkSquareH = Color(0xFFAAA23A); // last-move dark
  static const selectedSq = Color(0xFF7FC97F);
  static const checkSq = Color(0xFFE63946);

  // Frame / panel
  static const frame = Color(0xFF6B3A2A);
  static const frameDark = Color(0xFF4A2518);
  static const coordColor = Color(0xFFD4A96A);
  static const panelBg = Color(0xFF2C1810);
  static const panelSurface = Color(0xFF3D2314);

  // Text
  static const text1 = Color(0xFFF5E6D3);
  static const text2 = Color(0xFFB8956A);
  static const textDim = Color(0xFF7A5C40);

  // Legal move dot
  static const legalDot = Color(0x55000000);
  static const legalCapture = Color(0x44E63946);

  // Clock
  static const clockActive = Color(0xFFF5E6D3);
  static const clockIdle = Color(0xFF7A5C40);
  static const clockLow = Color(0xFFE63946);

  // Pieces (Unicode)
  static const pieceWhite = Color(0xFFFFFAF0);
  static const pieceBlack = Color(0xFF1A0A00);
}

// ─── Unicode piece map ────────────────────────────────────────────────────────
const Map<String, String> _kPieceUnicode = {
  'wK': '♔',
  'wQ': '♕',
  'wR': '♖',
  'wB': '♗',
  'wN': '♘',
  'wP': '♙',
  'bK': '♚',
  'bQ': '♛',
  'bR': '♜',
  'bB': '♝',
  'bN': '♞',
  'bP': '♟',
};

// ─── Move record for history panel ───────────────────────────────────────────
class _MoveRecord {
  final int number;
  final String white;
  final String black;
  const _MoveRecord({
    required this.number,
    required this.white,
    this.black = '',
  });
}

// ─── Promotion piece ──────────────────────────────────────────────────────────
enum _PromoPiece { queen, rook, bishop, knight }

// =============================================================================
// CHESS BOARD WIDGET
// =============================================================================

class ChessBoardWidget extends StatefulWidget {
  /// FEN string — drives the entire board state.
  final String fen;

  /// 'white' or 'black' — perspective for this player.
  final String myColor;

  /// Is it currently this player's turn?
  final bool isMyTurn;

  /// Has the game ended?
  final bool isGameOver;

  /// Callback when a legal move is made. Receives UCI string e.g. "e2e4", "e7e8q".
  final void Function(String uci)? onMove;

  /// Last move UCI for highlighting.
  final String? lastMoveUci;

  /// Whether to show move history panel.
  final bool showHistory;

  /// Full move history in SAN notation (from provider).
  final List<String> sanHistory;

  const ChessBoardWidget({
    super.key,
    required this.fen,
    required this.myColor,
    this.isMyTurn = false,
    this.isGameOver = false,
    this.onMove,
    this.lastMoveUci,
    this.showHistory = true,
    this.sanHistory = const [],
  });

  @override
  State<ChessBoardWidget> createState() => _ChessBoardWidgetState();
}

class _ChessBoardWidgetState extends State<ChessBoardWidget>
    with TickerProviderStateMixin {
  // ── Chess engine instance ──────────────────────────────────────────────────
  late ch.Chess _chess;

  // ── Selection state ────────────────────────────────────────────────────────
  String? _selectedSquare; // e.g. "e2"
  List<String> _legalTargets = [];
  Set<String> _legalCaptures = {};

  // ── Drag state ────────────────────────────────────────────────────────────
  String? _dragSquare;
  Offset? _dragOffset;
  String? _dragPiece; // e.g. 'wP'

  // ── Cache & Animation ─────────────────────────────────────────────────────
  String? _cachedCheckedKingSq;
  late AnimationController _checkPulse;
  late Animation<double> _checkAnim;

  // ── History scroll ────────────────────────────────────────────────────────
  final ScrollController _historyScroll = ScrollController();
  bool _historyExpanded = true;

  // ── Board layout ──────────────────────────────────────────────────────────
  double _squareSize = 44.0;
  final GlobalKey _boardKey = GlobalKey();

  bool get _flipped => widget.myColor == 'black';

  @override
  void initState() {
    super.initState();
    _chess = ch.Chess.fromFEN(widget.fen);
    _updateCachedCheck();

    _checkPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _checkAnim = Tween<double>(
      begin: 0.3,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _checkPulse, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(ChessBoardWidget old) {
    super.didUpdateWidget(old);
    if (old.fen != widget.fen) {
      _chess = ch.Chess.fromFEN(widget.fen);
      _updateCachedCheck();

      _selectedSquare = null;
      _legalTargets = [];
      _legalCaptures = {};
      _dragSquare = null;
      _dragPiece = null;

      // Scroll history to bottom when new move arrives
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollHistoryToBottom(),
      );
    }
  }

  @override
  void dispose() {
    _checkPulse.dispose();
    _historyScroll.dispose();
    super.dispose();
  }

  // ── Square utils ──────────────────────────────────────────────────────────

  /// Convert display (col, row) → algebraic square name.
  String _displayToSquare(int displayCol, int displayRow) {
    final col = _flipped ? 7 - displayCol : displayCol;
    final row = _flipped ? displayRow : 7 - displayRow;
    return '${String.fromCharCode(97 + col)}${row + 1}';
  }

  /// Convert square name → display (col, row).
  (int col, int row) _squareToDisplay(String sq) {
    final col = sq.codeUnitAt(0) - 97;
    final row = int.parse(sq[1]) - 1;
    final displayCol = _flipped ? 7 - col : col;
    final displayRow = _flipped ? row : 7 - row;
    return (displayCol, displayRow);
  }

  /// Get piece key at square, e.g. 'wP'.
  String? _pieceAt(String sq) {
    final piece = _chess.get(sq);
    if (piece == null) return null;
    final color = piece.color == ch.Color.WHITE ? 'w' : 'b';
    return '$color${piece.type.toUpperCase()}';
  }

  String? _kingSquare(bool white) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final sq = '${String.fromCharCode(97 + c)}${r + 1}';
        final p = _chess.get(sq);
        if (p != null &&
            p.type == ch.PieceType.KING &&
            (white ? p.color == ch.Color.WHITE : p.color == ch.Color.BLACK)) {
          return sq;
        }
      }
    }
    return null;
  }

  void _updateCachedCheck() {
    _cachedCheckedKingSq = _chess.in_check
        ? _kingSquare(_chess.turn == ch.Color.WHITE)
        : null;
  }

  // ── Legal move calculation ─────────────────────────────────────────────────

  void _selectSquare(String sq) {
    if (!widget.isMyTurn || widget.isGameOver) return;

    final piece = _chess.get(sq);
    final myColorEnum = widget.myColor == 'white'
        ? ch.Color.WHITE
        : ch.Color.BLACK;

    // Clicked own piece → select
    if (piece != null && piece.color == myColorEnum) {
      final moves = _chess.generate_moves({'square': sq});
      setState(() {
        _selectedSquare = sq;
        _legalTargets = moves
            .map((m) => m.toAlgebraic.substring(2, 4))
            .toList();
        _legalCaptures = moves
            .where((m) => m.flags & ch.Chess.BITS_CAPTURE != 0)
            .map((m) => m.toAlgebraic.substring(2, 4))
            .toSet();
      });
      return;
    }

    // Clicked legal target → attempt move
    if (_selectedSquare != null && _legalTargets.contains(sq)) {
      _attemptMove(_selectedSquare!, sq);
      return;
    }

    // Deselect
    setState(() {
      _selectedSquare = null;
      _legalTargets = [];
      _legalCaptures = {};
    });
  }

  void _attemptMove(String from, String to) {
    // Check promotion
    final piece = _chess.get(from);
    final isPawnPromo =
        piece != null &&
        piece.type == ch.PieceType.PAWN &&
        ((widget.myColor == 'white' && to[1] == '8') ||
            (widget.myColor == 'black' && to[1] == '1'));

    if (isPawnPromo) {
      _showPromoDialog(from, to);
      return;
    }

    _commitMove(from, to, null);
  }

  void _commitMove(String from, String to, String? promo) {
    String uci = '$from$to';
    if (promo != null) uci += promo;

    setState(() {
      _selectedSquare = null;
      _legalTargets = [];
      _legalCaptures = {};
      _dragSquare = null;
      _dragPiece = null;
    });

    HapticFeedback.mediumImpact();
    widget.onMove?.call(uci);
  }

  // ── Promotion dialog ──────────────────────────────────────────────────────

  Future<void> _showPromoDialog(String from, String to) async {
    final result = await showDialog<_PromoPiece>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => _PromotionDialog(isWhite: widget.myColor == 'white'),
    );
    if (!mounted) return;
    final promoChar = switch (result ?? _PromoPiece.queen) {
      _PromoPiece.queen => 'q',
      _PromoPiece.rook => 'r',
      _PromoPiece.bishop => 'b',
      _PromoPiece.knight => 'n',
    };
    _commitMove(from, to, promoChar);
  }

  // ── Drag handlers ─────────────────────────────────────────────────────────

  void _onDragStart(String sq, Offset globalPos) {
    if (!widget.isMyTurn || widget.isGameOver) return;
    final piece = _chess.get(sq);
    final myColorEnum = widget.myColor == 'white'
        ? ch.Color.WHITE
        : ch.Color.BLACK;
    if (piece == null || piece.color != myColorEnum) return;

    final moves = _chess.generate_moves({'square': sq});
    HapticFeedback.lightImpact();
    setState(() {
      _dragSquare = sq;
      _dragOffset = globalPos;
      _dragPiece =
          '${piece.color == ch.Color.WHITE ? 'w' : 'b'}${piece.type.toUpperCase()}';
      _selectedSquare = sq;
      _legalTargets = moves.map((m) => m.toAlgebraic.substring(2, 4)).toList();
      _legalCaptures = moves
          .where((m) => m.flags & ch.Chess.BITS_CAPTURE != 0)
          .map((m) => m.toAlgebraic.substring(2, 4))
          .toSet();
    });
  }

  void _onDragEnd(Offset globalPos) {
    if (_dragSquare == null) return;
    final renderBox =
        _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final local = renderBox.globalToLocal(globalPos);
      final boardSize = renderBox.size;
      _squareSize = boardSize.width / 8;

      final displayCol = (local.dx / _squareSize).floor().clamp(0, 7);
      final displayRow = (local.dy / _squareSize).floor().clamp(0, 7);
      final targetSq = _displayToSquare(displayCol, displayRow);

      if (_legalTargets.contains(targetSq) && targetSq != _dragSquare) {
        _attemptMove(_dragSquare!, targetSq);
        return;
      }
    }

    setState(() {
      _dragSquare = null;
      _dragOffset = null;
      _dragPiece = null;
    });
  }

  void _onDragMove(Offset globalPos) {
    if (_dragSquare == null) return;
    setState(() => _dragOffset = globalPos);
  }

  // ── Last move squares ─────────────────────────────────────────────────────

  (String?, String?) get _lastMoveSqs {
    final uci = widget.lastMoveUci;
    if (uci == null || uci.length < 4) return (null, null);
    return (uci.substring(0, 2), uci.substring(2, 4));
  }

  // ── History helpers ────────────────────────────────────────────────────────

  List<_MoveRecord> get _moveRecords {
    final records = <_MoveRecord>[];
    for (int i = 0; i < widget.sanHistory.length; i += 2) {
      records.add(
        _MoveRecord(
          number: (i ~/ 2) + 1,
          white: widget.sanHistory[i],
          black: i + 1 < widget.sanHistory.length
              ? widget.sanHistory[i + 1]
              : '',
        ),
      );
    }
    return records;
  }

  void _scrollHistoryToBottom() {
    if (_historyScroll.hasClients) {
      _historyScroll.animateTo(
        _historyScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _CW.panelBg,
      child: Column(
        children: [
          // Move history panel
          if (widget.showHistory) _buildHistoryPanel(),

          // Board + frame
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.maxWidth.clamp(
                  0.0,
                  constraints.maxHeight,
                );
                _squareSize = available / 8;
                return Center(child: _buildBoardWithFrame(available));
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Frame + coordinates ───────────────────────────────────────────────────

  Widget _buildBoardWithFrame(double boardSize) {
    const frameW = 20.0;
    final totalSize = boardSize + frameW * 2;

    return Container(
      width: totalSize,
      height: totalSize,
      decoration: BoxDecoration(
        color: _CW.frame,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _CW.frameDark.withValues(alpha: 0.8),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Rank labels (left)
          Positioned(
            left: 0,
            top: frameW,
            width: frameW,
            height: boardSize,
            child: Column(
              children: List.generate(8, (i) {
                final rank = _flipped ? i + 1 : 8 - i;
                return SizedBox(
                  height: _squareSize,
                  child: Center(
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        color: _CW.coordColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // File labels (bottom)
          Positioned(
            left: frameW,
            bottom: 0,
            width: boardSize,
            height: frameW,
            child: Row(
              children: List.generate(8, (i) {
                final file = _flipped
                    ? String.fromCharCode(104 - i)
                    : String.fromCharCode(97 + i);
                return SizedBox(
                  width: _squareSize,
                  child: Center(
                    child: Text(
                      file,
                      style: const TextStyle(
                        color: _CW.coordColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // Board
          Positioned(
            left: frameW,
            top: frameW,
            width: boardSize,
            height: boardSize,
            child: _buildBoard(boardSize),
          ),
        ],
      ),
    );
  }

  // ── Board grid ────────────────────────────────────────────────────────────

  Widget _buildBoard(double size) {
    final (lastFrom, lastTo) = _lastMoveSqs;
    final checkedKing = _cachedCheckedKingSq;

    return GestureDetector(
      onTapUp: (d) {
        final col = (d.localPosition.dx / _squareSize).floor().clamp(0, 7);
        final row = (d.localPosition.dy / _squareSize).floor().clamp(0, 7);
        _selectSquare(_displayToSquare(col, row));
      },
      child: Listener(
        onPointerDown: (e) {
          final col = (e.localPosition.dx / _squareSize).floor().clamp(0, 7);
          final row = (e.localPosition.dy / _squareSize).floor().clamp(0, 7);
          final sq = _displayToSquare(col, row);
          _onDragStart(sq, e.position);
        },
        onPointerMove: (e) => _onDragMove(e.position),
        onPointerUp: (e) => _onDragEnd(e.position),
        onPointerCancel: (_) => setState(() {
          _dragSquare = null;
          _dragOffset = null;
          _dragPiece = null;
        }),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            key: _boardKey,
            children: [
              // Squares
              ...List.generate(64, (i) {
                final displayRow = i ~/ 8;
                final displayCol = i % 8;
                final sq = _displayToSquare(displayCol, displayRow);
                final isLight = (displayCol + displayRow).isEven;
                final isLastFrom = sq == lastFrom;
                final isLastTo = sq == lastTo;
                final isSelected = sq == _selectedSquare;
                final isChecked = sq == checkedKing;

                Color squareColor;
                if (isSelected) {
                  squareColor = _CW.selectedSq;
                } else if (isLastFrom || isLastTo) {
                  squareColor = isLight ? _CW.lightSquareH : _CW.darkSquareH;
                } else {
                  squareColor = isLight ? _CW.lightSquare : _CW.darkSquare;
                }

                return Positioned(
                  left: displayCol * _squareSize,
                  top: displayRow * _squareSize,
                  width: _squareSize,
                  height: _squareSize,
                  child: AnimatedBuilder(
                    animation: _checkAnim,
                    builder: (_, __) => Container(
                      color: isChecked
                          ? Color.lerp(
                              _CW.checkSq.withValues(alpha: 0.3),
                              _CW.checkSq.withValues(alpha: 0.7),
                              _checkAnim.value,
                            )
                          : squareColor,
                    ),
                  ),
                );
              }),

              // Pieces (skip dragged piece)
              ...List.generate(64, (i) {
                final displayRow = i ~/ 8;
                final displayCol = i % 8;
                final sq = _displayToSquare(displayCol, displayRow);
                if (sq == _dragSquare) return const SizedBox.shrink();
                final pieceKey = _pieceAt(sq);
                if (pieceKey == null) return const SizedBox.shrink();
                return Positioned(
                  left: displayCol * _squareSize,
                  top: displayRow * _squareSize,
                  width: _squareSize,
                  height: _squareSize,
                  child: _PieceWidget(pieceKey: pieceKey, size: _squareSize),
                );
              }),

              // Legal move dots
              ..._legalTargets.map((sq) {
                final (dCol, dRow) = _squareToDisplay(sq);
                final isCapture = _legalCaptures.contains(sq);
                final pieceHere = _pieceAt(sq) != null;
                return Positioned(
                  left: dCol * _squareSize,
                  top: dRow * _squareSize,
                  width: _squareSize,
                  height: _squareSize,
                  child: IgnorePointer(
                    child: Center(
                      child: isCapture || pieceHere
                          ? _CaptureRing(size: _squareSize)
                          : _LegalDot(size: _squareSize),
                    ),
                  ),
                );
              }),

              // Dragged piece floating
              if (_dragSquare != null &&
                  _dragOffset != null &&
                  _dragPiece != null)
                _DraggedPiece(
                  boardKey: _boardKey,
                  globalOffset: _dragOffset!,
                  pieceKey: _dragPiece!,
                  size: _squareSize,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── History panel ─────────────────────────────────────────────────────────

  Widget _buildHistoryPanel() {
    final records = _moveRecords;

    return Container(
      decoration: const BoxDecoration(
        color: _CW.panelSurface,
        border: Border(bottom: BorderSide(color: Color(0xFF5C3520), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _historyExpanded = !_historyExpanded),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, color: _CW.text2, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Lịch sử nước đi (${widget.sanHistory.length})',
                    style: const TextStyle(
                      color: _CW.text2,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _historyExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _CW.text2,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          // Moves list (Collapsible)
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: _historyExpanded && records.isNotEmpty
                ? SizedBox(
                    height: 72,
                    child: ListView.builder(
                      controller: _historyScroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      itemCount: records.length,
                      itemBuilder: (_, i) {
                        final r = records[i];
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Move number
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _CW.panelBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${r.number}.',
                                  style: const TextStyle(
                                    color: _CW.textDim,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 3),
                              // White move
                              _MoveChip(
                                san: r.white,
                                isLatest:
                                    i == records.length - 1 && r.black.isEmpty,
                              ),
                              if (r.black.isNotEmpty) ...[
                                const SizedBox(width: 3),
                                _MoveChip(
                                  san: r.black,
                                  isLatest: i == records.length - 1,
                                ),
                              ],
                              const SizedBox(width: 6),
                              // Divider
                              Container(
                                width: 1,
                                height: 20,
                                color: const Color(0xFF5C3520),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        );
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PIECE WIDGET
// =============================================================================

class _PieceWidget extends StatelessWidget {
  final String pieceKey;
  final double size;
  final double opacity;

  const _PieceWidget({
    required this.pieceKey,
    required this.size,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final unicode = _kPieceUnicode[pieceKey] ?? '';
    final isWhite = pieceKey.startsWith('w');

    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Shadow / stroke effect
            Text(
              unicode,
              style: TextStyle(
                fontSize: size * 0.68,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.2
                  ..color = isWhite
                      ? const Color(0xFF8B4513)
                      : Colors.transparent,
              ),
            ),
            Text(
              unicode,
              style: TextStyle(
                fontSize: size * 0.68,
                color: isWhite ? _CW.pieceWhite : _CW.pieceBlack,
                shadows: isWhite
                    ? [
                        const Shadow(
                          color: Color(0xFF8B4513),
                          blurRadius: 1,
                          offset: Offset(0.5, 0.5),
                        ),
                      ]
                    : [
                        const Shadow(
                          color: Color(0xFFD2691E),
                          blurRadius: 2,
                          offset: Offset(0, 0),
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LEGAL MOVE INDICATORS
// =============================================================================

class _LegalDot extends StatelessWidget {
  final double size;
  const _LegalDot({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size * 0.32,
    height: size * 0.32,
    decoration: const BoxDecoration(
      color: _CW.legalDot,
      shape: BoxShape.circle,
    ),
  );
}

class _CaptureRing extends StatelessWidget {
  final double size;
  const _CaptureRing({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size * 0.9,
    height: size * 0.9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: _CW.legalCapture, width: size * 0.1),
    ),
  );
}

// =============================================================================
// DRAGGED PIECE (floating)
// =============================================================================

class _DraggedPiece extends StatelessWidget {
  final GlobalKey boardKey;
  final Offset globalOffset;
  final String pieceKey;
  final double size;

  const _DraggedPiece({
    required this.boardKey,
    required this.globalOffset,
    required this.pieceKey,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final renderBox = boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();
    final local = renderBox.globalToLocal(globalOffset);
    return Positioned(
      left: local.dx - size / 2,
      top: local.dy - size * 0.7, // lifted above finger
      child: IgnorePointer(
        child: _PieceWidget(pieceKey: pieceKey, size: size * 1.2),
      ),
    );
  }
}

// =============================================================================
// PROMOTION DIALOG
// =============================================================================

class _PromotionDialog extends StatelessWidget {
  final bool isWhite;
  const _PromotionDialog({required this.isWhite});

  @override
  Widget build(BuildContext context) {
    final pieces = [
      (_PromoPiece.queen, isWhite ? 'wQ' : 'bQ', 'Hậu'),
      (_PromoPiece.rook, isWhite ? 'wR' : 'bR', 'Xe'),
      (_PromoPiece.bishop, isWhite ? 'wB' : 'bB', 'Tượng'),
      (_PromoPiece.knight, isWhite ? 'wN' : 'bN', 'Mã'),
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _CW.frame,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _CW.frameDark, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Phong cấp quân',
              style: TextStyle(
                color: _CW.text1,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: pieces
                  .map(
                    (p) => GestureDetector(
                      onTap: () => Navigator.pop(context, p.$1),
                      child: Container(
                        width: 64,
                        height: 80,
                        decoration: BoxDecoration(
                          color: _CW.lightSquare,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _CW.darkSquare, width: 2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PieceWidget(pieceKey: p.$2, size: 40),
                            const SizedBox(height: 4),
                            Text(
                              p.$3,
                              style: const TextStyle(
                                color: _CW.panelBg,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MOVE CHIP (history)
// =============================================================================

class _MoveChip extends StatelessWidget {
  final String san;
  final bool isLatest;

  const _MoveChip({required this.san, this.isLatest = false});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: isLatest ? _CW.darkSquare : _CW.panelBg,
      borderRadius: BorderRadius.circular(5),
      border: isLatest
          ? Border.all(color: _CW.lightSquare.withValues(alpha: 0.4))
          : null,
    ),
    child: Text(
      san,
      style: TextStyle(
        color: isLatest ? _CW.text1 : _CW.text2,
        fontSize: 12,
        fontWeight: isLatest ? FontWeight.w700 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

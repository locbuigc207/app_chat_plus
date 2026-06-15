import 'package:flutter/material.dart';

class ChessBoardWidget extends StatelessWidget {
  final String fen;
  final bool isMyTurn;
  final dynamic myRole; // PlayerRole tương ứng của hệ thống
  final Function(String from, String to) onMove;

  const ChessBoardWidget({
    Key? key,
    required this.fen,
    required this.isMyTurn,
    required this.myRole,
    required this.onMove,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Bọc bằng AspectRatio để ép bàn cờ luôn là hình vuông (tỷ lệ 1.0)
    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        color: Colors.brown[300],
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 64,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
          ),
          itemBuilder: (context, index) {
            final int row = index ~/ 8;
            final int col = index % 8;
            final bool isDark = (row + col) % 2 == 1;

            return Container(
              color: isDark ? Colors.brown[700] : Colors.amber[100],
              child: Center(
                child: Text(
                  '$row,$col', // Sắp xếp mapping ký hiệu quân cờ dựa trên FEN thực tế tại đây
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TicTacToeMessageWidget extends StatelessWidget {
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

  void _onCellTapped(int index, Map<String, dynamic> gameState) async {
    List<dynamic> board = gameState['board'];
    String turn = gameState['turn'];
    String winner = gameState['winner'];
    String playerX = gameState['playerX'];
    String playerO = gameState['playerO'];

    if (winner.isNotEmpty || board[index].toString().isNotEmpty) return;

    // Gán người chơi nếu ghế còn trống
    if (playerX.isEmpty) {
      playerX = currentUserId;
      if (turn.isEmpty) turn = currentUserId;
    } else if (playerO.isEmpty && playerX != currentUserId) {
      playerO = currentUserId;
    }

    // Kiểm tra lượt
    if (turn != currentUserId) return; // Không phải lượt của mình

    String mySymbol = (currentUserId == playerX) ? 'X' : 'O';
    board[index] = mySymbol;

    // Đổi lượt
    String nextTurn = (currentUserId == playerX)
        ? (playerO.isEmpty ? playerX : playerO)
        : playerX;

    // Logic kiểm tra thắng thua cơ bản
    winner = _checkWinner(board);

    Map<String, dynamic> newState = {
      'board': board,
      'turn': nextTurn,
      'winner': winner,
      'playerX': playerX,
      'playerO': playerO,
    };

    // Cập nhật Realtime lên Firestore
    await FirebaseFirestore.instance
        .collection('messages')
        .doc(groupId)
        .collection(groupId)
        .doc(messageId)
        .update({'content': jsonEncode(newState)});
  }

  String _checkWinner(List<dynamic> b) {
    List<List<int>> lines = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6]
    ];
    for (var l in lines) {
      if (b[l[0]] != "" && b[l[0]] == b[l[1]] && b[l[1]] == b[l[2]])
        return b[l[0]];
    }
    if (!b.contains("")) return "Hòa";
    return "";
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> gameState = jsonDecode(content);
    List<dynamic> board = gameState['board'];
    String winner = gameState['winner'];

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(
              winner.isNotEmpty
                  ? (winner == "Hòa" ? "Hòa nhau!" : "Người thắng: $winner")
                  : "Cờ Caro 3x3",
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blueAccent)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
            itemCount: 9,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _onCellTapped(index, gameState),
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8)),
                  child: Center(
                    child: Text(board[index],
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color:
                              board[index] == 'X' ? Colors.red : Colors.green,
                        )),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

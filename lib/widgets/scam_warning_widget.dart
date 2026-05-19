import 'package:flutter/material.dart';

class ScamWarningWidget extends StatelessWidget {
  final String status; 

  const ScamWarningWidget({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    String text = "";
    IconData icon = Icons.warning_amber_rounded;
    Color color = Colors.orange;

    if (status == 'WARNING_MONEY') {
      text =
          "Cảnh báo: Tin nhắn có dấu hiệu mượn tiền/chuyển khoản. Hãy gọi điện xác nhận!";
    } else if (status == 'WARNING_LINK') {
      text = "Cảnh báo: Không bấm vào đường link lạ nếu không rõ nguồn gốc!";
    } else if (status == 'DANGER') {
      text = "NGUY HIỂM: Tin nhắn có dấu hiệu lừa đảo chiếm đoạt tài sản!";
      color = Colors.red;
      icon = Icons.gpp_bad_rounded;
    } else {
      return const SizedBox.shrink(); 
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

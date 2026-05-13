import 'package:any_link_preview/any_link_preview.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkPreviewWidget extends StatelessWidget {
  final String url;

  const LinkPreviewWidget({Key? key, required this.url}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      child: AnyLinkPreview(
        link: url,
        displayDirection: UIDirection.uiDirectionVertical,
        cache: const Duration(days: 7),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF252A3D)
            : Colors.grey[200],
        errorWidget: const SizedBox.shrink(), // Ẩn nếu không lấy được meta
        errorImage: "https://via.placeholder.com/150",
        borderRadius: 12,
        removeElevation: true,
        boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black12)],
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      ),
    );
  }
}

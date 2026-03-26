// lib/pages/group_media_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:url_launcher/url_launcher.dart';

class GroupMediaPage extends StatefulWidget {
  const GroupMediaPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupMediaPage> createState() => _GroupMediaPageState();
}

class _GroupMediaPageState extends State<GroupMediaPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DocumentSnapshot> _allMessages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllMessages();
  }

  Future<void> _loadAllMessages() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(widget.groupId)
          .collection(widget.groupId)
          .where('isDeleted', isEqualTo: false)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(200)
          .get();
      if (mounted) {
        setState(() {
          _allMessages = snap.docs;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<DocumentSnapshot> get _images => _allMessages
      .where((d) =>
          (d.data() as Map<String, dynamic>?)?['type'] == TypeMessage.image)
      .toList();

  List<DocumentSnapshot> get _voiceMessages => _allMessages
      .where((d) => (d.data() as Map<String, dynamic>?)?['type'] == 3)
      .toList();

  List<DocumentSnapshot> get _links => _allMessages.where((d) {
        final data = d.data() as Map<String, dynamic>?;
        if (data?['type'] != TypeMessage.text) return false;
        final content = data?['content'] as String? ?? '';
        return content.contains('http') || content.contains('maps.google.com');
      }).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.groupName} Media',
            style: const TextStyle(color: ColorConstants.primaryColor)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: ColorConstants.primaryColor,
          unselectedLabelColor: ColorConstants.greyColor,
          indicatorColor: ColorConstants.primaryColor,
          tabs: const [
            Tab(icon: Icon(Icons.image), text: 'Photos'),
            Tab(icon: Icon(Icons.mic), text: 'Voice'),
            Tab(icon: Icon(Icons.link), text: 'Links'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: ColorConstants.themeColor))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildImagesTab(),
                _buildVoiceTab(),
                _buildLinksTab(),
              ],
            ),
    );
  }

  Widget _buildImagesTab() {
    if (_images.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported,
                size: 64, color: ColorConstants.greyColor),
            SizedBox(height: 12),
            Text('No photos yet',
                style: TextStyle(color: ColorConstants.greyColor)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _images.length,
      itemBuilder: (_, i) {
        final data = _images[i].data() as Map<String, dynamic>? ?? {};
        final url = data['content'] as String? ?? '';
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FullPhotoPage(url: url)),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: ColorConstants.greyColor2,
            ),
            clipBehavior: Clip.hardEdge,
            child: Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                    color: ColorConstants.greyColor)),
          ),
        );
      },
    );
  }

  Widget _buildVoiceTab() {
    if (_voiceMessages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off, size: 64, color: ColorConstants.greyColor),
            SizedBox(height: 12),
            Text('No voice messages yet',
                style: TextStyle(color: ColorConstants.greyColor)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _voiceMessages.length,
      itemBuilder: (_, i) {
        final data = _voiceMessages[i].data() as Map<String, dynamic>? ?? {};
        final ts = data['timestamp'] as String? ?? '0';
        DateTime dt = DateTime.now();
        try {
          dt = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
        } catch (_) {}
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: ColorConstants.primaryColor,
              child: Icon(Icons.mic, color: Colors.white),
            ),
            title: const Text('Voice Message'),
            subtitle: Text(
                '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}'),
          ),
        );
      },
    );
  }

  Widget _buildLinksTab() {
    if (_links.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 64, color: ColorConstants.greyColor),
            SizedBox(height: 12),
            Text('No links shared yet',
                style: TextStyle(color: ColorConstants.greyColor)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _links.length,
      itemBuilder: (_, i) {
        final data = _links[i].data() as Map<String, dynamic>? ?? {};
        final content = data['content'] as String? ?? '';
        // Extract URL
        final urlReg = RegExp(r'https?://[^\s]+');
        final match = urlReg.firstMatch(content);
        final url = match?.group(0) ?? content;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: ColorConstants.primaryColor,
              child: Icon(Icons.link, color: Colors.white),
            ),
            title: Text(url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: ColorConstants.primaryColor,
                    decoration: TextDecoration.underline)),
            onTap: () async {
              try {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              } catch (_) {}
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

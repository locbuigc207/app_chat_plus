// lib/models/group.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class Group {
  final String id;
  final String groupName;
  final String groupPhotoUrl;
  final String adminId; // Giữ lại cho tương thích ngược
  final List<String> memberIds;
  final Map<String, dynamic> roles; // Map chứa Role của các thành viên
  final String createdAt;

  const Group({
    required this.id,
    required this.groupName,
    required this.groupPhotoUrl,
    required this.adminId,
    required this.memberIds,
    required this.roles,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      FirestoreConstants.groupName: groupName,
      FirestoreConstants.groupPhotoUrl: groupPhotoUrl,
      FirestoreConstants.adminId: adminId,
      FirestoreConstants.memberIds: memberIds,
      'roles': roles,
      FirestoreConstants.createdAt: createdAt,
    };
  }

  factory Group.fromDocument(DocumentSnapshot doc) {
    List<String> members = [];
    try {
      members = List<String>.from(doc.get(FirestoreConstants.memberIds));
    } catch (_) {}

    Map<String, dynamic> parsedRoles = {};
    try {
      parsedRoles = Map<String, dynamic>.from(doc.get('roles'));
    } catch (_) {
      // Tương thích ngược với các Group cũ chưa có trường 'roles'
      // Tự động gán adminId thành 'owner'
      final oldAdminId = doc.get(FirestoreConstants.adminId) as String?;
      if (oldAdminId != null && oldAdminId.isNotEmpty) {
        parsedRoles[oldAdminId] = 'owner';
      }
    }

    return Group(
      id: doc.id,
      groupName: doc.get(FirestoreConstants.groupName),
      groupPhotoUrl: doc.get(FirestoreConstants.groupPhotoUrl) ?? '',
      adminId: doc.get(FirestoreConstants.adminId) ?? '',
      memberIds: members,
      roles: parsedRoles,
      createdAt: doc.get(FirestoreConstants.createdAt),
    );
  }
}

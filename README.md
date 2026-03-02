# Flutter Chat Application

[![Flutter Version](https://img.shields.io/badge/Flutter-3.19.0+-blue.svg)](https://flutter.dev/)
[![Dart Version](https://img.shields.io/badge/Dart-3.3.0+-blue.svg)](https://dart.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Enabled-orange.svg)](https://firebase.google.com/)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey.svg)](https://flutter.dev/docs/deployment)

Ứng dụng chat đa nền tảng được xây dựng bằng Flutter và Firebase, hỗ trợ đầy đủ các tính năng hiện đại như chat bong bóng, tin nhắn tự xóa, phản ứng, và nhiều hơn nữa.

## 📱 Tính năng chính

### 🔐 Xác thực & Bảo mật
- Đăng nhập Google Sign-In
- Xác thực số điện thoại
- Khóa hội thoại bằng PIN/vân tay
- Mã hóa dữ liệu nhạy cảm

### 💬 Tin nhắn & Chat
- Nhắn tin văn bản, hình ảnh, giọng nói
- Gửi vị trí địa lý
- Tin nhắn tự xóa (View Once)
- Xóa tin nhắn tự động theo thời gian
- Ghim tin nhắn quan trọng
- Phản ứng emoji với tin nhắn
- Trả lời nhanh thông minh (Smart Reply)
- Dịch tin nhắn đa ngôn ngữ
- Tìm kiếm tin nhắn nâng cao

### 🎈 Chat Bong Bóng (Bubble Chat)
- **Bubble API (Android 11+)**: Sử dụng Notification API chính thức
- **WindowManager (Android < 11)**: Fallback cho thiết bị cũ
- **Unified Service**: Tự động chọn implementation phù hợp
- Hỗ trợ nhiều bubble cùng lúc
- Kéo thả để xóa bubble
- Lưu trạng thái khi xoay màn hình
- Mini chat overlay có thể di chuyển

### 👥 Quản lý bạn bè & nhóm
- Gửi/nhận lời mời kết bạn
- Quét mã QR để kết bạn
- Tạo và quản lý nhóm chat
- Hiển thị trạng thái online/offline
- Thanh bạn bè online nhanh

### 🔔 Thông báo & Nhắc nhở
- Thông báo tin nhắn mới
- Đặt nhắc nhở cho tin nhắn
- Thông báo local với timezone

### 🎨 Giao diện & UX
- Theme sáng/tối
- Tùy chỉnh màu chủ đạo
- Animations mượt mà
- Responsive design
- Loading states & error handling

## 📁 Cấu trúc dự án

```
flutter_chat_demo/
├── android/
│   └── app/
│       ├── src/main/kotlin/hust/appchat/
│       │   ├── MainActivity.kt                    # Activity chính
│       │   ├── BubbleActivity.kt                  # Activity cho Bubble mode
│       │   ├── FlutterMiniChatActivity.kt        # Mini chat activity
│       │   ├── MyAppGlideModule.kt               # Glide configuration
│       │   ├── bubble/
│       │   │   ├── BubbleManager.kt              # Quản lý bubble lifecycle
│       │   │   ├── BubbleOverlayService.kt       # Service hiển thị bubble
│       │   │   ├── BubbleView.kt                 # Custom bubble view
│       │   │   ├── DeleteZoneView.kt             # Delete zone UI
│       │   │   └── MultiBubbleManager.kt         # Multi-bubble management
│       │   ├── notifications/
│       │   │   ├── BubbleNotificationManager.kt  # Notification với message history
│       │   │   ├── BubbleNotificationService.kt  # Service xử lý notifications
│       │   │   └── NotificationHelper.kt         # Helper utilities
│       │   └── shortcuts/
│       │       ├── AvatarLoader.kt               # Avatar loading & caching
│       │       └── ShortcutHelper.kt             # Dynamic shortcuts management
│       ├── build.gradle                          # Build configuration
│       └── google-services.json                  # Firebase config
├── lib/
│   ├── constants/
│   │   ├── app_constants.dart                   # App constants
│   │   ├── color_constants.dart                 # Color definitions
│   │   ├── firestore_constants.dart             # Firestore field names
│   │   ├── type_message.dart                    # Message types
│   │   └── app_themes.dart                      # Theme definitions
│   ├── models/
│   │   ├── user_chat.dart                       # User model
│   │   ├── message_chat.dart                    # Message model
│   │   ├── conversation.dart                    # Conversation model
│   │   ├── group.dart                           # Group model
│   │   ├── friendship.dart                      # Friendship model
│   │   ├── message_reaction.dart                # Reaction model
│   │   └── bubble_models.dart                   # Bubble-related models
│   ├── pages/
│   │   ├── splash_page.dart                     # Splash screen
│   │   ├── login_page.dart                      # Login screen
│   │   ├── phone_login_page.dart                # Phone auth
│   │   ├── home_page.dart                       # Main chat list
│   │   ├── chat_page.dart                       # Chat interface
│   │   ├── group_chat_page.dart                 # Group chat
│   │   ├── friends_page.dart                    # Friends management
│   │   ├── settings_page.dart                   # Settings
│   │   ├── user_profile_page.dart               # User profile
│   │   ├── my_qr_code_page.dart                 # QR code generation
│   │   ├── qr_scanner_page.dart                 # QR scanner
│   │   ├── search_messages_page.dart            # Message search
│   │   ├── theme_settings_page.dart             # Theme customization
│   │   ├── full_photo_page.dart                 # Full photo viewer
│   │   └── enhanced_photo_viewer.dart           # Enhanced photo viewer
│   ├── providers/
│   │   ├── auth_provider.dart                   # Authentication logic
│   │   ├── phone_auth_provider.dart             # Phone auth logic
│   │   ├── chat_provider.dart                   # Chat functionality
│   │   ├── home_provider.dart                   # Home page logic
│   │   ├── setting_provider.dart                # Settings management
│   │   ├── friend_provider.dart                 # Friends management
│   │   ├── message_provider.dart                # Message operations
│   │   ├── reaction_provider.dart               # Message reactions
│   │   ├── conversation_provider.dart           # Conversation management
│   │   ├── theme_provider.dart                  # Theme management
│   │   ├── reminder_provider.dart               # Reminders
│   │   ├── auto_delete_provider.dart            # Auto-delete messages
│   │   ├── conversation_lock_provider.dart      # Conversation locking
│   │   ├── view_once_provider.dart              # View-once messages
│   │   ├── smart_reply_provider.dart            # Smart replies
│   │   ├── user_presence_provider.dart          # User status
│   │   ├── location_provider.dart               # Location sharing
│   │   ├── translation_provider.dart            # Message translation
│   │   └── voice_message_provider.dart          # Voice messages
│   ├── services/
│   │   ├── unified_bubble_service.dart          # Unified bubble service (NEW)
│   │   ├── bubble_service_v2.dart               # Bubble API implementation
│   │   ├── chat_bubble_service.dart             # Legacy bubble service
│   │   └── notification_service.dart            # Notification service
│   ├── utils/
│   │   ├── utilities.dart                       # General utilities
│   │   ├── debouncer.dart                       # Debouncing
│   │   ├── error_logger.dart                    # Error logging
│   │   ├── network_utils.dart                   # Network utilities
│   │   ├── app_date_utils.dart                  # Date formatting
│   │   └── bubble_testing_utils.dart            # Bubble testing tools
│   ├── widgets/
│   │   ├── bubble_manager.dart                  # Bubble manager widget
│   │   ├── mini_chat_overlay.dart               # Mini chat overlay
│   │   ├── conversation_item.dart               # Conversation list item
│   │   ├── message_options_dialog.dart          # Message options
│   │   ├── enhanced_message_options_dialog.dart # Enhanced options
│   │   ├── conversation_options_dialog.dart     # Conversation options
│   │   ├── enhanced_conversation_options.dart   # Enhanced conv options
│   │   ├── auto_delete_settings_dialog.dart     # Auto-delete settings
│   │   ├── pin_input_dialog.dart                # PIN input
│   │   ├── edit_message_dialog.dart             # Edit message
│   │   ├── schedule_message_dialog.dart         # Schedule message
│   │   ├── translation_dialog.dart              # Translation UI
│   │   ├── reaction_picker.dart                 # Emoji picker
│   │   ├── message_reactions_display.dart       # Reactions display
│   │   ├── smart_reply.dart                     # Smart reply widget
│   │   ├── typing_indicator.dart                # Typing indicator
│   │   ├── user_status_indicator.dart           # Status indicator
│   │   ├── online_friends_bar.dart              # Online friends bar
│   │   ├── read_receipt_widget.dart             # Read receipts
│   │   ├── view_once_message_widget.dart        # View-once widget
│   │   ├── voice_message_widget.dart            # Voice message player
│   │   ├── advanced_search_bar.dart             # Search bar
│   │   └── loading_view.dart                    # Loading indicator
│   └── main.dart                                # App entry point
├── functions/
│   ├── index.js                                 # Cloud Functions
│   └── package.json                             # Functions dependencies
├── firebase.json                                # Firebase configuration
├── firestore.rules                              # Security rules
├── firestore.indexes.json                       # Firestore indexes
├── pubspec.yaml                                 # Flutter dependencies
└── README.md                                    # This file
```

## 🚀 Hướng dẫn cài đặt

### Yêu cầu hệ thống

- **Flutter SDK**: 3.19.0 hoặc cao hơn
- **Dart SDK**: 3.3.0 hoặc cao hơn
- **Android Studio/VS Code** với Flutter extension
- **Xcode** (cho iOS development)
- **Firebase CLI** (cho deployment)
- **Node.js** 22+ (cho Cloud Functions)

### Bước 1: Clone repository

```bash
git clone https://github.com/your-username/flutter-chat-app.git
cd flutter-chat-app
```

### Bước 2: Cài đặt dependencies

```bash
flutter pub get
cd functions && npm install && cd ..
```

### Bước 3: Cấu hình Firebase

#### 3.1. Tạo Firebase Project

1. Truy cập [Firebase Console](https://console.firebase.google.com/)
2. Tạo project mới hoặc sử dụng project existing
3. Enable các services:
    - Authentication (Google, Phone)
    - Cloud Firestore
    - Cloud Storage
    - Cloud Functions
    - Firebase Analytics
    - Firebase Crashlytics

#### 3.2. Cấu hình Android App

1. Thêm Android app vào Firebase project
2. Package name: `hust.appchat`
3. Download `google-services.json`
4. Copy vào `android/app/`

#### 3.3. Cấu hình iOS App (Optional)

1. Thêm iOS app vào Firebase project
2. Bundle ID: `com.example.flutterchatdemo`
3. Download `GoogleService-Info.plist`
4. Copy vào `ios/Runner/`

#### 3.4. Cấu hình Google Sign-In

**Android:**
1. Get SHA-1 certificate fingerprint:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

2. Add SHA-1 vào Firebase Console (Project Settings > Android App)

**iOS:**
1. Thêm URL scheme vào `ios/Runner/Info.plist`
2. Enable Google Sign-In trong Firebase Console

### Bước 4: Deploy Firestore Rules & Indexes

```bash
# Deploy rules
firebase deploy --only firestore:rules

# Deploy indexes
firebase deploy --only firestore:indexes
```

### Bước 5: Deploy Cloud Functions

```bash
cd functions
npm run deploy
```

### Bước 6: Build & Run

#### Android

```bash
# Debug build
flutter run

# Release build
flutter build apk --release
# hoặc
flutter build appbundle --release
```

#### iOS

```bash
# Debug build
flutter run

# Release build
flutter build ios --release
```


### Tính năng Bubble Chat

#### Android 11+ (Bubble API)

- **Notification-based bubbles**: Sử dụng Android Bubble API chính thức
- **Message history**: Lưu trữ 10 tin nhắn gần nhất trong notification
- **Dynamic shortcuts**: Tự động tạo shortcuts cho conversations
- **Avatar caching**: LRU cache với Glide để tải avatar hiệu quả
- **Smart navigation**: Tránh duplicate navigation

#### Android < 11 (WindowManager)

- **Overlay bubbles**: Sử dụng WindowManager để tạo floating bubbles
- **Drag & drop**: Kéo thả bubble với delete zone
- **Multi-bubble support**: Hỗ trợ nhiều bubble cùng lúc
- **State persistence**: Lưu trạng thái khi app restart
- **Screen rotation**: Tự động điều chỉnh vị trí

### Testing Bubble Chat

```dart
// Sử dụng BubbleTestingUtils
import 'package:flutter_chat_demo/utils/bubble_testing_utils.dart';

// Test bubble functionality
await BubbleTestingUtils.testUnifiedBubbleService();

// Log implementation info
BubbleTestingUtils.logBubbleImplementation();

// Test message sending
await BubbleTestingUtils.testBubbleMessages(userId, userName);
```

## 📊 Firebase Structure

### Firestore Collections

#### `users` Collection
```javascript
{
  id: String,              // User ID (same as Auth UID)
  nickname: String,        // Display name
  photoUrl: String,        // Avatar URL
  phoneNumber: String,     // Phone number
  email: String,          // Email address
  aboutMe: String,        // Bio/status
  isOnline: Boolean,      // Online status
  lastSeen: Timestamp,    // Last active time
  pushToken: String,      // FCM token
  createdAt: Timestamp
}
```

#### `conversations` Collection
```javascript
{
  id: String,                    // Conversation ID
  participants: Array<String>,   // User IDs
  isGroup: Boolean,              // Group or 1-1
  groupName: String,             // Group name (if group)
  groupAvatar: String,           // Group avatar URL
  lastMessage: String,           // Last message content
  lastMessageTime: Timestamp,    // Last message timestamp
  lastMessageSenderId: String,   // Sender ID
  isPinned: Boolean,             // Pinned status
  autoDeleteEnabled: Boolean,    // Auto-delete enabled
  autoDeleteDuration: Number,    // Duration in ms
  isLocked: Boolean,             // Lock status
  lockType: String,              // "pin" or "fingerprint"
  createdAt: Timestamp
}
```

#### `messages/{conversationId}/{messageId}` Collection
```javascript
{
  id: String,              // Message ID
  idFrom: String,          // Sender ID
  idTo: String,            // Receiver ID (for 1-1)
  timestamp: String,       // Timestamp (as string)
  content: String,         // Message content
  type: Number,            // 0=text, 1=image, 2=sticker, 3=voice, 4=location
  isRead: Boolean,         // Read status
  isDeleted: Boolean,      // Deleted status
  isPinned: Boolean,       // Pinned status
  isViewOnce: Boolean,     // View-once status
  isViewed: Boolean,       // Viewed status (for view-once)
  autoDeleteAt: String,    // Auto-delete timestamp
  replyTo: String,         // Replied message ID
  location: {              // Location data
    latitude: Number,
    longitude: Number,
    address: String
  },
  reactions: Map<String, String>  // userId -> emoji
}
```

#### `friendships` Collection
```javascript
{
  id: String,              // Friendship ID
  userId1: String,         // User 1 ID
  userId2: String,         // User 2 ID
  createdAt: Timestamp
}
```

#### `friend_requests` Collection
```javascript
{
  id: String,              // Request ID
  requesterId: String,     // Requester ID
  receiverId: String,      // Receiver ID
  status: String,          // "pending", "accepted", "rejected"
  createdAt: Timestamp
}
```

#### `reminders` Collection
```javascript
{
  id: String,              // Reminder ID
  userId: String,          // User ID
  conversationId: String,  // Conversation ID
  messageId: String,       // Message ID
  reminderTime: Timestamp, // Scheduled time
  message: String,         // Reminder message
  isCompleted: Boolean,    // Completion status
  createdAt: Timestamp
}
```

### Cloud Functions

#### 1. `cleanupExpiredMessages` (Scheduled: every 5 minutes)
- Tự động xóa tin nhắn đã hết hạn
- Query conversations với `autoDeleteEnabled = true`
- Batch delete expired messages

#### 2. `scheduleMessageDeletion` (Trigger: onCreate message)
- Tự động set `autoDeleteAt` cho tin nhắn mới
- Dựa vào `autoDeleteDuration` của conversation

#### 3. `cleanupTypingStatus` (Scheduled: every 1 minute)
- Xóa typing status cũ hơn 5 giây
- Tránh hiển thị "typing..." vĩnh viễn

#### 4. `updateUserPresence` (Trigger: onUpdate user)
- Update `lastSeen` khi user offline
- Tracking user activity

#### 5. `sendMessageNotification` (Trigger: onCreate message)
- Gửi push notification cho tin nhắn mới
- Sử dụng FCM token

#### 6. `cleanupOldDeletedMessages` (Scheduled: every 24 hours)
- Xóa vĩnh viễn tin nhắn đã delete > 30 ngày
- Giảm database size


## 🐛 Common Issues & Solutions

### Issue 1: Bubble Chat không hoạt động

**Solution:**
- Check Android version (>=11 cho Bubble API)
- Verify overlay permission granted
- Check logs: `adb logcat | grep "Bubble"`

### Issue 2: Google Sign-In failed

**Solution:**
- Verify SHA-1 certificate trong Firebase Console
- Check package name match
- Enable Google Sign-In trong Firebase Authentication

### Issue 3: Notifications không hiển thị

**Solution:**
- Check FCM token generation
- Verify notification permissions
- Check notification channel creation

### Issue 4: Cloud Functions timeout

**Solution:**
- Increase function timeout trong `firebase.json`
- Optimize Firestore queries
- Add indexes if needed


## 👥 Contributors

- **Project Lead**: [Bùi Gia Lộc]
- **Android Development**: Kotlin Native Integration
- **Flutter Development**: Cross-platform Implementation
- **Firebase Backend**: Cloud Functions & Firestore

## 🙏 Acknowledgments

- Flutter Team for the amazing framework
- Firebase Team for backend services
- Material Design Team for design guidelines
- Open source community for various packages

**Happy Chatting! 💬**
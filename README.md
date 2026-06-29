# README.md

## 📱 flutter_chat_demo (App Chat Plus)

**Production chat app with advanced Android Bubble API, WindowManager overlay, contextual adaptive UI, real-time Firestore, AR filters, and Game Center.**

Dự án này là một ứng dụng nhắn tin toàn diện (Production-ready) được phát triển bằng Flutter, kết hợp chặt chẽ với hệ sinh thái Firebase và tích hợp sâu AI (Google Gemini). Ứng dụng hỗ trợ đa nền tảng với các tính năng nâng cao như gọi Audio/Video qua Agora, phân tích bảo mật nội dung (Scam/Hate speech), cảnh báo Deepfake, trợ lý AI AutoPilot, Mini Games và AR Filters.

---

## ✨ Tính năng chính

### 1. Nhắn tin & Giao tiếp Cốt lõi

* **Trò chuyện 1-1 và Nhóm (Group Chat):** Hỗ trợ đầy đủ văn bản, hình ảnh, video, âm thanh, tài liệu, chia sẻ vị trí và tạo bình chọn (Polls).
* **Mã hóa đầu cuối (E2EE):** Đảm bảo tính riêng tư của tin nhắn thông qua `encrypt` và `pointycastle`.
* **Adaptive UI & Bong bóng chat (Bubbles):** Hỗ trợ Android Bubble API, WindowManager overlay cho mini-chat và PiP (Picture-in-Picture).
* **Hẹn giờ hủy tin nhắn & Tin nhắn tự xóa (View Once):** Cho phép gửi nội dung bảo mật cao.

### 2. Tích hợp AI Thông minh (Google Gemini)

* **Smart Reply & Swipe Replies:** AI phân tích ngữ cảnh và gợi ý câu trả lời nhanh chóng dựa trên tone giọng (friendly, professional, genz,...).
* **AutoPilot (Trả lời tự động):** AI học hỏi phong cách nhắn tin (Persona) của bạn để tự động trả lời khi bạn bận/đang ngủ.
* **Tóm tắt & Phân tích (Recap & Insights):** Tạo "Bản tin Bóc phốt tuần", báo cáo cảm xúc (Sentiment Analysis), trích xuất Action Items/Quyết định quan trọng.
* **Thay đổi giọng điệu (Tone Rewriter):** Dịch hoặc viết lại tin nhắn để phù hợp với người nhận (Elder, Student, Professional).
* **Smart Reminders:** Tự động phát hiện deadline, lịch hẹn từ tin nhắn và lên lịch nhắc nhở (Cron Jobs).

### 3. Calling & WebRTC (Agora)

* **Audio & Video Call 1-1 và Nhóm:** Khử tiếng ồn, chia sẻ màn hình, và theo dõi chất lượng mạng.
* **Bảo mật cuộc gọi & Chống Deepfake:** Phân tích dữ liệu âm thanh/hình ảnh thời gian thực để đưa ra cảnh báo lừa đảo mạo danh.
* **Ghi âm cuộc gọi (Cloud Recording):** Lưu trữ trực tiếp vào Google Cloud Storage.

### 4. Giải trí & Tiện ích

* **Game Center:** Cùng chơi Cờ vua (Chess), Cờ Caro (Tic-tac-toe) ngay trong phòng chat với tính năng tính giờ và trạng thái ván đấu real-time.
* **AR Filters & Camera:** Tích hợp `deepar_flutter_plus` để thêm hiệu ứng khuôn mặt (8bitHearts, Vendetta Mask, Emotion Meter,...).
* **Stories:** Chia sẻ khoảnh khắc trong 24h.

---

## 📂 Cấu trúc thư mục (Project Structure)

Dự án áp dụng mô hình quản lý state bằng `Provider`, tách biệt UI, Logic và Services.

```text
app_chat_plus/
├── android/                   # Cấu hình & code Native Android (Bubble API, WindowManager, Notifications)
├── ios/                       # Cấu hình Native iOS
├── web/                       # Assets và cấu hình Web
├── assets/                    # Chứa AR effects (.deepar), fonts (Inter)
├── images/                    # Chứa icon, gemini_avatar,...
├── functions/                 # Mã nguồn Firebase Cloud Functions (Node.js)
│   ├── index.js               # Chứa 55+ APIs và Cron Jobs
│   └── package.json           # Các dependencies của backend
└── lib/                       # Mã nguồn chính Flutter
    ├── constants/             # Hằng số (app, colors, themes, firestore)
    ├── models/                # Data models (ai_models, conversation, deepfake, game_match, group_call, message_chat, user_chat, reminder, story)
    ├── pages/                 # UI Screens (Chat, Call, Login, Group, Insights, Story, Settings)
    ├── providers/             # State Management (auth, chat, theme, voice_message, game_state, insights)
    ├── services/              # Xử lý Logic (agora_rtc, ai_backend, e2ee, firebase_fcm, deepfake_detector, local_db)
    ├── utils/                 # Tiện ích (audio_extractor, error_logger, data_masking, formatters)
    ├── widgets/               # UI Components tái sử dụng (adaptive_bubble, ai_shield, chess_board, mini_chat, tox_badge)
    ├── firebase_options.dart  # Config Firebase
    └── main.dart              # Entry point của ứng dụng

```

---

## 🛠 Hướng dẫn Cài đặt & Khởi chạy

### Yêu cầu hệ thống

* **Flutter SDK:** `>=3.44.0 <4.0.0`
* **Dart SDK:** `>=3.12.0 <4.0.0`
* **Node.js** (để deploy Cloud Functions)

### Các bước thực hiện

1. **Clone repository và cài đặt thư viện:**
```bash
flutter pub get

```


2. **Cấu hình Môi trường (.env):**
   Tạo file `.env` tại thư mục gốc và khai báo các khóa bí mật:
```env
GEMINI_API_KEY=your_gemini_api_key
AGORA_APP_ID=your_agora_app_id
AGORA_APP_CERTIFICATE=your_agora_certificate
# ... các config khác

```


3. **Cấu hình Firebase:**
   Sử dụng Firebase CLI để kết nối dự án:
```bash
flutterfire configure

```


4. **Deploy Cloud Functions:**
```bash
cd functions
npm install
firebase deploy --only functions
firebase deploy --only firestore:indexes

```


5. **Chạy ứng dụng:**
```bash
flutter run

```



---

## 🔥 Kiến trúc Firebase & Cloud Functions

### 1. Firestore Database 

Cơ sở dữ liệu được tổ chức tối ưu cho việc truy vấn Real-time (Sử dụng Collection & Collection Group):

* **`users`**: Lưu trữ hồ sơ, trạng thái online/offline, FcmToken, cấu hình Insight.
* **`conversations`**: Metadata hội thoại (isGroup, isLocked, lastMessage, autoDeleteEnabled).
* **`messages` (Sub-collection / Collection Group)**: Tin nhắn thực tế (có các trường `isPinned`, `isViewOnce`, `isDeleted`, `timestamp`).
* **`ai_analysis` (Sub-collection)**: Kết quả phân tích Scam/Toxicity cho từng tin nhắn.


* **`groups`**: Quản lý thông tin nhóm chat.
* **`calls` / `group_calls**`: Trạng thái cuộc gọi (calling, ringing, connected, missed) và link ghi âm.
* **`friend_requests` / `friendships**`: Mạng lưới quan hệ xã hội của user.
* **`game_matches`**: Quản lý state các ván game (Chess, Caro).
* **`stories`**: Trạng thái và nội dung story (expiresAt).
* **`reminders`**: Quản lý lịch nhắc nhở (isCompleted, reminderTime, isAutoGenerated).
* **`reactions`**: Cảm xúc (thả tim, haha) trên từng message.
* **`autopilot_config`**: Cấu hình AI trả lời tự động cho từng user.
* **`ai_content`**: Lưu nội dung chat của AI Assistant để phục vụ tóm tắt tuần.
* **`conversation_locks`**: Mã pin / Số lần thử thất bại của tính năng khóa chat.

### 2. Cloud Functions 

Dự án sử dụng Firebase Functions v2, chia làm 4 nhóm chính:

#### A. Security & Content Moderation (Bảo mật & Kiểm duyệt)

* `analyzeDecryptedMessage`, `analyzeScam`, `analyzeDecryptedClientMessage`: Phân tích tin nhắn lừa đảo.
* `detectHateSpeech`, `analyzeToxicityBatch`: Nhận diện ngôn từ độc hại.
* `analyzeCallSecurity`: Phân tích hội thoại gọi thoại, kết hợp điểm Local Deepfake để cảnh báo mạo danh.

#### B. AI & Chat Intelligence (Trí tuệ nhân tạo)

* `smartReplyWithContext`, `smartReplyEnhanced`, `suggestReplies`, `generateSwipeReplies`: Đề xuất câu trả lời thông minh.
* `generateAutoPilotReply`: Sinh câu trả lời khi chế độ AutoPilot được bật (Dựa vào persona người dùng).
* `translateCommunication`, `generateMessageTone`: Dịch và điều chỉnh văn phong (Gen Z, Chuyên nghiệp, Bạn bè).
* `analyzeChatContext`, `analyzeSentiment`, `extractKeyMoments`: Phân tích ngữ cảnh, xu hướng cảm xúc và khoảnh khắc đáng nhớ.
* `extractRelationshipMemory`: Đánh giá mức độ thân thiết của mối quan hệ từ lịch sử chat.
* `generateIcebreakers`: Tạo câu mở lời phá băng.
* `generateAiChatReply`: API cho chatbot hỗ trợ trực tiếp.

#### C. User Insights & Personas (Phân tích hành vi)

* `learnUserPersona`: Phân tích lịch sử để học cách dùng từ, emoji, độ dài câu của user.
* `getUserInsights`, `getUserInsightsV2`, `getInsightsDashboard`, `triggerInsightsRefresh`: Tạo báo cáo thống kê mức độ tương tác, chủ đề yêu thích, thói quen online.
* `generateWeeklyRecap`: Tạo bản tin tổng hợp tuần theo nhiều phong cách (Hài hước, Lãng mạn, MC truyền hình).

#### D. Calling & WebRTC (Gọi điện & Trực tuyến)

* `requestCallToken`, `generateAgoraToken`: Cấp phát token bảo mật cho Agora RTC.
* `startGroupCallRecording`, `stopGroupCallRecording`: Ghi âm cuộc gọi nhóm lưu vào Google Cloud Storage.

#### E. Reminders & Schedulers (Nhắc nhở & Tự động hóa)

* `extractReminderWithPriority`, `batchExtractReminders`, `generateReminderSuggestions`: Trích xuất deadline/cuộc hẹn từ tin nhắn thô.
* **Cron Jobs (`onSchedule`):**
* `cleanupExpiredMessages`, `cleanupExpiredStories`, `cleanupExpiredReminders`: Xóa tự động nội dung hết hạn.
* `cleanupStaleCalls`, `autoMissExpiredGroupCalls`, `autoAbortExpiredGameMatches`: Hủy trạng thái treo do rớt mạng.
* `onReminderDue`, `onReminderOverdueDigest`, `dailyConversationDigest`: Đẩy thông báo Push (FCM) nhắc nhở định kỳ.
* `weeklyAiRecap`: Chạy tổng hợp Recap AI vào chủ nhật hàng tuần.



#### F. Triggers (Phản hồi sự kiện CSDL)

* `sendMessageNotification`: Bắn Notification (FCM) ngay khi có tin nhắn mới, kèm dữ liệu để OS hiển thị Bubble chat.
* `onCallCreated`, `onGroupCallCreated`, `onCallUpdated`: Điều hướng chuông báo và Push data gọi điện.
* `updateUserPresence`: Cập nhật `lastSeen` khi user mất kết nối.
* `scheduleMessageDeletion`: Set mốc thời gian xóa dựa theo cấu hình nhóm.
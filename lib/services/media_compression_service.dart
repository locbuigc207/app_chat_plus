import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

class MediaCompressionService {
  static final MediaCompressionService _instance =
      MediaCompressionService._internal();
  factory MediaCompressionService() => _instance;
  MediaCompressionService._internal();

  /// 1. NÉN HÌNH ẢNH (Giảm ~80% dung lượng, giữ nguyên độ nét)
  Future<File?> compressImage(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      // Chuyển đổi sang định dạng JPEG để tối ưu nhất cho thiết bị di động
      final targetPath =
          "${dir.absolute.path}/temp_img_${DateTime.now().millisecondsSinceEpoch}.jpg";

      var result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 75, // Chất lượng tối ưu (Zalo/Messenger thường dùng 70-80)
        minWidth: 1280, // Giới hạn độ phân giải tối đa
        minHeight: 1280,
        format: CompressFormat.jpeg,
      );

      if (result != null) {
        print(
            "📸 Nén ảnh thành công: ${file.lengthSync()} bytes -> ${File(result.path).lengthSync()} bytes");
        return File(result.path);
      }
      return null;
    } catch (e) {
      print("❌ Lỗi nén ảnh: $e");
      return file; // Fallback: Trả về file gốc nếu lỗi
    }
  }

  /// 2. NÉN VIDEO (Chuyển đổi bitrate phần cứng)
  Future<File?> compressVideo(File file) async {
    try {
      print("🎥 Đang nén video... Vui lòng chờ.");
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.Res640x480Quality, // Chuẩn nén tin nhắn chat
        deleteOrigin: false,
        includeAudio: true,
      );

      if (info != null && info.file != null) {
        print("🎥 Nén video xong: ${info.filesize} bytes");
        return info.file!;
      }
      return null;
    } catch (e) {
      print("❌ Lỗi nén video: $e");
      return file;
    }
  }

  /// 3. TRÍCH XUẤT ẢNH THUMBNAIL TỪ VIDEO (Dùng để hiển thị ngoài UI)
  Future<File?> getVideoThumbnail(File file) async {
    try {
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        file.path,
        quality: 50, // Thumbnail chỉ cần chất lượng thấp
        position: -1, // Lấy frame giữa video
      );
      return thumbnailFile;
    } catch (e) {
      print("❌ Lỗi lấy thumbnail: $e");
      return null;
    }
  }

  /// 4. Dọn dẹp cache sau khi gửi xong
  Future<void> clearCache() async {
    await VideoCompress.deleteAllCache();
  }
}

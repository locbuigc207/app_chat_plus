import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

class MediaCompressionConfig {
  final int imageQuality;
  final int imageMaxDimension;
  final int imageSizeThresholdBytes;

  final VideoQuality videoQuality;
  final bool videoIncludeAudio;
  final int videoFrameRate;
  final int videoSizeThresholdBytes;

  final int thumbnailQuality;
  final int thumbnailMaxDimension;

  const MediaCompressionConfig({
    this.imageQuality = 78,
    this.imageMaxDimension = 1280,
    this.imageSizeThresholdBytes = 100 * 1024,
    this.videoQuality = VideoQuality.Res640x480Quality,
    this.videoIncludeAudio = true,
    this.videoFrameRate = 30,
    this.videoSizeThresholdBytes = 512 * 1024,
    this.thumbnailQuality = 60,
    this.thumbnailMaxDimension = 480,
  });

  static const chat = MediaCompressionConfig();

  static const highQuality = MediaCompressionConfig(
    imageQuality: 90,
    imageMaxDimension: 1920,
    videoQuality: VideoQuality.Res1280x720Quality,
    videoFrameRate: 30,
  );

  static const lowBandwidth = MediaCompressionConfig(
    imageQuality: 60,
    imageMaxDimension: 800,
    videoQuality: VideoQuality.LowQuality,
    thumbnailQuality: 40,
  );
}

class CompressionResult {
  final File file;
  final int originalSizeBytes;
  final int compressedSizeBytes;
  final double compressionRatio;
  final Duration elapsed;
  final bool wasCompressed;

  const CompressionResult({
    required this.file,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.compressionRatio,
    required this.elapsed,
    required this.wasCompressed,
  });

  String get summary => '${_fmtSize(originalSizeBytes)} → ${_fmtSize(compressedSizeBytes)} '
      '(−${(compressionRatio * 100).round()}%) in ${elapsed.inMilliseconds}ms';

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(2)} MB';
  }
}

class MediaCompressionException implements Exception {
  final String message;
  final Object? cause;
  const MediaCompressionException(this.message, {this.cause});

  @override
  String toString() => 'MediaCompressionException: $message'
      '${cause != null ? ' (caused by: $cause)' : ''}';
}

class MediaCompressionService {
  MediaCompressionService._internal();
  static final MediaCompressionService _instance = MediaCompressionService._internal();
  factory MediaCompressionService() => _instance;

  Subscription? _progressSub;

  StreamController<double>? _progressController;

  Stream<double> get compressionProgressStream =>
      _progressController?.stream ?? const Stream.empty();

  void _startProgressBridge(void Function(double)? externalCallback) {
    _stopProgressBridge();

    _progressController = StreamController<double>.broadcast();

    _progressSub = VideoCompress.compressProgress$.subscribe((progress) {
      final normalized = ((progress as num) / 100.0).clamp(0.0, 1.0);
      if (!(_progressController?.isClosed ?? true)) {
        _progressController?.add(normalized);
      }
      externalCallback?.call(normalized);
    });
  }

  void _stopProgressBridge() {
    _progressSub?.unsubscribe();
    _progressSub = null;
    _progressController?.close();
    _progressController = null;
  }

  Future<CompressionResult> compressImage(
    File file, {
    MediaCompressionConfig config = MediaCompressionConfig.chat,
  }) async {
    final watch = Stopwatch()..start();
    final originalSize = await file.length();

    if (originalSize < config.imageSizeThresholdBytes) {
      watch.stop();
      return CompressionResult(
        file: file,
        originalSizeBytes: originalSize,
        compressedSizeBytes: originalSize,
        compressionRatio: 0,
        elapsed: watch.elapsed,
        wasCompressed: false,
      );
    }

    try {
      final dir = await getTemporaryDirectory();
      final ext = _resolveImageExt(file.path);
      final format = _resolveCompressFormat(ext);
      final targetPath = p.join(
        dir.path,
        'cimg_${_ts()}_${p.basenameWithoutExtension(file.path)}.$ext',
      );

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: config.imageQuality,
        minWidth: config.imageMaxDimension,
        minHeight: config.imageMaxDimension,
        format: format,
        keepExif: false,
        autoCorrectionAngle: true,
      );

      if (result == null) {
        throw MediaCompressionException('compressAndGetFile trả về null cho ${file.path}');
      }

      final compressed = File(result.path);
      final compressedSize = await compressed.length();
      watch.stop();

      if (compressedSize >= originalSize) {
        await compressed.delete().catchError((_) {});
        _log('⚠️ Nén ảnh không hiệu quả, giữ file gốc.');
        return CompressionResult(
          file: file,
          originalSizeBytes: originalSize,
          compressedSizeBytes: originalSize,
          compressionRatio: 0,
          elapsed: watch.elapsed,
          wasCompressed: false,
        );
      }

      final ratio = 1 - compressedSize / originalSize;
      final res = CompressionResult(
        file: compressed,
        originalSizeBytes: originalSize,
        compressedSizeBytes: compressedSize,
        compressionRatio: ratio,
        elapsed: watch.elapsed,
        wasCompressed: true,
      );
      _log('📸 ${res.summary}');
      return res;
    } on MediaCompressionException {
      rethrow;
    } catch (e) {
      _log('❌ compressImage: $e');
      watch.stop();
      return CompressionResult(
        file: file,
        originalSizeBytes: originalSize,
        compressedSizeBytes: originalSize,
        compressionRatio: 0,
        elapsed: watch.elapsed,
        wasCompressed: false,
      );
    }
  }

  Future<File> compressImageFile(
    File file, {
    MediaCompressionConfig config = MediaCompressionConfig.chat,
  }) async {
    final result = await compressImage(file, config: config);
    return result.file;
  }

  Future<CompressionResult> compressVideo(
    File file, {
    MediaCompressionConfig config = MediaCompressionConfig.chat,
    void Function(double progress)? onProgress,
  }) async {
    final watch = Stopwatch()..start();
    final originalSize = await file.length();

    if (originalSize < config.videoSizeThresholdBytes) {
      watch.stop();
      return CompressionResult(
        file: file,
        originalSizeBytes: originalSize,
        compressedSizeBytes: originalSize,
        compressionRatio: 0,
        elapsed: watch.elapsed,
        wasCompressed: false,
      );
    }

    _startProgressBridge(onProgress);

    try {
      _log('🎥 Bắt đầu nén video: ${_fmtSize(originalSize)}');

      final info = await VideoCompress.compressVideo(
        file.path,
        quality: config.videoQuality,
        deleteOrigin: false,
        includeAudio: config.videoIncludeAudio,
        frameRate: config.videoFrameRate,
      );

      _stopProgressBridge();

      if (info?.file == null) {
        throw MediaCompressionException('VideoCompress trả về null');
      }

      final compressedFile = info!.file!;
      final compressedSize = info.filesize ?? await compressedFile.length();
      watch.stop();

      if (compressedSize >= originalSize) {
        _log('⚠️ Nén video không hiệu quả, giữ file gốc.');
        return CompressionResult(
          file: file,
          originalSizeBytes: originalSize,
          compressedSizeBytes: originalSize,
          compressionRatio: 0,
          elapsed: watch.elapsed,
          wasCompressed: false,
        );
      }

      final ratio = 1 - compressedSize / originalSize;
      final res = CompressionResult(
        file: compressedFile,
        originalSizeBytes: originalSize,
        compressedSizeBytes: compressedSize,
        compressionRatio: ratio,
        elapsed: watch.elapsed,
        wasCompressed: true,
      );
      _log('✅ Video: ${res.summary}');
      return res;
    } on MediaCompressionException {
      _stopProgressBridge();
      rethrow;
    } catch (e) {
      _stopProgressBridge();
      _log('❌ compressVideo: $e');
      watch.stop();
      return CompressionResult(
        file: file,
        originalSizeBytes: originalSize,
        compressedSizeBytes: originalSize,
        compressionRatio: 0,
        elapsed: watch.elapsed,
        wasCompressed: false,
      );
    }
  }

  Future<File> compressVideoFile(
    File file, {
    MediaCompressionConfig config = MediaCompressionConfig.chat,
    void Function(double)? onProgress,
  }) async {
    final result = await compressVideo(file, config: config, onProgress: onProgress);
    return result.file;
  }

  Future<File?> getVideoThumbnail(
    File file, {
    int quality = 60,
    int positionMs = -1,
    int maxDimension = 480,
  }) async {
    try {
      final thumb = await VideoCompress.getFileThumbnail(
        file.path,
        quality: quality,
        position: positionMs,
      );

      final result = await compressImage(
        thumb,
        config: MediaCompressionConfig(
          imageQuality: quality,
          imageMaxDimension: maxDimension,
          imageSizeThresholdBytes: 0,
        ),
      );
      return result.file;
    } catch (e) {
      _log('❌ getVideoThumbnail: $e');
      return null;
    }
  }

  Future<List<CompressionResult>> compressImageBatch(
    List<File> files, {
    MediaCompressionConfig config = MediaCompressionConfig.chat,
    int maxConcurrent = 3,
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <CompressionResult>[];
    int done = 0;

    for (int i = 0; i < files.length; i += maxConcurrent) {
      final batch = files.sublist(i, (i + maxConcurrent).clamp(0, files.length));
      final batchResults = await Future.wait(
        batch.map((f) => compressImage(f, config: config)),
      );
      results.addAll(batchResults);
      done += batch.length;
      onProgress?.call(done, files.length);
    }
    return results;
  }

  static bool isImageFile(String path) {
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    return {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif'}.contains(ext);
  }

  static bool isVideoFile(String path) {
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    return {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp'}.contains(ext);
  }

  Future<void> cancelCompression() async {
    _stopProgressBridge();
    await VideoCompress.cancelCompression();
    _log('⛔ Đã huỷ nén video.');
  }

  Future<void> clearCache() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (e) {
      _log('⚠️ clearVideoCache: $e');
    }

    try {
      final tmp = await getTemporaryDirectory();
      final entities = tmp.listSync();
      int deleted = 0;
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith('cimg_') || name.startsWith('temp_img_') || name.contains('_thumb')) {
            await entity.delete().catchError((_) {});
            deleted++;
          }
        }
      }
      _log('🗑️ Đã xoá $deleted file cache.');
    } catch (e) {
      _log('⚠️ clearImageCache: $e');
    }
  }

  Future<int> getCacheSizeBytes() async {
    int total = 0;
    try {
      final tmp = await getTemporaryDirectory();
      final entities = tmp.listSync();
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith('cimg_') || name.contains('_thumb')) {
            total += await entity.length().catchError((_) => 0);
          }
        }
      }
    } catch (_) {}
    return total;
  }

  String _resolveImageExt(String path) {
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    if (['heic', 'heif'].contains(ext)) return 'jpg';
    if (ext == 'webp') return 'webp';
    if (ext == 'png') return 'png';
    return 'jpg';
  }

  CompressFormat _resolveCompressFormat(String ext) {
    switch (ext) {
      case 'webp':
        return CompressFormat.webp;
      case 'png':
        return CompressFormat.png;
      default:
        return CompressFormat.jpeg;
    }
  }

  String _ts() => DateTime.now().millisecondsSinceEpoch.toString();

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(2)} MB';
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[MediaCompress] $msg');
  }
}

import 'dart:io';

void main() async {
  print('BƯỚC 1: Đang chạy công cụ sửa lỗi tự động của Flutter (dart fix)...');
  var fixResult = await Process.run('dart', ['fix', '--apply']);
  print(fixResult.stdout);
  if (fixResult.stderr.toString().isNotEmpty) {
    print('Lỗi từ dart fix: ${fixResult.stderr}');
  }

  print('BƯỚC 2: Bắt đầu quét và xóa comment trong các file .dart...');
  final dir = Directory('lib');
  if (await dir.exists()) {
    final List<FileSystemEntity> entities =
        await dir.list(recursive: true).toList();
    final dartFiles =
        entities.whereType<File>().where((file) => file.path.endsWith('.dart'));

// Regex xóa comment nhiều dòng: /* ... */
    final multiLineComment = RegExp(r'\/\*[\s\S]*?\*\/');
// Regex xóa comment một dòng: // ... (Loại trừ '://' trong các URL tĩnh)
    final singleLineComment = RegExp(r'(?<!:)\/\/.*');

    int processedCount = 0;

    for (var file in dartFiles) {
      String content = await file.readAsString();

      bool hasChanged = false;
      if (content.contains('/*') || content.contains('//')) {
        content = content.replaceAll(multiLineComment, '');
        content = content.replaceAll(singleLineComment, '');
        hasChanged = true;
      }

      if (hasChanged) {
        await file.writeAsString(content);
        processedCount++;
      }
    }
    print('Đã hoàn tất xóa comment tại $processedCount file.');
  } else {
    print('Không tìm thấy thư mục lib.');
  }

  print('HOÀN TẤT!');
  print(
      'Lưu ý: Đối với lỗi "use_build_context_synchronously" và "avoid_print", bạn cần tự thêm "if (!mounted) return;" và đổi "print" thành "debugPrint" vì script tự động không thể thay đổi logic luồng code của bạn.');
}

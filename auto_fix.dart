// ignore_for_file: avoid_print
import 'dart:io';

// ─── Constants ────────────────────────────────────────────────────────────────

const _green = '\x1B[32m';
const _red = '\x1B[31m';
const _yellow = '\x1B[33m';
const _cyan = '\x1B[36m';
const _bold = '\x1B[1m';
const _reset = '\x1B[0m';

const _libDir = 'lib';
const _testDir = 'test';

// ─── Entry point ─────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);

  _printBanner();

  final stopwatch = Stopwatch()..start();
  int totalIssues = 0;

  // ── BƯỚC 1: dart fix --apply ──────────────────────────────────────────────
  if (!options.skipDartFix) {
    totalIssues += await _runDartFix(options);
  }

  // ── BƯỚC 2: dart format ───────────────────────────────────────────────────
  if (!options.skipFormat) {
    await _runDartFormat(options);
  }

  // ── BƯỚC 3: Xóa comment ───────────────────────────────────────────────────
  if (!options.skipComments) {
    await _removeComments(options);
  }

  // ── BƯỚC 4: Thay print → debugPrint ──────────────────────────────────────
  if (!options.skipPrint) {
    totalIssues += await _replacePrintWithDebugPrint(options);
  }

  // ── BƯỚC 5: Thêm mounted check sau async gap ─────────────────────────────
  if (!options.skipMounted) {
    totalIssues += await _addMountedChecks(options);
  }

  // ── BƯỚC 6: Xóa import không dùng ────────────────────────────────────────
  if (!options.skipUnusedImports) {
    totalIssues += await _removeUnusedImports(options);
  }

  // ── BƯỚC 7: Chuẩn hóa trailing commas ────────────────────────────────────
  if (!options.skipTrailingComma) {
    totalIssues += await _fixTrailingCommas(options);
  }

  // ── BƯỚC 8: Sắp xếp imports ──────────────────────────────────────────────
  if (!options.skipSortImports) {
    totalIssues += await _sortImports(options);
  }

  // ── BƯỚC 9: dart analyze (check lần cuối) ────────────────────────────────
  if (!options.skipAnalyze) {
    await _runDartAnalyze(options);
  }

  stopwatch.stop();

  _printSummary(totalIssues, stopwatch.elapsed);
}

// ─── CLI Argument Parser ──────────────────────────────────────────────────────

class _Options {
  final bool dryRun;
  final bool verbose;
  final bool skipDartFix;
  final bool skipFormat;
  final bool skipComments;
  final bool skipPrint;
  final bool skipMounted;
  final bool skipUnusedImports;
  final bool skipTrailingComma;
  final bool skipSortImports;
  final bool skipAnalyze;
  final List<String> targetDirs;

  const _Options({
    this.dryRun = false,
    this.verbose = false,
    this.skipDartFix = false,
    this.skipFormat = false,
    this.skipComments = false,
    this.skipPrint = false,
    this.skipMounted = false,
    this.skipUnusedImports = false,
    this.skipTrailingComma = false,
    this.skipSortImports = false,
    this.skipAnalyze = false,
  }) : targetDirs = const [_libDir, _testDir];
}

_Options _parseArgs(List<String> args) {
  return _Options(
    dryRun: args.contains('--dry-run') || args.contains('-n'),
    verbose: args.contains('--verbose') || args.contains('-v'),
    skipDartFix: args.contains('--skip-dart-fix'),
    skipFormat: args.contains('--skip-format'),
    skipComments: args.contains('--skip-comments'),
    skipPrint: args.contains('--skip-print'),
    skipMounted: args.contains('--skip-mounted'),
    skipUnusedImports: args.contains('--skip-unused-imports'),
    skipTrailingComma: args.contains('--skip-trailing-comma'),
    skipSortImports: args.contains('--skip-sort-imports'),
    skipAnalyze: args.contains('--skip-analyze'),
  );
}

// ─── Step 1: dart fix ────────────────────────────────────────────────────────

Future<int> _runDartFix(_Options opts) async {
  _printStep(1, 'dart fix --apply');
  if (opts.dryRun) {
    _info('  [dry-run] Bỏ qua');
    return 0;
  }

  try {
    final result = await Process.run('dart', ['fix', '--apply']);
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();

    if (stdout.isNotEmpty && opts.verbose) print('  $stdout');
    if (stderr.isNotEmpty) _warn('  dart fix stderr: $stderr');

    // Đếm số fix đã áp dụng
    final fixes = RegExp(r'(\d+) fix').firstMatch(stdout)?.group(1) ?? '0';
    _ok('  Áp dụng $fixes fix(es)');
    return int.tryParse(fixes) ?? 0;
  } catch (e) {
    _err('  Không chạy được dart fix: $e');
    return 0;
  }
}

// ─── Step 2: dart format ─────────────────────────────────────────────────────

Future<void> _runDartFormat(_Options opts) async {
  _printStep(2, 'dart format');
  if (opts.dryRun) {
    _info('  [dry-run] Bỏ qua');
    return;
  }

  try {
    final result = await Process.run('dart', [
      'format',
      '--line-length=100',
      _libDir,
      if (await Directory(_testDir).exists()) _testDir,
    ]);
    final stdout = result.stdout.toString().trim();
    final changed =
        RegExp(r'Formatted (\d+)').firstMatch(stdout)?.group(1) ?? '0';
    _ok('  Format $changed file(s)');
  } catch (e) {
    _err('  dart format lỗi: $e');
  }
}

// ─── Step 3: Remove comments ──────────────────────────────────────────────────

Future<void> _removeComments(_Options opts) async {
  _printStep(3, 'Xóa comment');

  final files = await _collectDartFiles(opts.targetDirs);
  int changed = 0;

  final multiLine = RegExp(r'/\*[\s\S]*?\*/', multiLine: true);

  final singleLine = RegExp(r'''(?<![:"'`])//(?!/).*$''', multiLine: true);

// Doc comment: /// ...
  final docComment = RegExp(r'///.*$', multiLine: true);

  for (final file in files) {
    final original = await file.readAsString();
    var content = original;

    // Bỏ qua file chỉ có shebang hoặc ignore comment
    if (!content.contains('//') && !content.contains('/*')) continue;

    // Xóa doc comment trước
    content = content.replaceAll(docComment, '');
    // Xóa multi-line
    content = content.replaceAll(multiLine, '');
    // Xóa single-line (giữ lại // ignore: và // ignore_for_file:)
    content = content.replaceAllMapped(singleLine, (m) {
      final line = m.group(0) ?? '';
      if (line.trim().startsWith('// ignore') ||
          line.trim().startsWith('// coverage:') ||
          line.trim().startsWith('// TODO') ||
          line.trim().startsWith('// FIXME')) {
        return line; // Giữ lại các comment đặc biệt
      }
      return '';
    });

    // Xóa dòng trống liên tiếp (> 2 dòng)
    content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    if (content != original) {
      if (!opts.dryRun) await file.writeAsString(content);
      changed++;
      if (opts.verbose) _info('  Xóa comment: ${_relPath(file.path)}');
    }
  }

  _ok('  Đã xử lý $changed/${files.length} file(s)');
}

// ─── Step 4: Replace print → debugPrint ──────────────────────────────────────

Future<int> _replacePrintWithDebugPrint(_Options opts) async {
  _printStep(4, 'Thay print() → debugPrint()');

  final files = await _collectDartFiles(opts.targetDirs);
  int changedFiles = 0;
  int totalReplacements = 0;

  // Chỉ thay print( mà không phải debugPrint, sprint, footprint, v.v.
  final printRegex = RegExp(r'(?<![a-zA-Z_$])print\s*\(');

  for (final file in files) {
    final original = await file.readAsString();
    if (!printRegex.hasMatch(original)) continue;

    var content = original;
    int count = 0;

    content = content.replaceAllMapped(printRegex, (m) {
      count++;
      return 'debugPrint(';
    });

    // Thêm import foundation nếu chưa có
    if (count > 0 &&
        !content.contains("import 'package:flutter/foundation.dart'")) {
      content = _ensureFoundationImport(content);
    }

    if (content != original) {
      if (!opts.dryRun) await file.writeAsString(content);
      changedFiles++;
      totalReplacements += count;
      if (opts.verbose) {
        _info('  ${_relPath(file.path)}: $count replacement(s)');
      }
    }
  }

  _ok('  $totalReplacements print() → debugPrint() trong $changedFiles file(s)');
  return totalReplacements;
}

String _ensureFoundationImport(String content) {
  if (content.contains("import 'package:flutter/foundation.dart'") ||
      content.contains('import "package:flutter/foundation.dart"')) {
    return content;
  }

  // Chèn sau dòng import cuối cùng của flutter/material hoặc đầu file
  final materialImport = RegExp(r"import 'package:flutter/material\.dart';");
  if (materialImport.hasMatch(content)) {
    return content.replaceFirst(
      materialImport,
      "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';",
    );
  }

  // Chèn trước dòng import đầu tiên
  final firstImport = RegExp(r'^import ', multiLine: true);
  final match = firstImport.firstMatch(content);
  if (match != null) {
    return "${content.substring(0, match.start)}import 'package:flutter/foundation.dart';\n${content.substring(match.start)}";
  }

  return content;
}

// ─── Step 5: Add mounted checks ───────────────────────────────────────────────

Future<int> _addMountedChecks(_Options opts) async {
  _printStep(5, 'Thêm mounted check (use_build_context_synchronously)');

  // Pattern: await ... sau đó dùng context hoặc Navigator/ScaffoldMessenger
  // Đây là heuristic – không thể 100% chính xác mà không parse AST
  final files = await _collectDartFiles([_libDir]);
  int suggestions = 0;

  final awaitThenContextRegex = RegExp(
    r'(await\s+[^;]+;)\s*\n(\s*)((?:Navigator|ScaffoldMessenger|showDialog|showModalBottomSheet|Theme\.of|Provider\.of)\s*\(?\s*context)',
    multiLine: true,
  );

  for (final file in files) {
    final content = await file.readAsString();
    final matches = awaitThenContextRegex.allMatches(content);

    for (final match in matches) {
      final line = match.start;
      final lineNum = '\n'.allMatches(content.substring(0, line)).length + 1;

      // Kiểm tra xem đã có mounted check chưa
      final before = content.substring(
          (match.start - 200).clamp(0, content.length), match.start);
      if (before.contains('if (!mounted)') ||
          before.contains('if (mounted)') ||
          before.contains('if (!context.mounted)')) {
        continue;
      }

      suggestions++;
      if (opts.verbose) {
        _warn(
            '  ⚠ ${_relPath(file.path)}:$lineNum → Cần thêm mounted check trước: ${match.group(3)?.trim()}');
      }
    }

    // Tự động thêm mounted check nếu pattern rõ ràng
    if (!opts.dryRun && matches.isNotEmpty) {
      var newContent = content.replaceAllMapped(
        awaitThenContextRegex,
        (m) {
          final awaitLine = m.group(1) ?? '';
          final indent = m.group(2) ?? '';
          final contextLine = m.group(3) ?? '';
          final before200 = content.substring(
              (m.start - 200).clamp(0, content.length), m.start);
          if (before200.contains('if (!mounted)') ||
              before200.contains('if (mounted)')) {
            return m.group(0)!;
          }
          return '$awaitLine\n${indent}if (!mounted) return;\n$indent$contextLine';
        },
      );

      if (newContent != content) {
        await file.writeAsString(newContent);
      }
    }
  }

  if (suggestions > 0) {
    _warn(
        '  $suggestions vị trí cần kiểm tra mounted (đã tự động thêm nếu có thể)');
  } else {
    _ok('  Không tìm thấy vấn đề mounted check');
  }
  return suggestions;
}

// ─── Step 6: Remove unused imports ───────────────────────────────────────────

Future<int> _removeUnusedImports(_Options opts) async {
  _printStep(6, 'Kiểm tra unused imports (qua dart analyze)');

  try {
    final result =
        await Process.run('dart', ['analyze', '--format=json', _libDir]);
    final output = result.stdout.toString();

    int unusedCount = 0;

    // Parse JSON output của dart analyze
    if (output.contains('unused_import')) {
      final lines = output.split('\n');
      for (final line in lines) {
        if (line.contains('unused_import')) {
          unusedCount++;
          if (opts.verbose) _warn('  $line');
        }
      }
    }

    if (unusedCount > 0) {
      _warn(
          '  $unusedCount unused import(s) – Chạy "dart fix --apply" để tự sửa');
    } else {
      _ok('  Không có unused import');
    }

    return unusedCount;
  } catch (e) {
    _err('  Không phân tích được: $e');
    return 0;
  }
}

// ─── Step 7: Fix trailing commas ─────────────────────────────────────────────

Future<int> _fixTrailingCommas(_Options opts) async {
  _printStep(7, 'Chuẩn hóa trailing commas');

  final files = await _collectDartFiles([_libDir]);
  int changed = 0;

  // Thêm trailing comma vào constructor/function call nhiều dòng
  final missingTrailingComma = RegExp(
    r'(\w+)\s*\n(\s*)\)',
    multiLine: true,
  );

  for (final file in files) {
    final original = await file.readAsString();
    var content = original;

    content = content.replaceAllMapped(missingTrailingComma, (m) {
      final word = m.group(1) ?? '';
      final indent = m.group(2) ?? '';
      // Không thêm nếu đã có comma, hoặc là keyword
      const keywords = ['return', 'break', 'continue', 'throw', 'yield'];
      if (keywords.contains(word) || word.endsWith(',')) return m.group(0)!;
      return '$word,\n$indent)';
    });

    if (content != original) {
      if (!opts.dryRun) await file.writeAsString(content);
      changed++;
    }
  }

  _ok('  $changed file(s) được cập nhật trailing comma');
  return changed;
}

// ─── Step 8: Sort imports ──────────────────────────────────────────────────────

Future<int> _sortImports(_Options opts) async {
  _printStep(8, 'Sắp xếp imports (dart, package, relative)');

  final files = await _collectDartFiles([_libDir]);
  int changed = 0;

  for (final file in files) {
    final original = await file.readAsString();
    final sorted = _sortFileImports(original);

    if (sorted != original) {
      if (!opts.dryRun) await file.writeAsString(sorted);
      changed++;
      if (opts.verbose) _info('  Sort imports: ${_relPath(file.path)}');
    }
  }

  _ok('  $changed file(s) sắp xếp import');
  return changed;
}

String _sortFileImports(String content) {
  final lines = content.split('\n');

  // Tìm block import
  int importStart = -1;
  int importEnd = -1;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('import ')) {
      if (importStart == -1) importStart = i;
      importEnd = i;
    } else if (importStart != -1 &&
        line.isNotEmpty &&
        !line.startsWith('import ') &&
        !line.startsWith('//') &&
        !line.startsWith('///')) {
      break;
    }
  }

  if (importStart == -1) return content;

  final importLines = lines
      .sublist(importStart, importEnd + 1)
      .where((l) => l.trim().startsWith('import '))
      .toList();

  // Phân loại
  final dartImports = importLines
      .where((l) => l.contains("'dart:") || l.contains('"dart:'))
      .toList()
    ..sort();

  final flutterImports = importLines
      .where((l) =>
          l.contains("'package:flutter/") || l.contains('"package:flutter/'))
      .toList()
    ..sort();

  final packageImports = importLines
      .where((l) =>
          (l.contains("'package:") || l.contains('"package:')) &&
          !l.contains("'package:flutter/") &&
          !l.contains('"package:flutter/'))
      .toList()
    ..sort();

  final relativeImports = importLines
      .where((l) =>
          !l.contains("'dart:") &&
          !l.contains('"dart:') &&
          !l.contains("'package:") &&
          !l.contains('"package:'))
      .toList()
    ..sort();

  final sortedImports = <String>[];
  if (dartImports.isNotEmpty) {
    sortedImports.addAll(dartImports);
    sortedImports.add('');
  }
  if (flutterImports.isNotEmpty) {
    sortedImports.addAll(flutterImports);
    sortedImports.add('');
  }
  if (packageImports.isNotEmpty) {
    sortedImports.addAll(packageImports);
    sortedImports.add('');
  }
  if (relativeImports.isNotEmpty) {
    sortedImports.addAll(relativeImports);
  }

  // Xóa trailing empty line
  while (sortedImports.isNotEmpty && sortedImports.last.isEmpty) {
    sortedImports.removeLast();
  }

  final newLines = [
    ...lines.sublist(0, importStart),
    ...sortedImports,
    ...lines.sublist(importEnd + 1),
  ];

  return newLines.join('\n');
}

// ─── Step 9: dart analyze ─────────────────────────────────────────────────────

Future<void> _runDartAnalyze(_Options opts) async {
  _printStep(9, 'dart analyze (kiểm tra lần cuối)');

  try {
    final result = await Process.run('dart', ['analyze', _libDir]);
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();

    final errors = RegExp(r'error\s*-').allMatches(stdout).length;
    final warnings = RegExp(r'warning\s*-').allMatches(stdout).length;
    final hints = RegExp(r'info\s*-').allMatches(stdout).length;

    if (errors > 0) {
      _err('  ❌ $errors error(s), $warnings warning(s), $hints info(s)');
      if (opts.verbose && stdout.isNotEmpty) print(stdout);
    } else if (warnings > 0) {
      _warn('  ⚠ $warnings warning(s), $hints info(s)');
      if (opts.verbose && stdout.isNotEmpty) print(stdout);
    } else {
      _ok('  Không có lỗi/cảnh báo (${hints > 0 ? "$hints info(s)" : "clean"})');
    }

    if (stderr.isNotEmpty && opts.verbose) _warn('  $stderr');
  } catch (e) {
    _err('  dart analyze lỗi: $e');
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Future<List<File>> _collectDartFiles(List<String> dirs) async {
  final files = <File>[];
  for (final dirPath in dirs) {
    final dir = Directory(dirPath);
    if (!await dir.exists()) continue;
    final entities = await dir.list(recursive: true).toList();
    files.addAll(
      entities
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          // Bỏ qua file generated
          .where((f) =>
              !f.path.contains('.g.dart') &&
              !f.path.contains('.freezed.dart') &&
              !f.path.contains('.gr.dart') &&
              !f.path.contains('.mocks.dart')),
    );
  }
  return files;
}

String _relPath(String path) {
  final cwd = Directory.current.path;
  return path.startsWith(cwd) ? path.substring(cwd.length + 1) : path;
}

// ─── Console Output ───────────────────────────────────────────────────────────

void _printBanner() {
  print('');
  print(
      '$_bold$_cyan╔══════════════════════════════════════════════════╗$_reset');
  print(
      '$_bold$_cyan║         🛠  Flutter Auto-Fix Tool v2.0            ║$_reset');
  print(
      '$_bold$_cyan╚══════════════════════════════════════════════════╝$_reset');
  print('  Thư mục: ${Directory.current.path}');
  print('  Thời gian: ${DateTime.now().toIso8601String()}');
  print('');
}

void _printStep(int step, String name) {
  print('\n$_bold[$step/9] $name$_reset');
  print('  ${'─' * 50}');
}

void _printSummary(int totalIssues, Duration elapsed) {
  print('');
  print(
      '$_bold$_cyan╔══════════════════════════════════════════════════╗$_reset');
  print(
      '$_bold$_cyan║                  📊 TÓM TẮT                       ║$_reset');
  print(
      '$_bold$_cyan╚══════════════════════════════════════════════════╝$_reset');
  print(
      '  ⏱  Thời gian: ${elapsed.inSeconds}s ${elapsed.inMilliseconds % 1000}ms');
  print('  🔧 Tổng vấn đề xử lý: $totalIssues');
  print('');
  print('$_bold$_green✅ HOÀN TẤT!$_reset');
  print('');
  print('$_yellow💡 Lưu ý:$_reset');
  print('  • Kiểm tra lại các file đã thay đổi trước khi commit');
  print('  • Chạy "flutter test" để đảm bảo không có regression');
  print('  • Một số mounted check phức tạp cần kiểm tra thủ công');
  print('  • File generated (*.g.dart, *.freezed.dart) đã được bỏ qua');
  print('');
  print('$_yellow🚀 Gợi ý tiếp theo:$_reset');
  print('  • flutter pub run build_runner build --delete-conflicting-outputs');
  print('  • flutter test --coverage');
  print('  • flutter build apk --release');
  print('');
}

void _ok(String msg) => print('$_green✓$_reset $msg');
void _warn(String msg) => print('$_yellow⚠$_reset $msg');
void _err(String msg) => print('$_red✗$_reset $msg');
void _info(String msg) => print('  $msg');

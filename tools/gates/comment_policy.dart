import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

final class CommentViolation implements Comparable<CommentViolation> {
  const CommentViolation(this.path, this.line, this.preview);

  final String path;
  final int line;
  final String preview;

  @override
  int compareTo(CommentViolation other) {
    final pathOrder = path.compareTo(other.path);
    if (pathOrder != 0) return pathOrder;
    return line.compareTo(other.line);
  }

  @override
  String toString() => '$path:$line $preview';
}

final class CommentPolicy {
  CommentPolicy({required String root}) : root = p.normalize(p.absolute(root));

  final String root;

  static const Set<String> securityRationaleFiles = <String>{
    'apps/studio/lib/src/authoring/experience_authoring_controller.dart',
    'apps/studio/lib/src/host/studio_experience_transport.dart',
    'apps/studio/lib/src/host/studio_host_client.dart',
    'apps/studio/lib/src/host/studio_host_client_web.dart',
    'apps/studio/lib/src/jaspr/verified_artifact_image.dart',
    'apps/studio/lib/src/lab/scenario_lab_relay_controller.dart',
    'apps/studio/lib/src/lab/studio_lab_relay_transport.dart',
    'apps/studio/lib/src/quality/scenario_quality_decision_controller.dart',
    'apps/studio/lib/src/target_frame/target_frame_launch.dart',
    'apps/studio/lib/src/target_frame/target_frame_web.dart',
    'libs/execution_runtime/lib/src/authoring/filesystem_experience_authoring_store.dart',
    'libs/execution_runtime/lib/src/authoring/projection_layout_preserving_swap.dart',
    'libs/execution_runtime/lib/src/authoring/projection_layout_promotion.dart',
    'libs/execution_runtime/lib/src/evidence/android_evidence_provider.dart',
    'libs/execution_runtime/lib/src/evidence/png_capture_inspector.dart',
    'libs/execution_runtime/lib/src/lab/scenario_lab_execution_service.dart',
    'libs/flutter_app_adapter/lib/src/app_adapter_bridge_web.dart',
  };

  static const Set<String> operationalRationaleFiles = <String>{
    'apps/remote_worker/Dockerfile',
    'deploy/helm/control-plane/values.yaml',
    'apps/hosted_control_plane/migrations/0001_expand_hosted_v1.sql',
    'apps/hosted_control_plane/migrations/0002_contract_hosted_v1.sql',
    'apps/hosted_control_plane/migrations/0003_expand_remote_v1.sql',
    'apps/hosted_control_plane/migrations/0004_expand_remote_transport.sql',
    'apps/hosted_control_plane/migrations/0005_contract_remote_transport.sql',
    'apps/hosted_control_plane/migrations/0006_expand_remote_cleanup.sql',
    'examples/sample_flutter/.experience/lab/script-dashboard-ready.yaml',
  };

  List<CommentViolation> check() {
    final violations = <CommentViolation>[];
    for (final path in _intendedPaths()) {
      final file = File(p.join(root, path));
      if (!file.existsSync() || file.lengthSync() > 4 * 1024 * 1024) continue;
      final scanner = _scannerFor(path);
      if (scanner == null) continue;
      final source = file.readAsStringSync();
      for (final comment in scanner(source, path)) {
        if (_isAllowed(path, comment)) continue;
        violations.add(
          CommentViolation(
            path,
            comment.line,
            comment.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
          ),
        );
      }
    }
    return violations..sort();
  }

  bool supports(String path) => _scannerFor(path) != null;

  String removeNonEssentialComments(String path, String source) {
    final scanner = _scannerFor(path);
    if (scanner == null) return source;
    final comments =
        scanner(
            source,
            path,
          ).where((comment) => !_isAllowed(path, comment)).toList()
          ..sort((a, b) => b.offset.compareTo(a.offset));
    var result = source;
    for (final comment in comments) {
      final lineStart = source.lastIndexOf('\n', comment.offset - 1) + 1;
      final lineBreak = source.indexOf('\n', comment.end);
      final lineEnd = lineBreak == -1 ? source.length : lineBreak + 1;
      final before = source.substring(lineStart, comment.offset);
      final after = source.substring(
        comment.end,
        lineBreak == -1 ? source.length : lineBreak,
      );
      final removeWholeLine = before.trim().isEmpty && after.trim().isEmpty;
      result = result.replaceRange(
        removeWholeLine ? lineStart : comment.offset,
        removeWholeLine ? lineEnd : comment.end,
        '',
      );
    }
    return result;
  }

  bool _isAllowed(String path, _LexicalComment comment) {
    final text = comment.text.trim();
    if (text.startsWith('#!')) return true;
    if (RegExp(r'^#\s*shellcheck\b').hasMatch(text)) return true;
    if (path.startsWith('.github/workflows/') &&
        RegExp(r'^#\s*v\d+(?:\.\d+)+\s*$').hasMatch(text)) {
      return true;
    }
    if (RegExp(
      r'^//\s*(ignore(?::|_for_file:)|dart format\b|coverage:ignore\b|GENERATED FILE\b|Generated with\b)',
    ).hasMatch(text)) {
      return true;
    }
    if (RegExp(
      r'copyright|SPDX-License-Identifier',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }
    if (comment.isEmptyCatchRationale) return true;
    if (_isGeneratedFile(path)) return true;
    if (securityRationaleFiles.contains(path) ||
        operationalRationaleFiles.contains(path)) {
      return true;
    }
    if (comment.isDocumentation &&
        path.startsWith('libs/') &&
        path.contains('/lib/')) {
      return true;
    }
    return false;
  }

  List<String> _intendedPaths() {
    if (Directory(p.join(root, '.git')).existsSync()) {
      final result = Process.runSync('git', <String>[
        '-C',
        root,
        'ls-files',
        '-z',
      ]);
      if (result.exitCode != 0) {
        throw StateError('git ls-files failed: ${result.stderr}');
      }
      return (result.stdout as String)
          .split('\x00')
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
    }
    final paths = <String>[];
    for (final entity in Directory(
      root,
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: root);
      if (!_isIgnoredFallbackPath(relative)) paths.add(relative);
    }
    paths.sort();
    return paths;
  }

  static _CommentScanner? _scannerFor(String path) {
    final basename = p.basename(path);
    final extension = p.extension(path).toLowerCase();
    if (extension == '.dart') return _scanDartComments;
    if (extension == '.sh' ||
        extension == '.yaml' ||
        extension == '.yml' ||
        extension == '.properties' ||
        basename == 'Dockerfile') {
      return (source, _) => _scanHashComments(
        source,
        shell: extension == '.sh' || basename == 'Dockerfile',
        yaml: extension == '.yaml' || extension == '.yml',
      );
    }
    if (extension == '.css' ||
        extension == '.java' ||
        extension == '.kt' ||
        extension == '.kts' ||
        extension == '.gradle') {
      return (source, _) => _scanCStyleComments(source);
    }
    if (extension == '.html' || extension == '.xml') {
      return (source, _) => _scanMarkupComments(source);
    }
    if (extension == '.sql') {
      return (source, _) => _scanSqlComments(source);
    }
    return null;
  }

  static List<_LexicalComment> _scanDartComments(String source, String path) {
    final comments = <_LexicalComment>[];
    final parsed = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    );
    final emptyCatchBodies = <({int start, int end})>[];
    parsed.unit.accept(_EmptyCatchVisitor(emptyCatchBodies));
    var token = parsed.unit.beginToken;
    while (true) {
      Token? comment = token.precedingComments;
      while (comment != null) {
        final text = comment.lexeme;
        final commentOffset = comment.offset;
        final commentEnd = comment.end;
        comments.add(
          _LexicalComment(
            offset: commentOffset,
            end: commentEnd,
            line: _lineAt(source, commentOffset),
            text: text,
            isDocumentation:
                text.trimLeft().startsWith('///') ||
                text.trimLeft().startsWith('/**'),
            isEmptyCatchRationale: emptyCatchBodies.any(
              (body) => commentOffset >= body.start && commentEnd <= body.end,
            ),
          ),
        );
        comment = comment.next;
      }
      if (token.isEof) break;
      token = token.next!;
    }
    return comments;
  }

  static List<_LexicalComment> _scanHashComments(
    String source, {
    required bool shell,
    required bool yaml,
  }) {
    final comments = <_LexicalComment>[];
    var quote = _Quote.none;
    String? heredoc;
    int? yamlBlockIndent;
    var offset = 0;
    for (final lineWithEnding in _linesWithEndings(source)) {
      final line = lineWithEnding.replaceFirst(RegExp(r'\r?\n$'), '');
      final trimmed = line.trim();
      final indent = line.length - line.trimLeft().length;
      if (heredoc != null) {
        if (trimmed == heredoc) heredoc = null;
        offset += lineWithEnding.length;
        continue;
      }
      if (yamlBlockIndent != null) {
        if (trimmed.isEmpty || indent > yamlBlockIndent) {
          offset += lineWithEnding.length;
          continue;
        }
        yamlBlockIndent = null;
      }
      var escaped = false;
      int? commentStart;
      for (var index = 0; index < line.length; index += 1) {
        final character = line[index];
        if (quote == _Quote.single) {
          if (character == "'") quote = _Quote.none;
          continue;
        }
        if (quote == _Quote.double) {
          if (escaped) {
            escaped = false;
          } else if (character == r'\') {
            escaped = true;
          } else if (character == '"') {
            quote = _Quote.none;
          }
          continue;
        }
        if (character == "'") {
          quote = _Quote.single;
          continue;
        }
        if (character == '"') {
          quote = _Quote.double;
          continue;
        }
        final shellParameterHash =
            shell &&
            ((index > 0 && line[index - 1] == r'$') ||
                (index > 1 &&
                    line[index - 1] == '{' &&
                    line[index - 2] == r'$'));
        if (character == '#' &&
            !shellParameterHash &&
            (index == 0 || RegExp(r'[\s;|&(){}]').hasMatch(line[index - 1]))) {
          commentStart = index;
          break;
        }
      }
      final code = commentStart == null
          ? line
          : line.substring(0, commentStart);
      if (commentStart != null) {
        comments.add(
          _LexicalComment(
            offset: offset + commentStart,
            end: offset + line.length,
            line: _lineAt(source, offset + commentStart),
            text: line.substring(commentStart),
          ),
        );
      }
      if (shell) {
        final match = RegExp(
          r'''<<-?\s*(?:['"])?([A-Za-z_][A-Za-z0-9_]*)(?:['"])?''',
        ).firstMatch(code);
        if (match != null) heredoc = match.group(1);
      }
      if (yaml && RegExp(r'[:\-]\s*[|>]\s*[+\-]?\s*$').hasMatch(code)) {
        yamlBlockIndent = indent;
      }
      offset += lineWithEnding.length;
    }
    return comments;
  }

  static List<_LexicalComment> _scanCStyleComments(String source) =>
      _scanDelimitedComments(
        source,
        lineMarker: '//',
        blockStart: '/*',
        blockEnd: '*/',
      );

  static List<_LexicalComment> _scanSqlComments(String source) =>
      _scanDelimitedComments(
        source,
        lineMarker: '--',
        blockStart: '/*',
        blockEnd: '*/',
      );

  static List<_LexicalComment> _scanMarkupComments(String source) {
    final comments = <_LexicalComment>[];
    var offset = 0;
    while (true) {
      final start = source.indexOf('<!--', offset);
      if (start < 0) break;
      final closing = source.indexOf('-->', start + 4);
      final end = closing < 0 ? source.length : closing + 3;
      comments.add(
        _LexicalComment(
          offset: start,
          end: end,
          line: _lineAt(source, start),
          text: source.substring(start, end),
        ),
      );
      offset = end;
    }
    return comments;
  }

  static List<_LexicalComment> _scanDelimitedComments(
    String source, {
    required String lineMarker,
    required String blockStart,
    required String blockEnd,
  }) {
    final comments = <_LexicalComment>[];
    var quote = _Quote.none;
    var escaped = false;
    var offset = 0;
    while (offset < source.length) {
      final character = source[offset];
      if (quote == _Quote.single) {
        if (character == "'" && !escaped) quote = _Quote.none;
        escaped = character == r'\' && !escaped;
        offset += 1;
        continue;
      }
      if (quote == _Quote.double) {
        if (character == '"' && !escaped) quote = _Quote.none;
        escaped = character == r'\' && !escaped;
        offset += 1;
        continue;
      }
      if (character == "'") {
        quote = _Quote.single;
        offset += 1;
        continue;
      }
      if (character == '"') {
        quote = _Quote.double;
        offset += 1;
        continue;
      }
      if (source.startsWith(lineMarker, offset)) {
        final lineEnd = source.indexOf('\n', offset);
        final end = lineEnd < 0 ? source.length : lineEnd;
        comments.add(
          _LexicalComment(
            offset: offset,
            end: end,
            line: _lineAt(source, offset),
            text: source.substring(offset, end),
          ),
        );
        offset = end;
        continue;
      }
      if (source.startsWith(blockStart, offset)) {
        final closing = source.indexOf(blockEnd, offset + blockStart.length);
        final end = closing < 0 ? source.length : closing + blockEnd.length;
        comments.add(
          _LexicalComment(
            offset: offset,
            end: end,
            line: _lineAt(source, offset),
            text: source.substring(offset, end),
          ),
        );
        offset = end;
        continue;
      }
      offset += 1;
    }
    return comments;
  }

  static bool _isGeneratedFile(String path) {
    if (path == 'apps/studio/lib/main.client.options.dart' ||
        path == 'examples/sample_flutter/android/gradlew' ||
        path == 'examples/sample_flutter/android/gradle.properties' ||
        path == 'examples/sample_flutter/android/app/build.gradle.kts') {
      return true;
    }
    if (!path.startsWith('examples/sample_flutter/android/')) return false;
    return path.endsWith('AndroidManifest.xml') ||
        path.endsWith('/styles.xml') ||
        path.endsWith('/launch_background.xml');
  }

  static bool _isIgnoredFallbackPath(String path) {
    final segments = p.split(path);
    const ignored = <String>{
      '.git',
      '.dart_tool',
      'build',
      '.artifacts',
      '.idea',
    };
    const generatedFiles = <String>{
      'examples/sample_flutter/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
      'examples/sample_flutter/android/local.properties',
    };
    return segments.any(ignored.contains) || generatedFiles.contains(path);
  }

  static int _lineAt(String source, int offset) =>
      RegExp('\n').allMatches(source.substring(0, offset)).length + 1;

  static Iterable<String> _linesWithEndings(String source) sync* {
    var start = 0;
    for (var index = 0; index < source.length; index += 1) {
      if (source.codeUnitAt(index) != 10) continue;
      yield source.substring(start, index + 1);
      start = index + 1;
    }
    if (start < source.length) yield source.substring(start);
  }
}

typedef _CommentScanner =
    List<_LexicalComment> Function(String source, String path);

enum _Quote { none, single, double }

final class _LexicalComment {
  const _LexicalComment({
    required this.offset,
    required this.end,
    required this.line,
    required this.text,
    this.isDocumentation = false,
    this.isEmptyCatchRationale = false,
  });

  final int offset;
  final int end;
  final int line;
  final String text;
  final bool isDocumentation;
  final bool isEmptyCatchRationale;
}

final class _EmptyCatchVisitor extends RecursiveAstVisitor<void> {
  _EmptyCatchVisitor(this.bodies);

  final List<({int start, int end})> bodies;

  @override
  void visitCatchClause(CatchClause node) {
    if (node.body.statements.isEmpty) {
      bodies.add((
        start: node.body.leftBracket.end,
        end: node.body.rightBracket.offset,
      ));
    }
    super.visitCatchClause(node);
  }
}

void main(List<String> arguments) {
  final root = arguments.isEmpty ? Directory.current.path : arguments.single;
  final violations = CommentPolicy(root: root).check();
  if (violations.isEmpty) return;
  stderr.writeln('Non-essential comment violations:');
  for (final violation in violations) {
    stderr.writeln('- $violation');
  }
  exitCode = 1;
}

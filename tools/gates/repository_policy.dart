import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

final class PolicyViolation implements Comparable<PolicyViolation> {
  const PolicyViolation(this.code, this.path, this.detail);

  final String code;
  final String path;
  final String detail;

  @override
  int compareTo(PolicyViolation other) {
    final pathOrder = path.compareTo(other.path);
    if (pathOrder != 0) return pathOrder;
    final codeOrder = code.compareTo(other.code);
    if (codeOrder != 0) return codeOrder;
    return detail.compareTo(other.detail);
  }

  @override
  String toString() => '$path [$code] $detail';
}

final class RepositoryPolicy {
  RepositoryPolicy({required String root})
    : root = p.normalize(p.absolute(root));

  final String root;

  static const String _retiredTechnicalToken =
      'dev'
      'ex';
  static const String _retiredKitToken =
      'dev'
      'exkit';
  static const String _retiredCssToken =
      'd'
      'x';
  static const String _endAnchor = r'$';

  static const Map<String, String> technicalVersionPaths = <String, String>{
    'apps/hosted_control_plane/migrations/0001_expand_hosted_v1.sql':
        'deployed database migration sequence and stored schema generation',
    'apps/hosted_control_plane/migrations/0002_contract_hosted_v1.sql':
        'deployed database migration sequence and stored schema generation',
    'apps/hosted_control_plane/migrations/0003_expand_remote_v1.sql':
        'deployed database migration sequence and stored schema generation',
    'libs/experience_contracts/lib/src/lab/scenario_lab_relay_v2_rpc_contracts.dart':
        'negotiated relay wire generation',
    'libs/experience_contracts/test/scenario_lab_relay_v2_rpc_contracts_test.dart':
        'conformance coverage for the negotiated relay wire generation',
  };

  static const Map<String, List<String>> schemaOwnerSymbols =
      <String, List<String>>{
        'consumer-config': <String>['WorkspaceConfiguration'],
        'kit-composition': <String>['EffectiveKitManifest'],
        'evidence-release': <String>['EvidenceBundle', 'ReleasePointer'],
        'session-runtime': <String>['Session', 'Checkpoint'],
        'catalog-authoring-document': <String>['AuthoringDocument'],
        'experience-authoring-document': <String>['AuthoringDocument'],
        'source-automation': <String>['SourceSnapshot', 'SourceChangeSet'],
      };

  List<PolicyViolation> check() {
    final paths = _intendedPaths();
    final violations = <PolicyViolation>[];
    final packages = _packages(paths);
    final searchableText = StringBuffer();

    for (final path in paths) {
      _checkPath(path, violations);
      final file = File(p.join(root, path));
      if (!file.existsSync() || _isBinaryOrOversized(file)) continue;
      final source = file.readAsStringSync();
      searchableText
        ..write(source)
        ..write('\n');
      _checkTechnicalIdentity(path, source, violations);
      if (path.endsWith('.dart')) {
        _checkDartBoundaries(path, source, packages, violations);
      }
      if (path.endsWith('.md')) {
        _checkMarkdownLinks(path, source, violations);
      }
    }

    _checkSchemas(paths, searchableText.toString(), violations);
    return violations..sort();
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

  Map<String, _PackageRoot> _packages(List<String> paths) {
    final packages = <String, _PackageRoot>{};
    for (final path in paths.where(
      (path) => p.basename(path) == 'pubspec.yaml',
    )) {
      final source = File(p.join(root, path)).readAsStringSync();
      final match = RegExp(
        r'^name:\s*([a-zA-Z0-9_]+)\s*$',
        multiLine: true,
      ).firstMatch(source);
      if (match == null) continue;
      packages[match.group(1)!] = _PackageRoot(
        match.group(1)!,
        p.dirname(path) == '.' ? '' : p.dirname(path),
      );
    }
    return packages;
  }

  void _checkPath(String path, List<PolicyViolation> violations) {
    final segments = p.posix.split(path);
    if (segments.firstOrNull == 'packages' ||
        segments.firstOrNull == 'tool' ||
        segments.firstOrNull == 'test' ||
        path == 'docs/adr' ||
        path.startsWith('docs/adr/')) {
      violations.add(
        PolicyViolation('canonical-structure', path, 'uses a replaced root'),
      );
    }
    const generated = <String>{'.dart_tool', 'build', '.artifacts', '.idea'};
    final generatedSegment = segments.where(generated.contains).firstOrNull;
    if (generatedSegment != null) {
      violations.add(
        PolicyViolation(
          'tracked-generated',
          path,
          'tracks generated or local state in $generatedSegment',
        ),
      );
    }
    final technicalSegment = segments.where((segment) {
      final normalized = segment.toLowerCase();
      return RegExp(
        '(^|[-_.])($_retiredKitToken|$_retiredTechnicalToken|abel)'
        '([-_.]|$_endAnchor)',
      ).hasMatch(normalized);
    }).firstOrNull;
    if (technicalSegment != null) {
      violations.add(
        PolicyViolation(
          'technical-identity-path',
          path,
          'technical identity appears in $technicalSegment',
        ),
      );
    }
    final versioned = segments.any(
      (segment) => RegExp(
        r'(^|[-_.])(p0|v0(?:[._]?[1-3])?|v[1-5]|v0[1-3])([-_.]|$)',
        caseSensitive: false,
      ).hasMatch(segment),
    );
    if (versioned && !technicalVersionPaths.containsKey(path)) {
      violations.add(
        PolicyViolation(
          'phase-version-path',
          path,
          'uses a phase-like version instead of a semantic name',
        ),
      );
    }
    final legacyName = segments
        .where(
          (segment) => RegExp(
            r'(^|[-_.])(legacy|old|previous|deprecated|compatibility)([-_.]|$)',
            caseSensitive: false,
          ).hasMatch(segment),
        )
        .firstOrNull;
    if (legacyName != null) {
      violations.add(
        PolicyViolation('legacy-path', path, 'active path uses $legacyName'),
      );
    }
  }

  void _checkTechnicalIdentity(
    String path,
    String source,
    List<PolicyViolation> violations,
  ) {
    final retiredIdentity = RegExp(
      '\\b$_retiredTechnicalToken(?:kit)?\\b|'
      '\\b$_retiredTechnicalToken(?:kit)?[A-Z_.-]',
      caseSensitive: false,
    ).firstMatch(source);
    if (retiredIdentity != null) {
      violations.add(
        PolicyViolation(
          'technical-identity-text',
          path,
          'contains ${retiredIdentity.group(0)}',
        ),
      );
    }
    final retiredCssIdentity = RegExp(
      '(^|[^A-Za-z0-9])$_retiredCssToken[-_]',
      caseSensitive: false,
    ).firstMatch(source);
    if (retiredCssIdentity != null) {
      violations.add(
        PolicyViolation(
          'technical-identity-text',
          path,
          'contains retired abbreviated technical identity',
        ),
      );
    }
    final productPrefixMatch = RegExp(
      r'\b(?:abel[A-Z_][A-Za-z0-9_]*|abel[_-][A-Za-z0-9_-]+)\b',
    ).firstMatch(source);
    if (productPrefixMatch != null) {
      violations.add(
        PolicyViolation(
          'technical-product-prefix',
          path,
          'contains ${productPrefixMatch.group(0)}',
        ),
      );
    }
  }

  void _checkDartBoundaries(
    String path,
    String source,
    Map<String, _PackageRoot> packages,
    List<PolicyViolation> violations,
  ) {
    final current = _owningPackage(path, packages.values);
    if (current == null) return;
    final isProductionSource = _isProductionSource(path, current);
    final parsed = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    );
    final directives = parsed.unit.directives.whereType<UriBasedDirective>();
    for (final directive in directives) {
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      final packageMatch = RegExp(r'^package:([^/]+)/(.+)$').firstMatch(uri);
      if (packageMatch != null) {
        final dependency = packageMatch.group(1)!;
        final importedPath = packageMatch.group(2)!;
        if (importedPath.startsWith('src/') && dependency != current.name) {
          violations.add(
            PolicyViolation(
              'cross-package-private-import',
              path,
              'imports private library $uri',
            ),
          );
        }
        final target = packages[dependency];
        if (target != null && target.name != current.name) {
          final currentKind = current.root.split('/').firstOrNull;
          final targetKind = target.root.split('/').firstOrNull;
          if (currentKind == 'apps' && targetKind == 'apps') {
            violations.add(
              PolicyViolation(
                'app-depends-on-app',
                path,
                'imports $dependency from ${target.root}',
              ),
            );
          }
          if (currentKind == 'libs' && targetKind == 'apps') {
            violations.add(
              PolicyViolation(
                'library-depends-on-app',
                path,
                'imports $dependency from ${target.root}',
              ),
            );
          }
          if (currentKind == 'examples' && targetKind != 'libs') {
            violations.add(
              PolicyViolation(
                'example-non-library-dependency',
                path,
                'imports $dependency from ${target.root}',
              ),
            );
          }
        }
        continue;
      }
      if (uri.startsWith('dart:') || uri.startsWith('package:')) continue;
      final resolved = p.normalize(p.join(p.dirname(path), uri));
      if (isProductionSource &&
          (resolved == 'tools' || resolved.startsWith('tools/'))) {
        violations.add(
          PolicyViolation('runtime-depends-on-tools', path, 'imports $uri'),
        );
      }
      if (isProductionSource &&
          (resolved.contains('/test/') || resolved.startsWith('test/'))) {
        violations.add(
          PolicyViolation('production-depends-on-test', path, 'imports $uri'),
        );
      }
    }
  }

  void _checkSchemas(
    List<String> paths,
    String searchableText,
    List<PolicyViolation> violations,
  ) {
    for (final path in paths.where((path) => path.endsWith('.schema.json'))) {
      final basename = p.basename(path).replaceFirst('.schema.json', '');
      final symbols =
          schemaOwnerSymbols[basename] ?? <String>[_pascalCase(basename)];
      if (!symbols.any(searchableText.contains)) {
        violations.add(
          PolicyViolation(
            'schema-without-owner',
            path,
            'no producer or consumer symbol found (${symbols.join(', ')})',
          ),
        );
      }
    }
  }

  void _checkMarkdownLinks(
    String path,
    String source,
    List<PolicyViolation> violations,
  ) {
    var inFence = false;
    final links = <String>[];
    for (final line in const LineSplitter().convert(source)) {
      if (line.trimLeft().startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      for (final match in RegExp(r'!?\[[^\]]*\]\(([^)]+)\)').allMatches(line)) {
        var target = match.group(1)!.trim();
        if (target.startsWith('<') && target.endsWith('>')) {
          target = target.substring(1, target.length - 1);
        }
        final titleStart = RegExp(r'''\s+["']''').firstMatch(target)?.start;
        if (titleStart != null) target = target.substring(0, titleStart);
        links.add(target);
      }
    }
    for (final rawTarget in links) {
      if (rawTarget.isEmpty ||
          rawTarget.startsWith('#') ||
          rawTarget.startsWith('http://') ||
          rawTarget.startsWith('https://') ||
          rawTarget.startsWith('mailto:')) {
        continue;
      }
      final decoded = Uri.decodeComponent(rawTarget.split('#').first);
      final target = p.normalize(p.join(p.dirname(path), decoded));
      if (target == '..' || target.startsWith('../')) {
        violations.add(
          PolicyViolation(
            'markdown-link',
            path,
            'link escapes repository: $rawTarget',
          ),
        );
        continue;
      }
      if (!FileSystemEntity.isFileSync(p.join(root, target)) &&
          !FileSystemEntity.isDirectorySync(p.join(root, target))) {
        violations.add(
          PolicyViolation('markdown-link', path, 'missing target $rawTarget'),
        );
      }
    }
  }

  _PackageRoot? _owningPackage(String path, Iterable<_PackageRoot> packages) {
    final candidates =
        packages
            .where(
              (package) =>
                  package.root.isEmpty ||
                  path == package.root ||
                  path.startsWith('${package.root}/'),
            )
            .toList()
          ..sort((a, b) => b.root.length.compareTo(a.root.length));
    return candidates.firstOrNull;
  }

  static bool _isProductionSource(String path, _PackageRoot package) {
    if (package.root.isEmpty) return false;
    final relative = p.posix.relative(path, from: package.root);
    final first = p.posix.split(relative).firstOrNull;
    return first == 'lib' || first == 'bin' || first == 'tool';
  }

  bool _isBinaryOrOversized(File file) {
    if (file.lengthSync() > 4 * 1024 * 1024) return true;
    final bytes = file.openSync()..setPositionSync(0);
    try {
      return bytes.readSync(4096).contains(0);
    } finally {
      bytes.closeSync();
    }
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
    const ignoredFiles = <String>{
      '.flutter-plugins-dependencies',
      'examples/sample_flutter/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
      'examples/sample_flutter/android/local.properties',
    };
    return segments.any(ignored.contains) ||
        ignoredFiles.contains(path) ||
        ignoredFiles.contains(segments.lastOrNull);
  }

  static String _pascalCase(String value) => value
      .split('-')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join();
}

final class _PackageRoot {
  const _PackageRoot(this.name, this.root);

  final String name;
  final String root;
}

void main(List<String> arguments) {
  final root = arguments.isEmpty ? Directory.current.path : arguments.single;
  final violations = RepositoryPolicy(root: root).check();
  if (violations.isEmpty) return;
  stderr.writeln('Repository policy violations:');
  for (final violation in violations) {
    stderr.writeln('- $violation');
  }
  exitCode = 1;
}

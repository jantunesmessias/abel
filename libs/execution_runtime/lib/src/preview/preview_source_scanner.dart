import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

enum PreviewFactoryReturnKind { widget, widgetBuilder }

final class PreviewSourceScanException implements Exception {
  PreviewSourceScanException(Iterable<String> issues)
    : issues = List<String>.unmodifiable(issues);

  final List<String> issues;

  @override
  String toString() => issues.join('\n');
}

final class ScannedPreviewDeclaration {
  const ScannedPreviewDeclaration({
    required this.candidate,
    required this.returnKind,
  });

  final PreviewDeclarationCandidate candidate;
  final PreviewFactoryReturnKind returnKind;
}

final class PreviewSourceScanResult {
  PreviewSourceScanResult(Iterable<ScannedPreviewDeclaration> declarations)
    : declarations = List<ScannedPreviewDeclaration>.unmodifiable(
        declarations.toList(growable: false)..sort((left, right) {
          final source = left.candidate.sourceUri.compareTo(
            right.candidate.sourceUri,
          );
          if (source != 0) return source;
          final name = left.candidate.declarationName.compareTo(
            right.candidate.declarationName,
          );
          return name != 0
              ? name
              : left.candidate.id.compareTo(right.candidate.id);
        }),
      );

  final List<ScannedPreviewDeclaration> declarations;

  Iterable<PreviewDeclarationCandidate> get candidates =>
      declarations.map((value) => value.candidate);
}

final class PreviewFactoryValidator {
  const PreviewFactoryValidator();

  PreviewFactoryReturnKind? validate(
    FunctionDeclaration declaration,
    List<String> issues, {
    required String location,
  }) {
    final name = declaration.name.lexeme;
    if (name.startsWith('_')) {
      issues.add('$location: preview factory must be public');
    }
    if (declaration.isGetter || declaration.isSetter) {
      issues.add('$location: preview factory must be a function');
    }
    final element = declaration.declaredFragment?.element;
    if (element == null) {
      issues.add('$location: preview factory could not be resolved');
      return null;
    }
    if (element.formalParameters.isNotEmpty) {
      issues.add('$location: preview factory must not receive parameters');
    }
    final returnType = element.returnType;
    if (_isFlutterWidget(returnType)) return PreviewFactoryReturnKind.widget;
    if (_isFlutterWidgetBuilder(returnType)) {
      return PreviewFactoryReturnKind.widgetBuilder;
    }
    issues.add(
      '$location: preview factory must return Widget or WidgetBuilder, got '
      '${returnType.getDisplayString()}',
    );
    return null;
  }

  bool _isFlutterWidget(DartType type) {
    if (type is! InterfaceType) return false;
    return type.element.name == 'Widget' &&
        type.element.library.uri.toString() ==
            'package:flutter/src/widgets/framework.dart';
  }

  bool _isFlutterWidgetBuilder(DartType type) {
    final alias = type.alias?.element;
    return alias?.name == 'WidgetBuilder' &&
        alias?.library.uri.toString() ==
            'package:flutter/src/widgets/framework.dart';
  }
}

final class PreviewSourceScanner {
  const PreviewSourceScanner({
    this.factoryValidator = const PreviewFactoryValidator(),
    this.maxFiles = 20000,
  });

  static const String flutterCompatibility = '3.47.x';
  static const String _previewLibrary =
      'package:flutter_preview/src/auto_preview.dart';

  final PreviewFactoryValidator factoryValidator;
  final int maxFiles;

  Future<PreviewSourceScanResult> scan({
    required String applicationRoot,
  }) async {
    final root = Directory(p.normalize(p.absolute(applicationRoot)));
    if (!root.existsSync()) {
      throw FileSystemException('Application root does not exist', root.path);
    }
    final canonicalRoot = await root.resolveSymbolicLinks();
    final lib = Directory(p.join(canonicalRoot, 'lib'));
    if (!lib.existsSync()) {
      throw FileSystemException(
        'Application lib directory does not exist',
        lib.path,
      );
    }
    final canonicalLib = await lib.resolveSymbolicLinks();
    if (!p.isWithin(canonicalRoot, canonicalLib)) {
      throw FileSystemException(
        'Application lib escapes through a symlink',
        lib.path,
      );
    }

    final files = _dartFiles(Directory(canonicalLib));
    if (files.length > maxFiles) {
      throw FileSystemException(
        'Application exceeds the $maxFiles file preview scan limit',
        canonicalLib,
      );
    }
    final collection = AnalysisContextCollection(
      includedPaths: <String>[canonicalLib],
    );
    final issues = <String>[];
    final declarations = <ScannedPreviewDeclaration>[];
    try {
      for (final file in files) {
        final session = collection.contextFor(file).currentSession;
        final result = await session.getResolvedUnit(file);
        if (result is! ResolvedUnitResult) {
          issues.add('$file: Analyzer could not resolve the compilation unit');
          continue;
        }
        final sourceUri = result.libraryElement.uri.toString();
        for (final declaration
            in result.unit.declarations.whereType<FunctionDeclaration>()) {
          for (final annotation in declaration.metadata) {
            final annotationName = annotation.name.toSource().split('.').last;
            final looksLikePreview = const <String>{
              'AutoPreview',
              'AutoMultiPreview',
            }.contains(annotationName);
            final value = annotation.elementAnnotation?.computeConstantValue();
            final annotationType = _annotationType(value);
            if (annotationType == null) {
              if (looksLikePreview) {
                issues.add(
                  '$file#${declaration.name.lexeme}: AutoPreview annotation '
                  'must resolve to a compile-time constant',
                );
              }
              continue;
            }
            final (libraryUri, typeName) = annotationType;
            if (libraryUri != _previewLibrary ||
                !const <String>{
                  'AutoPreview',
                  'AutoMultiPreview',
                }.contains(typeName)) {
              continue;
            }

            final location = '$sourceUri#${declaration.name.lexeme}';
            final issueCount = issues.length;
            final returnKind = factoryValidator.validate(
              declaration,
              issues,
              location: location,
            );
            final candidate = _candidate(
              value!,
              typeName: typeName,
              sourceUri: sourceUri,
              declarationName: declaration.name.lexeme,
              location: location,
              issues: issues,
            );
            if (returnKind != null &&
                candidate != null &&
                issues.length == issueCount) {
              declarations.add(
                ScannedPreviewDeclaration(
                  candidate: candidate,
                  returnKind: returnKind,
                ),
              );
            }
          }
        }
      }
    } finally {
      await collection.dispose();
    }
    if (issues.isNotEmpty) throw PreviewSourceScanException(issues);
    return PreviewSourceScanResult(declarations);
  }

  List<String> _dartFiles(Directory lib) {
    final files = <String>[];
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw FileSystemException(
          'Links are forbidden in preview sources',
          entity.path,
        );
      }
      if (entity is File && p.extension(entity.path) == '.dart') {
        files.add(p.normalize(p.absolute(entity.path)));
      }
    }
    files.sort();
    return files;
  }

  (String, String)? _annotationType(DartObject? value) {
    final type = value?.type;
    if (type is! InterfaceType) return null;
    return (type.element.library.uri.toString(), type.element.name ?? '');
  }

  PreviewDeclarationCandidate? _candidate(
    DartObject value, {
    required String typeName,
    required String sourceUri,
    required String declarationName,
    required String location,
    required List<String> issues,
  }) {
    final id = _requiredString(value, 'id', location, issues);
    final scenarioId = _requiredString(value, 'scenarioId', location, issues);
    final capturePolicyId = _requiredString(
      value,
      'capturePolicyId',
      location,
      issues,
    );
    final fixtureRef = _optionalString(value, 'fixtureRef', location, issues);
    final variants = <PreviewVariantCandidate>[];
    if (typeName == 'AutoPreview') {
      final variant = _variant(value, location: location, issues: issues);
      if (variant != null) variants.add(variant);
    } else {
      final values = value.getField('variants')?.toListValue();
      if (values == null) {
        issues.add('$location: variants must be a const list');
      } else if (values.isEmpty) {
        issues.add('$location: AutoMultiPreview variants must not be empty');
      } else {
        for (var index = 0; index < values.length; index++) {
          final variant = _variant(
            values[index],
            location: '$location.variants[$index]',
            issues: issues,
          );
          if (variant != null) variants.add(variant);
        }
      }
    }
    if (id == null || scenarioId == null || capturePolicyId == null) {
      return null;
    }
    return PreviewDeclarationCandidate(
      id: id,
      scenarioId: scenarioId,
      sourceUri: sourceUri,
      declarationName: declarationName,
      capturePolicyId: capturePolicyId,
      fixtureRef: fixtureRef,
      variants: variants,
    );
  }

  PreviewVariantCandidate? _variant(
    DartObject value, {
    required String location,
    required List<String> issues,
  }) {
    final id = _requiredString(value, 'variantId', location, issues);
    final locale = _requiredString(value, 'localeTag', location, issues);
    final dpr = _requiredNumber(value, 'devicePixelRatio', location, issues);
    final textScale = _optionalNumber(value, 'textScaleFactor') ?? 1;
    final size = _field(value, 'size');
    final width = size == null
        ? null
        : _requiredSizeNumber(size, 'width', 0, location, issues);
    final height = size == null
        ? null
        : _requiredSizeNumber(size, 'height', 1, location, issues);
    if (size == null) issues.add('$location.size must be a const Size');
    final brightnessValue = _field(value, 'brightness');
    final brightnessName =
        brightnessValue?.variable?.name ??
        brightnessValue?.getField('_name')?.toStringValue() ??
        brightnessValue?.getField('name')?.toStringValue();
    final brightness = switch (brightnessName) {
      'light' => PreviewBrightness.light,
      'dark' => PreviewBrightness.dark,
      _ => null,
    };
    if (brightness == null) {
      issues.add('$location.brightness must be Brightness.light or dark');
    }
    if (id == null ||
        locale == null ||
        dpr == null ||
        width == null ||
        height == null ||
        brightness == null) {
      return null;
    }
    return PreviewVariantCandidate(
      id: id,
      logicalWidth: width,
      logicalHeight: height,
      devicePixelRatio: dpr,
      brightness: brightness,
      localeTag: locale,
      textScaleFactor: textScale,
    );
  }

  String? _requiredString(
    DartObject object,
    String field,
    String location,
    List<String> issues,
  ) {
    final value = _field(object, field)?.toStringValue();
    if (value == null || value.isEmpty) {
      issues.add('$location.$field must be a non-empty const String');
      return null;
    }
    return value;
  }

  String? _optionalString(
    DartObject object,
    String field,
    String location,
    List<String> issues,
  ) {
    final value = _field(object, field);
    if (value == null || value.isNull) return null;
    final string = value.toStringValue();
    if (string == null || string.isEmpty) {
      issues.add('$location.$field must be null or a non-empty const String');
      return null;
    }
    return string;
  }

  double? _requiredNumber(
    DartObject object,
    String field,
    String location,
    List<String> issues,
  ) {
    final value = _field(object, field);
    final number = value?.toDoubleValue() ?? value?.toIntValue()?.toDouble();
    if (number == null || !number.isFinite) {
      issues.add('$location.$field must be a finite const number');
      return null;
    }
    return number;
  }

  double? _optionalNumber(DartObject object, String field) {
    final value = _field(object, field);
    return value?.toDoubleValue() ?? value?.toIntValue()?.toDouble();
  }

  double? _requiredSizeNumber(
    DartObject size,
    String field,
    int positionalIndex,
    String location,
    List<String> issues,
  ) {
    final positional = size.constructorInvocation?.positionalArguments;
    final value =
        _field(size, field) ??
        (positional != null && positional.length > positionalIndex
            ? positional[positionalIndex]
            : null);
    final number = value?.toDoubleValue() ?? value?.toIntValue()?.toDouble();
    if (number == null || !number.isFinite) {
      issues.add('$location.$field must be a finite const number');
      return null;
    }
    return number;
  }

  DartObject? _field(DartObject object, String field) =>
      object.getField(field) ??
      object.constructorInvocation?.namedArguments[field];
}

final class EphemeralPreviewRegistry {
  const EphemeralPreviewRegistry({
    required this.directory,
    required this.registryPath,
    required this.manifestPath,
  });

  final String directory;
  final String registryPath;
  final String manifestPath;
}

final class EphemeralPreviewRegistryWriter {
  const EphemeralPreviewRegistryWriter();

  Future<EphemeralPreviewRegistry> write({
    required String applicationRoot,
    required Digest planDigest,
    required PreviewManifest manifest,
    required PreviewSourceScanResult scan,
  }) async {
    final root = await Directory(
      p.normalize(p.absolute(applicationRoot)),
    ).resolveSymbolicLinks();
    final toolRoot = p.join(root, '.dart_tool');
    _rejectLink(toolRoot);
    final safeDigest = planDigest.value.replaceFirst(':', '-');
    final output = p.join(toolRoot, 'workspace', 'preview', safeDigest);
    if (!p.isWithin(root, output)) {
      throw FileSystemException(
        'Preview output escapes application root',
        output,
      );
    }
    _rejectExistingAncestorLinks(root, output);
    await Directory(output).create(recursive: true);

    final declarations = <String, ScannedPreviewDeclaration>{};
    for (final declaration in scan.declarations) {
      final candidate = declaration.candidate;
      declarations[_declarationKey(
            candidate.sourceUri,
            candidate.declarationName,
            candidate.id,
          )] =
          declaration;
    }
    for (final descriptor in manifest.descriptors) {
      final declaration =
          declarations[_declarationKey(
            descriptor.sourceUri,
            descriptor.declarationName,
            descriptor.id.value,
          )];
      if (declaration == null ||
          !declaration.candidate.variants.any(
            (variant) => variant.id == descriptor.variant.id.value,
          )) {
        throw StateError(
          'Manifest descriptor ${descriptor.key} has no scanned factory',
        );
      }
    }

    final registryPath = p.join(output, 'preview_registry.g.dart');
    final manifestPath = p.join(output, 'preview_manifest.json');
    await _atomicWrite(registryPath, _registrySource(manifest, declarations));
    await _atomicWrite(
      manifestPath,
      '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
    );
    return EphemeralPreviewRegistry(
      directory: output,
      registryPath: registryPath,
      manifestPath: manifestPath,
    );
  }

  String _registrySource(
    PreviewManifest manifest,
    Map<String, ScannedPreviewDeclaration> declarations,
  ) {
    final uris =
        manifest.descriptors.map((value) => value.sourceUri).toSet().toList()
          ..sort();
    final aliases = <String, String>{
      for (var index = 0; index < uris.length; index++)
        uris[index]: 'source$index',
    };
    final buffer = StringBuffer()
      ..writeln('// GENERATED FILE, DO NOT MODIFY')
      ..writeln("import 'package:flutter/widgets.dart';");
    for (final uri in uris) {
      buffer.writeln("import '$uri' as ${aliases[uri]};");
    }
    buffer
      ..writeln()
      ..writeln('typedef PreviewFactory = Widget Function(BuildContext);')
      ..writeln()
      ..writeln('final Map<String, PreviewFactory> previewFactories =')
      ..writeln('    <String, PreviewFactory>{');
    for (final descriptor in manifest.descriptors) {
      final declaration =
          declarations[_declarationKey(
            descriptor.sourceUri,
            descriptor.declarationName,
            descriptor.id.value,
          )]!;
      final invocation =
          '${aliases[descriptor.sourceUri]}.${descriptor.declarationName}()';
      final expression =
          declaration.returnKind == PreviewFactoryReturnKind.widget
          ? invocation
          : '$invocation(context)';
      buffer.writeln(
        '  ${jsonEncode(descriptor.key)}: (BuildContext context) => $expression,',
      );
    }
    buffer.writeln('};');
    return buffer.toString();
  }

  String _declarationKey(String uri, String name, String id) =>
      '$uri#$name#$id';

  void _rejectLink(String path) {
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('Preview output path contains a link', path);
    }
  }

  void _rejectExistingAncestorLinks(String root, String target) {
    var current = root;
    for (final segment in p.relative(target, from: root).split(p.separator)) {
      current = p.join(current, segment);
      _rejectLink(current);
    }
  }

  Future<void> _atomicWrite(String path, String contents) async {
    final temporary = File('$path.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(path);
  }
}

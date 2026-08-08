import '../catalog/catalog_contracts.dart';
import '../digest.dart';

enum PreviewBrightness { light, dark }

enum PreviewCaptureStatus {
  collected,
  invalid,
  failed,
  unsupported,
  policyDenied,
}

enum PreviewDiagnosticSeverity { info, warning, error }

final class VariantId extends OpaqueId {
  factory VariantId(String value) {
    OpaqueId.validate(value, 'Variant');
    return VariantId._(value);
  }

  const VariantId._(super.value);
}

final class AutoPreviewId extends OpaqueId {
  factory AutoPreviewId(String value) {
    OpaqueId.validate(value, 'AutoPreview');
    return AutoPreviewId._(value);
  }

  const AutoPreviewId._(super.value);
}

final class Variant {
  Variant({
    required this.id,
    required this.applicationId,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
    required this.brightness,
    required this.localeTag,
    this.textScaleFactor = 1,
    this.themeId,
  }) {
    for (final dimension in <double>[logicalWidth, logicalHeight]) {
      if (!dimension.isFinite || dimension <= 0 || dimension > 10000) {
        throw ArgumentError('Variant viewport dimensions are invalid');
      }
    }
    if (!devicePixelRatio.isFinite ||
        devicePixelRatio <= 0 ||
        devicePixelRatio > 8) {
      throw ArgumentError.value(devicePixelRatio, 'devicePixelRatio');
    }
    if (!textScaleFactor.isFinite ||
        textScaleFactor < 0.5 ||
        textScaleFactor > 4) {
      throw ArgumentError.value(textScaleFactor, 'textScaleFactor');
    }
    if (!RegExp(r'^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$').hasMatch(localeTag)) {
      throw FormatException('Invalid Variant localeTag: $localeTag');
    }
    if (themeId != null) OpaqueId.validate(themeId!, 'Theme');
  }

  static const int schemaVersion = 1;
  final VariantId id;
  final ApplicationId applicationId;
  final double logicalWidth;
  final double logicalHeight;
  final double devicePixelRatio;
  final PreviewBrightness brightness;
  final String localeTag;
  final double textScaleFactor;
  final String? themeId;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'Variant',
    'id': id.value,
    'applicationId': applicationId.value,
    'logicalWidth': logicalWidth,
    'logicalHeight': logicalHeight,
    'devicePixelRatio': devicePixelRatio,
    'brightness': brightness.name,
    'localeTag': localeTag,
    'textScaleFactor': textScaleFactor,
    if (themeId != null) 'themeId': themeId,
    if (includeDigest) 'digest': digest.value,
  };

  factory Variant.fromJson(Object? value) {
    final json = _document(value, 'Variant', const <String>{
      'id',
      'applicationId',
      'logicalWidth',
      'logicalHeight',
      'devicePixelRatio',
      'brightness',
      'localeTag',
      'textScaleFactor',
      'themeId',
    });
    final variant = Variant(
      id: VariantId(_string(json, 'id', 'Variant')),
      applicationId: ApplicationId(_string(json, 'applicationId', 'Variant')),
      logicalWidth: _number(json, 'logicalWidth', 'Variant'),
      logicalHeight: _number(json, 'logicalHeight', 'Variant'),
      devicePixelRatio: _number(json, 'devicePixelRatio', 'Variant'),
      brightness: _enumValue(
        PreviewBrightness.values,
        _string(json, 'brightness', 'Variant'),
        'Variant.brightness',
      ),
      localeTag: _string(json, 'localeTag', 'Variant'),
      textScaleFactor: _number(json, 'textScaleFactor', 'Variant'),
      themeId: _optionalString(json, 'themeId', 'Variant'),
    );
    _verifyDigest(json, variant.digest, 'Variant');
    return variant;
  }
}

final class PreviewDescriptor {
  PreviewDescriptor({
    required this.id,
    required this.scenarioId,
    required this.variant,
    required this.sourceUri,
    required this.declarationName,
    required this.capturePolicyId,
    this.fixtureRef,
  }) {
    final uri = Uri.tryParse(sourceUri);
    if (uri == null ||
        !uri.hasScheme ||
        !const <String>{'package', 'file'}.contains(uri.scheme)) {
      throw FormatException('PreviewDescriptor sourceUri is invalid');
    }
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(declarationName) ||
        declarationName.startsWith('_')) {
      throw FormatException('Preview declaration must be public top-level');
    }
    OpaqueId.validate(capturePolicyId, 'CapturePolicy');
    if (fixtureRef != null) OpaqueId.validate(fixtureRef!, 'Fixture');
  }

  static const int schemaVersion = 1;
  final AutoPreviewId id;
  final ScenarioId scenarioId;
  final Variant variant;
  final String sourceUri;
  final String declarationName;
  final String capturePolicyId;
  final String? fixtureRef;

  String get key => '${id.value}:${variant.id.value}';
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'PreviewDescriptor',
    'id': id.value,
    'scenarioId': scenarioId.value,
    'variant': variant.toJson(),
    'sourceUri': sourceUri,
    'declarationName': declarationName,
    'capturePolicyId': capturePolicyId,
    if (fixtureRef != null) 'fixtureRef': fixtureRef,
    if (includeDigest) 'digest': digest.value,
  };

  factory PreviewDescriptor.fromJson(Object? value) {
    final json = _document(value, 'PreviewDescriptor', const <String>{
      'id',
      'scenarioId',
      'variant',
      'sourceUri',
      'declarationName',
      'capturePolicyId',
      'fixtureRef',
    });
    final descriptor = PreviewDescriptor(
      id: AutoPreviewId(_string(json, 'id', 'PreviewDescriptor')),
      scenarioId: ScenarioId(_string(json, 'scenarioId', 'PreviewDescriptor')),
      variant: Variant.fromJson(json['variant']),
      sourceUri: _string(json, 'sourceUri', 'PreviewDescriptor'),
      declarationName: _string(json, 'declarationName', 'PreviewDescriptor'),
      capturePolicyId: _string(json, 'capturePolicyId', 'PreviewDescriptor'),
      fixtureRef: _optionalString(json, 'fixtureRef', 'PreviewDescriptor'),
    );
    _verifyDigest(json, descriptor.digest, 'PreviewDescriptor');
    return descriptor;
  }
}

final class PreviewManifest {
  PreviewManifest({
    required this.catalogDigest,
    required this.flutterCompatibility,
    required List<PreviewDescriptor> descriptors,
  }) : descriptors = List<PreviewDescriptor>.unmodifiable(
         List<PreviewDescriptor>.of(descriptors)
           ..sort((left, right) => left.key.compareTo(right.key)),
       ) {
    if (this.descriptors.isEmpty ||
        _duplicates(this.descriptors.map((e) => e.key))) {
      throw ArgumentError(
        'PreviewManifest descriptors must be non-empty and unique',
      );
    }
    if (!RegExp(r'^[0-9]+\.[0-9]+\.x$').hasMatch(flutterCompatibility)) {
      throw FormatException('Invalid Flutter compatibility marker');
    }
    final variants = <VariantId, Digest>{};
    final previewScenarios = <AutoPreviewId, ScenarioId>{};
    for (final descriptor in this.descriptors) {
      final existingVariant = variants[descriptor.variant.id];
      if (existingVariant != null &&
          existingVariant != descriptor.variant.digest) {
        throw ArgumentError(
          'Variant ${descriptor.variant.id.value} has divergent definitions',
        );
      }
      variants[descriptor.variant.id] = descriptor.variant.digest;
      final existingScenario = previewScenarios[descriptor.id];
      if (existingScenario != null &&
          existingScenario != descriptor.scenarioId) {
        throw ArgumentError(
          'AutoPreview ${descriptor.id.value} spans multiple Scenarios',
        );
      }
      previewScenarios[descriptor.id] = descriptor.scenarioId;
    }
  }

  static const int schemaVersion = 1;
  final Digest catalogDigest;
  final String flutterCompatibility;
  final List<PreviewDescriptor> descriptors;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'PreviewManifest',
    'catalogDigest': catalogDigest.value,
    'flutterCompatibility': flutterCompatibility,
    'descriptors': <Object?>[
      for (final descriptor in descriptors) descriptor.toJson(),
    ],
    if (includeDigest) 'digest': digest.value,
  };

  factory PreviewManifest.fromJson(Object? value) {
    final json = _document(value, 'PreviewManifest', const <String>{
      'catalogDigest',
      'flutterCompatibility',
      'descriptors',
    });
    final manifest = PreviewManifest(
      catalogDigest: Digest(_string(json, 'catalogDigest', 'PreviewManifest')),
      flutterCompatibility: _string(
        json,
        'flutterCompatibility',
        'PreviewManifest',
      ),
      descriptors: _list(
        json,
        'descriptors',
        'PreviewManifest',
      ).map(PreviewDescriptor.fromJson).toList(growable: false),
    );
    _verifyDigest(json, manifest.digest, 'PreviewManifest');
    return manifest;
  }
}

final class PreviewCaptureDiagnostic {
  PreviewCaptureDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
  }) {
    OpaqueId.validate(code, 'PreviewDiagnostic');
    if (message.isEmpty || message.length > 2048) {
      throw ArgumentError.value(message, 'message');
    }
  }

  final String code;
  final PreviewDiagnosticSeverity severity;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'severity': severity.name,
    'message': message,
  };

  factory PreviewCaptureDiagnostic.fromJson(Object? value) {
    final json = _object(value, 'PreviewCaptureDiagnostic');
    _only(json, const <String>{
      'code',
      'severity',
      'message',
    }, 'PreviewCaptureDiagnostic');
    return PreviewCaptureDiagnostic(
      code: _string(json, 'code', 'PreviewCaptureDiagnostic'),
      severity: _enumValue(
        PreviewDiagnosticSeverity.values,
        _string(json, 'severity', 'PreviewCaptureDiagnostic'),
        'PreviewCaptureDiagnostic.severity',
      ),
      message: _string(json, 'message', 'PreviewCaptureDiagnostic'),
    );
  }
}

final class PreviewCaptureItem {
  PreviewCaptureItem({
    required this.previewId,
    required this.scenarioId,
    required this.variantId,
    required this.descriptorDigest,
    required this.captureKey,
    required this.status,
    this.artifactDigest,
    this.pixelDigest,
    this.pixelWidth,
    this.pixelHeight,
    List<PreviewCaptureDiagnostic> diagnostics =
        const <PreviewCaptureDiagnostic>[],
  }) : diagnostics = List<PreviewCaptureDiagnostic>.unmodifiable(diagnostics) {
    final collected = status == PreviewCaptureStatus.collected;
    final completeArtifact =
        artifactDigest != null &&
        pixelDigest != null &&
        pixelWidth != null &&
        pixelHeight != null &&
        pixelWidth! > 0 &&
        pixelHeight! > 0;
    if (collected != completeArtifact) {
      throw ArgumentError(
        'Only collected PreviewCaptureItem may contain a complete artifact',
      );
    }
    if (!collected &&
        (artifactDigest != null ||
            pixelDigest != null ||
            pixelWidth != null ||
            pixelHeight != null)) {
      throw ArgumentError('Failed capture item cannot contain artifact fields');
    }
  }

  final AutoPreviewId previewId;
  final ScenarioId scenarioId;
  final VariantId variantId;
  final Digest descriptorDigest;
  final Digest captureKey;
  final PreviewCaptureStatus status;
  final Digest? artifactDigest;
  final Digest? pixelDigest;
  final int? pixelWidth;
  final int? pixelHeight;
  final List<PreviewCaptureDiagnostic> diagnostics;

  String get key => '${previewId.value}:${variantId.value}';

  Map<String, Object?> toJson() => <String, Object?>{
    'previewId': previewId.value,
    'scenarioId': scenarioId.value,
    'variantId': variantId.value,
    'descriptorDigest': descriptorDigest.value,
    'captureKey': captureKey.value,
    'status': status.name,
    if (artifactDigest != null) 'artifactDigest': artifactDigest!.value,
    if (pixelDigest != null) 'pixelDigest': pixelDigest!.value,
    if (pixelWidth != null) 'pixelWidth': pixelWidth,
    if (pixelHeight != null) 'pixelHeight': pixelHeight,
    'diagnostics': <Object?>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
  };

  factory PreviewCaptureItem.fromJson(Object? value) {
    final json = _object(value, 'PreviewCaptureItem');
    _only(json, const <String>{
      'previewId',
      'scenarioId',
      'variantId',
      'descriptorDigest',
      'captureKey',
      'status',
      'artifactDigest',
      'pixelDigest',
      'pixelWidth',
      'pixelHeight',
      'diagnostics',
    }, 'PreviewCaptureItem');
    final artifact = _optionalString(
      json,
      'artifactDigest',
      'PreviewCaptureItem',
    );
    final pixel = _optionalString(json, 'pixelDigest', 'PreviewCaptureItem');
    return PreviewCaptureItem(
      previewId: AutoPreviewId(
        _string(json, 'previewId', 'PreviewCaptureItem'),
      ),
      scenarioId: ScenarioId(_string(json, 'scenarioId', 'PreviewCaptureItem')),
      variantId: VariantId(_string(json, 'variantId', 'PreviewCaptureItem')),
      descriptorDigest: Digest(
        _string(json, 'descriptorDigest', 'PreviewCaptureItem'),
      ),
      captureKey: Digest(_string(json, 'captureKey', 'PreviewCaptureItem')),
      status: _enumValue(
        PreviewCaptureStatus.values,
        _string(json, 'status', 'PreviewCaptureItem'),
        'PreviewCaptureItem.status',
      ),
      artifactDigest: artifact == null ? null : Digest(artifact),
      pixelDigest: pixel == null ? null : Digest(pixel),
      pixelWidth: _optionalInteger(json, 'pixelWidth', 'PreviewCaptureItem'),
      pixelHeight: _optionalInteger(json, 'pixelHeight', 'PreviewCaptureItem'),
      diagnostics: _list(
        json,
        'diagnostics',
        'PreviewCaptureItem',
      ).map(PreviewCaptureDiagnostic.fromJson).toList(growable: false),
    );
  }
}

final class PreviewCaptureManifest {
  PreviewCaptureManifest({
    required this.previewManifestDigest,
    required this.renderer,
    required this.toolchainDigest,
    required this.executionFingerprintDigest,
    required List<PreviewCaptureItem> items,
  }) : items = List<PreviewCaptureItem>.unmodifiable(
         List<PreviewCaptureItem>.of(items)
           ..sort((left, right) => left.key.compareTo(right.key)),
       ) {
    OpaqueId.validate(renderer, 'PreviewRenderer');
    if (_duplicates(this.items.map((item) => item.key))) {
      throw ArgumentError('PreviewCaptureManifest items must be unique');
    }
  }

  static const int schemaVersion = 1;
  final Digest previewManifestDigest;
  final String renderer;
  final Digest toolchainDigest;
  final Digest executionFingerprintDigest;
  final List<PreviewCaptureItem> items;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'PreviewCaptureManifest',
    'previewManifestDigest': previewManifestDigest.value,
    'renderer': renderer,
    'toolchainDigest': toolchainDigest.value,
    'executionFingerprintDigest': executionFingerprintDigest.value,
    'items': <Object?>[for (final item in items) item.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  factory PreviewCaptureManifest.fromJson(Object? value) {
    final json = _document(value, 'PreviewCaptureManifest', const <String>{
      'previewManifestDigest',
      'renderer',
      'toolchainDigest',
      'executionFingerprintDigest',
      'items',
    });
    final manifest = PreviewCaptureManifest(
      previewManifestDigest: Digest(
        _string(json, 'previewManifestDigest', 'PreviewCaptureManifest'),
      ),
      renderer: _string(json, 'renderer', 'PreviewCaptureManifest'),
      toolchainDigest: Digest(
        _string(json, 'toolchainDigest', 'PreviewCaptureManifest'),
      ),
      executionFingerprintDigest: Digest(
        _string(json, 'executionFingerprintDigest', 'PreviewCaptureManifest'),
      ),
      items: _list(
        json,
        'items',
        'PreviewCaptureManifest',
      ).map(PreviewCaptureItem.fromJson).toList(growable: false),
    );
    _verifyDigest(json, manifest.digest, 'PreviewCaptureManifest');
    return manifest;
  }
}

final class PreviewCaptureReport {
  PreviewCaptureReport({
    required this.captureManifestDigest,
    required DateTime startedAt,
    required DateTime completedAt,
    required this.totalItems,
    required this.collectedItems,
    required this.failedItems,
    List<PreviewCaptureDiagnostic> diagnostics =
        const <PreviewCaptureDiagnostic>[],
  }) : startedAt = startedAt.toUtc(),
       completedAt = completedAt.toUtc(),
       diagnostics = List<PreviewCaptureDiagnostic>.unmodifiable(diagnostics) {
    if (this.completedAt.isBefore(this.startedAt) ||
        totalItems < 0 ||
        collectedItems < 0 ||
        failedItems < 0 ||
        collectedItems + failedItems != totalItems) {
      throw ArgumentError(
        'PreviewCaptureReport counts or timestamps are invalid',
      );
    }
  }

  static const int schemaVersion = 1;
  final Digest captureManifestDigest;
  final DateTime startedAt;
  final DateTime completedAt;
  final int totalItems;
  final int collectedItems;
  final int failedItems;
  final List<PreviewCaptureDiagnostic> diagnostics;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'PreviewCaptureReport',
    'captureManifestDigest': captureManifestDigest.value,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'totalItems': totalItems,
    'collectedItems': collectedItems,
    'failedItems': failedItems,
    'diagnostics': <Object?>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
    if (includeDigest) 'digest': digest.value,
  };

  factory PreviewCaptureReport.fromJson(Object? value) {
    final json = _document(value, 'PreviewCaptureReport', const <String>{
      'captureManifestDigest',
      'startedAt',
      'completedAt',
      'totalItems',
      'collectedItems',
      'failedItems',
      'diagnostics',
    });
    final report = PreviewCaptureReport(
      captureManifestDigest: Digest(
        _string(json, 'captureManifestDigest', 'PreviewCaptureReport'),
      ),
      startedAt: _dateTime(json, 'startedAt', 'PreviewCaptureReport'),
      completedAt: _dateTime(json, 'completedAt', 'PreviewCaptureReport'),
      totalItems: _integer(json, 'totalItems', 'PreviewCaptureReport'),
      collectedItems: _integer(json, 'collectedItems', 'PreviewCaptureReport'),
      failedItems: _integer(json, 'failedItems', 'PreviewCaptureReport'),
      diagnostics: _list(
        json,
        'diagnostics',
        'PreviewCaptureReport',
      ).map(PreviewCaptureDiagnostic.fromJson).toList(growable: false),
    );
    _verifyDigest(json, report.digest, 'PreviewCaptureReport');
    return report;
  }
}

Map<String, Object?> _document(Object? value, String kind, Set<String> fields) {
  final json = _object(value, kind);
  _only(json, <String>{'schemaVersion', 'kind', ...fields, 'digest'}, kind);
  if (json['schemaVersion'] != 1 || json['kind'] != kind) {
    throw FormatException('$kind has invalid schemaVersion or kind');
  }
  return json;
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path unknown field $key');
    }
  }
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

double _number(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! num) throw FormatException('$path.$key must be a number');
  return value.toDouble();
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

int? _optionalInteger(Map<String, Object?> json, String key, String path) {
  if (json[key] == null) return null;
  return _integer(json, key, path);
}

List<Object?> _list(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$path.$key must be a list');
  }
  return value;
}

DateTime _dateTime(Map<String, Object?> json, String key, String path) {
  final source = _string(json, key, path);
  final value = DateTime.tryParse(source);
  if (value == null || !value.isUtc || value.toIso8601String() != source) {
    throw FormatException('$path.$key must be canonical UTC time');
  }
  return value;
}

T _enumValue<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has unsupported value $name');
}

bool _duplicates(Iterable<Object> values) {
  final seen = <Object>{};
  return values.any((value) => !seen.add(value));
}

void _verifyDigest(Map<String, Object?> json, Digest digest, String path) {
  final encoded = _string(json, 'digest', path);
  if (encoded != digest.value) throw FormatException('$path digest mismatch');
}

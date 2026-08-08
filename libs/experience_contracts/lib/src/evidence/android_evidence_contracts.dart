import '../digest.dart';

enum AndroidEvidenceStatus { collected, unavailable, failed, policyDenied }

final class AndroidDeviceEnvironment {
  AndroidDeviceEnvironment({
    required this.imageDescriptor,
    required this.imageDigest,
    required this.apiLevel,
    required this.abi,
    required this.renderer,
    required this.locale,
    required this.timezone,
    required Map<String, String> toolchain,
  }) : toolchain = Map<String, String>.unmodifiable(
         Map<String, String>.fromEntries(
           toolchain.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
         ),
       ) {
    for (final value in <String>[imageDescriptor, renderer, locale, timezone]) {
      if (value.isEmpty || value.length > 512 || value.contains('\u0000')) {
        throw const FormatException(
          'Android device environment contains an invalid value',
        );
      }
    }
    if (apiLevel < 21 ||
        apiLevel > 999 ||
        !RegExp(r'^[a-z0-9_]{2,32}$').hasMatch(abi)) {
      throw const FormatException('Android device API or ABI is invalid');
    }
    if (this.toolchain.isEmpty ||
        this.toolchain.entries.any(
          (entry) =>
              entry.key.isEmpty ||
              entry.value.isEmpty ||
              entry.key.length > 128 ||
              entry.value.length > 512,
        )) {
      throw const FormatException('Android device toolchain is invalid');
    }
  }

  final String imageDescriptor;
  final Digest imageDigest;
  final int apiLevel;
  final String abi;
  final String renderer;
  final String locale;
  final String timezone;
  final Map<String, String> toolchain;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'imageDescriptor': imageDescriptor,
    'imageDigest': imageDigest.value,
    'apiLevel': apiLevel,
    'abi': abi,
    'renderer': renderer,
    'locale': locale,
    'timezone': timezone,
    'toolchain': toolchain,
  };

  factory AndroidDeviceEnvironment.fromJson(Object? value) {
    final json = _androidEvidenceObject(value, 'AndroidDeviceEnvironment');
    _androidEvidenceOnly(json, const <String>{
      'imageDescriptor',
      'imageDigest',
      'apiLevel',
      'abi',
      'renderer',
      'locale',
      'timezone',
      'toolchain',
    }, 'AndroidDeviceEnvironment');
    return AndroidDeviceEnvironment(
      imageDescriptor: _androidEvidenceString(
        json,
        'imageDescriptor',
        'AndroidDeviceEnvironment',
      ),
      imageDigest: Digest(
        _androidEvidenceString(json, 'imageDigest', 'AndroidDeviceEnvironment'),
      ),
      apiLevel: _androidEvidenceInt(
        json,
        'apiLevel',
        'AndroidDeviceEnvironment',
      ),
      abi: _androidEvidenceString(json, 'abi', 'AndroidDeviceEnvironment'),
      renderer: _androidEvidenceString(
        json,
        'renderer',
        'AndroidDeviceEnvironment',
      ),
      locale: _androidEvidenceString(
        json,
        'locale',
        'AndroidDeviceEnvironment',
      ),
      timezone: _androidEvidenceString(
        json,
        'timezone',
        'AndroidDeviceEnvironment',
      ),
      toolchain: _androidEvidenceStringMap(
        json['toolchain'],
        'AndroidDeviceEnvironment.toolchain',
      ),
    );
  }
}

final class AndroidEvidenceObservation {
  AndroidEvidenceObservation({
    required this.role,
    required this.status,
    required this.detailCode,
    this.artifactDigest,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9.-]{1,127}$').hasMatch(role) ||
        !RegExp(r'^[a-z][a-z0-9_.-]{1,127}$').hasMatch(detailCode)) {
      throw const FormatException(
        'Android evidence observation identifiers are invalid',
      );
    }
    if ((status == AndroidEvidenceStatus.collected) !=
        (artifactDigest != null)) {
      throw ArgumentError(
        'Only a collected observation has an artifact digest',
      );
    }
  }

  final String role;
  final AndroidEvidenceStatus status;
  final String detailCode;
  final Digest? artifactDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'status': status.name,
    'detailCode': detailCode,
    if (artifactDigest != null) 'artifactDigest': artifactDigest!.value,
  };

  factory AndroidEvidenceObservation.fromJson(Object? value) {
    final json = _androidEvidenceObject(value, 'AndroidEvidenceObservation');
    _androidEvidenceOnly(json, const <String>{
      'role',
      'status',
      'detailCode',
      'artifactDigest',
    }, 'AndroidEvidenceObservation');
    final statusName = _androidEvidenceString(
      json,
      'status',
      'AndroidEvidenceObservation',
    );
    final status = AndroidEvidenceStatus.values
        .where((item) => item.name == statusName)
        .firstOrNull;
    if (status == null) {
      throw FormatException(
        'Invalid AndroidEvidenceObservation.status: $statusName',
      );
    }
    return AndroidEvidenceObservation(
      role: _androidEvidenceString(json, 'role', 'AndroidEvidenceObservation'),
      status: status,
      detailCode: _androidEvidenceString(
        json,
        'detailCode',
        'AndroidEvidenceObservation',
      ),
      artifactDigest: json['artifactDigest'] == null
          ? null
          : Digest(
              _androidEvidenceString(
                json,
                'artifactDigest',
                'AndroidEvidenceObservation',
              ),
            ),
    );
  }
}

final class AndroidEvidenceManifest {
  AndroidEvidenceManifest({
    required this.correlationId,
    required this.targetId,
    required this.environment,
    required this.containmentReportDigest,
    required this.collectedAt,
    required this.syntheticDataConfirmed,
    required List<AndroidEvidenceObservation> observations,
  }) : observations = List<AndroidEvidenceObservation>.unmodifiable(
         List<AndroidEvidenceObservation>.of(observations)
           ..sort((a, b) => a.role.compareTo(b.role)),
       ) {
    if (!RegExp(r'^[a-zA-Z0-9._-]{8,128}$').hasMatch(correlationId) ||
        targetId.isEmpty) {
      throw const FormatException(
        'Android evidence correlation or target ID is invalid',
      );
    }
    if (!collectedAt.isUtc) {
      throw ArgumentError('Android evidence collectedAt must be UTC');
    }
    if (this.observations.isEmpty ||
        this.observations.map((item) => item.role).toSet().length !=
            this.observations.length) {
      throw ArgumentError(
        'Android evidence observations must be non-empty and unique',
      );
    }
  }

  static const int schemaVersion = 1;
  final String correlationId;
  final String targetId;
  final AndroidDeviceEnvironment environment;
  final Digest containmentReportDigest;
  final DateTime collectedAt;
  final bool syntheticDataConfirmed;
  final List<AndroidEvidenceObservation> observations;
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AndroidEvidenceManifest',
    'correlationId': correlationId,
    'targetId': targetId,
    'runtimeFidelity': 'hostNative',
    'environment': environment.toJson(),
    'containmentReportDigest': containmentReportDigest.value,
    'collectedAt': collectedAt.toIso8601String(),
    'syntheticDataConfirmed': syntheticDataConfirmed,
    'observations': <Object?>[
      for (final observation in observations) observation.toJson(),
    ],
    if (includeDigest) 'digest': digest.value,
  };

  factory AndroidEvidenceManifest.fromJson(Object? value) {
    final json = _androidEvidenceObject(value, 'AndroidEvidenceManifest');
    _androidEvidenceOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'correlationId',
      'targetId',
      'runtimeFidelity',
      'environment',
      'containmentReportDigest',
      'collectedAt',
      'syntheticDataConfirmed',
      'observations',
      'digest',
    }, 'AndroidEvidenceManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'AndroidEvidenceManifest' ||
        json['runtimeFidelity'] != 'hostNative') {
      throw const FormatException(
        'Invalid AndroidEvidenceManifest version, kind, or fidelity',
      );
    }
    final values = json['observations'];
    if (values is! List<Object?>) {
      throw const FormatException(
        'AndroidEvidenceManifest.observations must be an array',
      );
    }
    final manifest = AndroidEvidenceManifest(
      correlationId: _androidEvidenceString(
        json,
        'correlationId',
        'AndroidEvidenceManifest',
      ),
      targetId: _androidEvidenceString(
        json,
        'targetId',
        'AndroidEvidenceManifest',
      ),
      environment: AndroidDeviceEnvironment.fromJson(json['environment']),
      containmentReportDigest: Digest(
        _androidEvidenceString(
          json,
          'containmentReportDigest',
          'AndroidEvidenceManifest',
        ),
      ),
      collectedAt: DateTime.parse(
        _androidEvidenceString(json, 'collectedAt', 'AndroidEvidenceManifest'),
      ),
      syntheticDataConfirmed: _androidEvidenceBool(
        json,
        'syntheticDataConfirmed',
        'AndroidEvidenceManifest',
      ),
      observations: values
          .map(AndroidEvidenceObservation.fromJson)
          .toList(growable: false),
    );
    if (Digest(
          _androidEvidenceString(json, 'digest', 'AndroidEvidenceManifest'),
        ) !=
        manifest.digest) {
      throw const FormatException('AndroidEvidenceManifest.digest mismatch');
    }
    return manifest;
  }
}

final class VisualComparisonPolicy {
  VisualComparisonPolicy({
    required this.id,
    required this.maxChannelDelta,
    required this.maxChangedPixelRatio,
  }) {
    if (id.isEmpty ||
        maxChannelDelta < 0 ||
        maxChannelDelta > 255 ||
        !maxChangedPixelRatio.isFinite ||
        maxChangedPixelRatio < 0 ||
        maxChangedPixelRatio > 1) {
      throw const FormatException('Visual comparison policy is invalid');
    }
  }

  final String id;
  final int maxChannelDelta;
  final double maxChangedPixelRatio;
  late final Digest digest = Digest.semantic(toJson());
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'VisualComparisonPolicy',
    'id': id,
    'maxChannelDelta': maxChannelDelta,
    'maxChangedPixelRatio': maxChangedPixelRatio,
  };

  factory VisualComparisonPolicy.fromJson(Object? value) {
    final json = _androidEvidenceObject(value, 'VisualComparisonPolicy');
    _androidEvidenceOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'id',
      'maxChannelDelta',
      'maxChangedPixelRatio',
    }, 'VisualComparisonPolicy');
    if (json['schemaVersion'] != 1 ||
        json['kind'] != 'VisualComparisonPolicy') {
      throw const FormatException(
        'Invalid VisualComparisonPolicy version or kind',
      );
    }
    final ratio = json['maxChangedPixelRatio'];
    if (ratio is! num) {
      throw const FormatException(
        'VisualComparisonPolicy ratio must be numeric',
      );
    }
    return VisualComparisonPolicy(
      id: _androidEvidenceString(json, 'id', 'VisualComparisonPolicy'),
      maxChannelDelta: _androidEvidenceInt(
        json,
        'maxChannelDelta',
        'VisualComparisonPolicy',
      ),
      maxChangedPixelRatio: ratio.toDouble(),
    );
  }
}

final class SemanticComparisonPolicy {
  SemanticComparisonPolicy({
    required this.id,
    required this.maxChangedNodes,
    required this.ignoreBounds,
  }) {
    if (id.isEmpty || maxChangedNodes < 0) {
      throw const FormatException('Semantic comparison policy is invalid');
    }
  }
  final String id;
  final int maxChangedNodes;
  final bool ignoreBounds;
  late final Digest digest = Digest.semantic(toJson());
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'SemanticComparisonPolicy',
    'id': id,
    'maxChangedNodes': maxChangedNodes,
    'ignoreBounds': ignoreBounds,
  };

  factory SemanticComparisonPolicy.fromJson(Object? value) {
    final json = _androidEvidenceObject(value, 'SemanticComparisonPolicy');
    _androidEvidenceOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'id',
      'maxChangedNodes',
      'ignoreBounds',
    }, 'SemanticComparisonPolicy');
    if (json['schemaVersion'] != 1 ||
        json['kind'] != 'SemanticComparisonPolicy') {
      throw const FormatException(
        'Invalid SemanticComparisonPolicy version or kind',
      );
    }
    return SemanticComparisonPolicy(
      id: _androidEvidenceString(json, 'id', 'SemanticComparisonPolicy'),
      maxChangedNodes: _androidEvidenceInt(
        json,
        'maxChangedNodes',
        'SemanticComparisonPolicy',
      ),
      ignoreBounds: _androidEvidenceBool(
        json,
        'ignoreBounds',
        'SemanticComparisonPolicy',
      ),
    );
  }
}

final class EvidenceComparisonReport {
  EvidenceComparisonReport({
    required this.comparisonKind,
    required this.expectedDigest,
    required this.actualDigest,
    required this.policyDigest,
    required this.passed,
    required this.comparedUnits,
    required this.changedUnits,
    required Map<String, Object?> metrics,
  }) : metrics = Map<String, Object?>.unmodifiable(metrics) {
    if (!const <String>{'visual', 'semantic'}.contains(comparisonKind) ||
        comparedUnits < 0 ||
        changedUnits < 0 ||
        changedUnits > comparedUnits) {
      throw const FormatException('Evidence comparison report is invalid');
    }
  }
  final String comparisonKind;
  final Digest expectedDigest;
  final Digest actualDigest;
  final Digest policyDigest;
  final bool passed;
  final int comparedUnits;
  final int changedUnits;
  final Map<String, Object?> metrics;
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));
  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'EvidenceComparisonReport',
    'comparisonKind': comparisonKind,
    'expectedDigest': expectedDigest.value,
    'actualDigest': actualDigest.value,
    'policyDigest': policyDigest.value,
    'passed': passed,
    'comparedUnits': comparedUnits,
    'changedUnits': changedUnits,
    'metrics': metrics,
    if (includeDigest) 'digest': digest.value,
  };

  factory EvidenceComparisonReport.fromJson(Object? value) {
    final json = _androidEvidenceObject(value, 'EvidenceComparisonReport');
    _androidEvidenceOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'comparisonKind',
      'expectedDigest',
      'actualDigest',
      'policyDigest',
      'passed',
      'comparedUnits',
      'changedUnits',
      'metrics',
      'digest',
    }, 'EvidenceComparisonReport');
    if (json['schemaVersion'] != 1 ||
        json['kind'] != 'EvidenceComparisonReport' ||
        json['metrics'] is! Map<String, Object?>) {
      throw const FormatException(
        'Invalid EvidenceComparisonReport version, kind, or metrics',
      );
    }
    final report = EvidenceComparisonReport(
      comparisonKind: _androidEvidenceString(
        json,
        'comparisonKind',
        'EvidenceComparisonReport',
      ),
      expectedDigest: Digest(
        _androidEvidenceString(
          json,
          'expectedDigest',
          'EvidenceComparisonReport',
        ),
      ),
      actualDigest: Digest(
        _androidEvidenceString(
          json,
          'actualDigest',
          'EvidenceComparisonReport',
        ),
      ),
      policyDigest: Digest(
        _androidEvidenceString(
          json,
          'policyDigest',
          'EvidenceComparisonReport',
        ),
      ),
      passed: _androidEvidenceBool(json, 'passed', 'EvidenceComparisonReport'),
      comparedUnits: _androidEvidenceInt(
        json,
        'comparedUnits',
        'EvidenceComparisonReport',
      ),
      changedUnits: _androidEvidenceInt(
        json,
        'changedUnits',
        'EvidenceComparisonReport',
      ),
      metrics: json['metrics']! as Map<String, Object?>,
    );
    if (Digest(
          _androidEvidenceString(json, 'digest', 'EvidenceComparisonReport'),
        ) !=
        report.digest) {
      throw const FormatException('EvidenceComparisonReport.digest mismatch');
    }
    return report;
  }
}

Map<String, Object?> _androidEvidenceObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _androidEvidenceOnly(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _androidEvidenceString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

int _androidEvidenceInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

bool _androidEvidenceBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

Map<String, String> _androidEvidenceStringMap(Object? value, String path) {
  if (value is! Map<String, Object?> ||
      value.values.any((item) => item is! String)) {
    throw FormatException('$path must be a string map');
  }
  return value.cast<String, String>();
}

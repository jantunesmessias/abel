import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';

import '../evidence/png_capture_inspector.dart';
import '../storage/filesystem_workspace_store.dart';
import 'scenario_lab_execution_ports.dart';

/// Resolves one exact Scenario Lab comparison input from the Host CAS.
///
/// The resolver performs direct digest lookups only. It never enumerates CAS
/// entries or substitutes a first/latest artifact when the requested identity
/// is absent.
final class ScenarioLabSupplementalArtifactCasResolver {
  const ScenarioLabSupplementalArtifactCasResolver({
    required this.store,
    this.pngInspector = const PngCaptureInspector(),
  });

  final FileSystemWorkspaceStore store;
  final PngCaptureInspector pngInspector;

  Future<ScenarioLabResolvedComparisonArtifact?> resolve({
    required ScenarioLabRunId runId,
    required ScenarioLabComparisonArtifactDescriptor descriptor,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    if (cancellation.isCancelled) {
      throw const ScenarioLabComparisonCancelled();
    }

    final List<int>? artifactBytes;
    final List<int>? provenanceBytes;
    try {
      artifactBytes = store.readBlob(descriptor.artifactDigest);
      provenanceBytes = store.readBlob(descriptor.provenanceDigest);
    } on FileSystemException {
      throw const ScenarioLabComparisonInputInvalid();
    } on StateError {
      throw const ScenarioLabComparisonInputInvalid();
    }
    if (artifactBytes == null || provenanceBytes == null) return null;
    if (cancellation.isCancelled) {
      throw const ScenarioLabComparisonCancelled();
    }
    if (provenanceBytes.isEmpty ||
        provenanceBytes.length >
            ScenarioLabSupplementalArtifactProvenance.maxDocumentBytes) {
      throw const ScenarioLabComparisonInputInvalid();
    }

    final ScenarioLabSupplementalArtifactProvenance provenance;
    try {
      final decoded = jsonDecode(
        utf8.decode(provenanceBytes, allowMalformed: false),
      );
      provenance = ScenarioLabSupplementalArtifactProvenance.fromJson(
        decoded,
        expectedDigest: descriptor.provenanceDigest,
      );
      if (!_sameBytes(provenanceBytes, provenance.canonicalBytes) ||
          provenance.digest != descriptor.provenanceDigest ||
          provenance.artifactDigest != descriptor.artifactDigest ||
          provenance.size != artifactBytes.length ||
          provenance.classification != descriptor.classification ||
          Digest.bytes(artifactBytes) != descriptor.artifactDigest) {
        throw const FormatException(
          'Scenario Lab supplemental artifact provenance mismatch',
        );
      }
      _validateMedia(provenance.mediaType, artifactBytes);
    } on CanonicalJsonException {
      throw const ScenarioLabComparisonInputInvalid();
    } on FormatException {
      throw const ScenarioLabComparisonInputInvalid();
    } on ArgumentError {
      throw const ScenarioLabComparisonInputInvalid();
    }

    if (cancellation.isCancelled) {
      throw const ScenarioLabComparisonCancelled();
    }
    return ScenarioLabResolvedComparisonArtifact(
      descriptor: descriptor,
      bytes: artifactBytes,
    );
  }

  void _validateMedia(
    ScenarioLabSupplementalArtifactMediaType mediaType,
    List<int> bytes,
  ) {
    switch (mediaType) {
      case ScenarioLabSupplementalArtifactMediaType.png:
        pngInspector.inspect(bytes);
        return;
      case ScenarioLabSupplementalArtifactMediaType.androidSemanticsV1:
        _validateAndroidSemantics(bytes);
        return;
    }
  }
}

void _validateAndroidSemantics(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
    throw const FormatException(
      'Scenario Lab semantics snapshot size is invalid',
    );
  }
  final text = utf8.decode(bytes, allowMalformed: false);
  final value = jsonDecode(text);
  if (value is! Map<String, Object?>) {
    throw const FormatException(
      'Scenario Lab semantics snapshot must be an object',
    );
  }
  const fields = <String>{'schemaVersion', 'kind', 'privacy', 'nodes'};
  final nodes = value['nodes'];
  if (value.length != fields.length ||
      value.keys.any((key) => !fields.contains(key)) ||
      value['schemaVersion'] != 1 ||
      value['kind'] != 'AndroidSemanticsSnapshot' ||
      value['privacy'] != 'hashedTextV1' ||
      nodes is! List<Object?> ||
      nodes.isEmpty ||
      nodes.length > 100000 ||
      nodes.any((node) => node is! Map<String, Object?>)) {
    throw const FormatException(
      'Scenario Lab semantics snapshot shape is invalid',
    );
  }
  final canonical = '${const JcsCanonicalizer().canonicalize(value)}\n';
  if (text != canonical) {
    throw const FormatException(
      'Scenario Lab semantics snapshot is not canonical JCS',
    );
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

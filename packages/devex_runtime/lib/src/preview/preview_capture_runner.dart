import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:path/path.dart' as p;

import '../evidence/local_evidence_repository.dart';
import '../evidence/png_capture_inspector.dart';
import '../secure_id_generator.dart';
import '../storage/filesystem_workspace_store.dart';
import '../system_clock.dart';
import 'preview_source_scanner.dart';

enum PreviewStabilizationMode { fixedFrames, fixedDuration, pumpAndSettle }

final class PreviewCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class PreviewStabilizationPolicy {
  PreviewStabilizationPolicy({
    required this.id,
    this.mode = PreviewStabilizationMode.fixedFrames,
    this.frames = 2,
    this.duration = const Duration(milliseconds: 32),
    this.timeout = const Duration(seconds: 30),
  }) {
    OpaqueId.validate(id, 'PreviewCapturePolicy');
    if (frames < 1 || frames > 120) {
      throw ArgumentError.value(frames, 'frames');
    }
    if (duration <= Duration.zero || duration > const Duration(seconds: 5)) {
      throw ArgumentError.value(duration, 'duration');
    }
    if (timeout < const Duration(seconds: 1) ||
        timeout > const Duration(minutes: 5)) {
      throw ArgumentError.value(timeout, 'timeout');
    }
  }

  final String id;
  final PreviewStabilizationMode mode;
  final int frames;
  final Duration duration;
  final Duration timeout;

  late final Digest digest = Digest.semantic(<String, Object?>{
    'id': id,
    'mode': mode.name,
    'frames': frames,
    'durationMicros': duration.inMicroseconds,
    'timeoutMicros': timeout.inMicroseconds,
  });
}

final class PreviewProcessResult {
  const PreviewProcessResult({
    required this.exitCode,
    required this.timedOut,
    required this.stdoutTail,
    required this.stderrTail,
    this.outputTruncated = false,
    this.protocolCompleted = false,
  });

  final int exitCode;
  final bool timedOut;
  final String stdoutTail;
  final String stderrTail;
  final bool outputTruncated;
  final bool protocolCompleted;
}

abstract interface class PreviewProcessExecutor {
  Future<PreviewProcessResult> execute({
    required String workingDirectory,
    required String testPath,
    required Duration timeout,
    required Set<String> completionMarkers,
    PreviewCancellationToken? cancellationToken,
  });
}

final class LocalFlutterTestProcessExecutor implements PreviewProcessExecutor {
  const LocalFlutterTestProcessExecutor({
    this.flutterExecutable = 'flutter',
    this.maxArtifactOutputBytes = 64 * 1024 * 1024,
    this.maxDiagnosticOutputBytes = 256 * 1024,
  });

  final String flutterExecutable;
  final int maxArtifactOutputBytes;
  final int maxDiagnosticOutputBytes;

  static const Set<String> _allowedEnvironment = <String>{
    'PATH',
    'HOME',
    'PUB_CACHE',
    'FLUTTER_ROOT',
    'TMPDIR',
    'LANG',
    'LC_ALL',
    'CI',
  };

  @override
  Future<PreviewProcessResult> execute({
    required String workingDirectory,
    required String testPath,
    required Duration timeout,
    required Set<String> completionMarkers,
    PreviewCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return const PreviewProcessResult(
        exitCode: -1,
        timedOut: false,
        stdoutTail: '',
        stderrTail: 'AutoPreview collection was cancelled',
      );
    }
    final environment = <String, String>{
      for (final entry in Platform.environment.entries)
        if (_allowedEnvironment.contains(entry.key)) entry.key: entry.value,
    };
    final fonts = await _resolveFlutterFonts(environment);
    environment['DEVEX_PREVIEW_ROBOTO_FONT'] = fonts.roboto;
    environment['DEVEX_PREVIEW_MATERIAL_ICONS_FONT'] = fonts.materialIcons;
    final process = await Process.start(
      flutterExecutable,
      <String>['test', '--no-pub', testPath],
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: false,
      mode: ProcessStartMode.normal,
    );
    final protocol = Completer<void>();
    late final _BoundedProcessOutput stdout;
    stdout = _BoundedProcessOutput(
      maxArtifactOutputBytes,
      onChanged: () {
        if (!protocol.isCompleted &&
            completionMarkers.any(
              (marker) => stdout.containsCompleteLine(marker),
            )) {
          protocol.complete();
        }
      },
    );
    final stderr = _BoundedProcessOutput(maxDiagnosticOutputBytes);
    final stdoutDone = process.stdout.listen(stdout.add).asFuture<void>();
    final stderrDone = process.stderr.listen(stderr.add).asFuture<void>();
    final outcome = await Future.any<_PreviewProcessOutcome>(
      <Future<_PreviewProcessOutcome>>[
        process.exitCode.then((_) => _PreviewProcessOutcome.exited),
        protocol.future.then((_) => _PreviewProcessOutcome.protocol),
        Future<_PreviewProcessOutcome>.delayed(
          timeout,
          () => _PreviewProcessOutcome.timeout,
        ),
        if (cancellationToken != null)
          cancellationToken.whenCancelled.then(
            (_) => _PreviewProcessOutcome.cancelled,
          ),
      ],
    );
    final timedOut = outcome == _PreviewProcessOutcome.timeout;
    final protocolCompleted = outcome == _PreviewProcessOutcome.protocol;
    if (outcome != _PreviewProcessOutcome.exited) {
      process.kill(ProcessSignal.sigterm);
    }
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      exitCode = await process.exitCode;
    }
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    return PreviewProcessResult(
      exitCode: exitCode,
      timedOut: timedOut,
      stdoutTail: stdout.value,
      stderrTail: stderr.value,
      outputTruncated: stdout.truncated || stderr.truncated,
      protocolCompleted: protocolCompleted,
    );
  }

  Future<_PreviewFonts> _resolveFlutterFonts(
    Map<String, String> environment,
  ) async {
    var flutterRoot = environment['FLUTTER_ROOT'];
    if (flutterRoot == null || flutterRoot.isEmpty) {
      final version = await Process.run(
        flutterExecutable,
        const <String>['--version', '--machine'],
        environment: environment,
        includeParentEnvironment: false,
      );
      if (version.exitCode != 0 || version.stdout is! String) {
        throw StateError('Unable to resolve Flutter fonts for AutoPreview');
      }
      final Object? metadata;
      try {
        metadata = jsonDecode(version.stdout! as String);
      } on FormatException {
        throw StateError('Flutter tool returned invalid version metadata');
      }
      flutterRoot = metadata is Map<String, Object?>
          ? metadata['flutterRoot'] as String?
          : null;
    }
    if (flutterRoot == null || flutterRoot.isEmpty) {
      throw StateError('Flutter root is unavailable for AutoPreview fonts');
    }
    final fontRoot = p.join(
      flutterRoot,
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
    );
    final roboto = _regularBoundedFont(p.join(fontRoot, 'Roboto-Regular.ttf'));
    final materialIcons = _regularBoundedFont(
      p.join(fontRoot, 'MaterialIcons-Regular.otf'),
    );
    return _PreviewFonts(roboto: roboto, materialIcons: materialIcons);
  }

  String _regularBoundedFont(String path) {
    if (FileSystemEntity.typeSync(path, followLinks: true) !=
        FileSystemEntityType.file) {
      throw FileSystemException('Flutter capture font is missing', path);
    }
    final file = File(path);
    final length = file.lengthSync();
    if (length < 1024 || length > 4 * 1024 * 1024) {
      throw FileSystemException('Flutter capture font has invalid size', path);
    }
    return file.resolveSymbolicLinksSync();
  }
}

final class _PreviewFonts {
  const _PreviewFonts({required this.roboto, required this.materialIcons});

  final String roboto;
  final String materialIcons;
}

enum _PreviewProcessOutcome { exited, protocol, timeout, cancelled }

final class _BoundedProcessOutput {
  _BoundedProcessOutput(this.maxBytes, {this.onChanged});

  final int maxBytes;
  final void Function()? onChanged;
  final List<int> _bytes = <int>[];
  bool truncated = false;

  void add(List<int> bytes) {
    _bytes.addAll(bytes);
    if (_bytes.length > maxBytes) {
      truncated = true;
      _bytes.removeRange(0, _bytes.length - maxBytes);
    }
    onChanged?.call();
  }

  String get value => utf8.decode(_bytes, allowMalformed: true);

  bool containsCompleteLine(String marker) {
    final output = value;
    final start = output.indexOf(marker);
    return start >= 0 && output.indexOf('\n', start + marker.length) >= 0;
  }
}

final class PreviewScaffold {
  const PreviewScaffold({
    required this.testPath,
    required this.stagingDirectory,
    required this.outputPaths,
    required this.diagnosticPaths,
    required this.protocolToken,
  });

  final String testPath;
  final String stagingDirectory;
  final Map<String, String> outputPaths;
  final Map<String, String> diagnosticPaths;
  final String protocolToken;

  Future<void> cleanup() async {
    final test = File(testPath);
    if (test.existsSync()) await test.delete();
    final staging = Directory(stagingDirectory);
    if (staging.existsSync()) await staging.delete(recursive: true);
  }
}

final class PreviewScaffoldBuilder {
  const PreviewScaffoldBuilder();

  Future<PreviewScaffold> build({
    required EphemeralPreviewRegistry registry,
    required Iterable<PreviewDescriptor> descriptors,
    required Map<String, PreviewStabilizationPolicy> policies,
  }) async {
    final values = descriptors.toList(growable: false);
    final runId = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final protocolToken = runId.replaceAll('-', '_');
    final staging = p.join(registry.directory, 'staging-$runId');
    _requireConfined(registry.directory, staging);
    await Directory(staging).create(recursive: false);
    final outputPaths = <String, String>{
      for (final descriptor in values)
        descriptor.key: p.join(staging, '${_safeName(descriptor.key)}.png'),
    };
    final diagnosticPaths = <String, String>{
      for (final descriptor in values)
        descriptor.key: p.join(
          staging,
          '${_safeName(descriptor.key)}.error.txt',
        ),
    };
    final testPath = p.join(registry.directory, 'capture-${runId}_test.dart');
    _requireConfined(registry.directory, testPath);
    await _atomicWrite(
      testPath,
      _source(
        values,
        policies: policies,
        outputPaths: outputPaths,
        diagnosticPaths: diagnosticPaths,
        protocolToken: protocolToken,
      ),
    );
    return PreviewScaffold(
      testPath: testPath,
      stagingDirectory: staging,
      outputPaths: Map<String, String>.unmodifiable(outputPaths),
      diagnosticPaths: Map<String, String>.unmodifiable(diagnosticPaths),
      protocolToken: protocolToken,
    );
  }

  String _source(
    List<PreviewDescriptor> descriptors, {
    required Map<String, PreviewStabilizationPolicy> policies,
    required Map<String, String> outputPaths,
    required Map<String, String> diagnosticPaths,
    required String protocolToken,
  }) {
    final maxWidth = descriptors
        .map((descriptor) => descriptor.variant.logicalWidth)
        .fold<double>(0, (left, right) => left > right ? left : right);
    final maxHeight = descriptors
        .map((descriptor) => descriptor.variant.logicalHeight)
        .fold<double>(0, (left, right) => left > right ? left : right);
    final buffer = StringBuffer()
      ..writeln('// Generated by DevExKit. Do not edit.')
      ..writeln("import 'dart:convert';")
      ..writeln("import 'dart:io';")
      ..writeln("import 'dart:typed_data';")
      ..writeln("import 'dart:ui' as ui;")
      ..writeln()
      ..writeln("import 'package:flutter/material.dart';")
      ..writeln("import 'package:flutter/rendering.dart';")
      ..writeln("import 'package:flutter/services.dart';")
      ..writeln("import 'package:flutter_test/flutter_test.dart';")
      ..writeln("import 'preview_registry.g.dart';")
      ..writeln()
      ..writeln('void main() {')
      ..writeln("  testWidgets('capture AutoPreview batch', (tester) async {")
      ..writeln('    await _loadDevExFonts();')
      ..writeln(
        '    await tester.binding.setSurfaceSize('
        'const Size($maxWidth, $maxHeight));',
      );
    for (final descriptor in descriptors) {
      final variant = descriptor.variant;
      final policy = policies[descriptor.capturePolicyId]!;
      buffer
        ..writeln('    // ${descriptor.key}')
        ..writeln('    try {')
        ..writeln(
          '    tester.platformDispatcher.localeTestValue = '
          '_locale(${jsonEncode(variant.localeTag)});',
        )
        ..writeln(
          '    tester.platformDispatcher.platformBrightnessTestValue = '
          'Brightness.${variant.brightness.name};',
        )
        ..writeln('    final boundaryKey = GlobalKey();')
        ..writeln('    await tester.pumpWidget(')
        ..writeln('      Align(')
        ..writeln('        alignment: Alignment.topLeft,')
        ..writeln('        child: SizedBox(')
        ..writeln('          width: ${variant.logicalWidth},')
        ..writeln('          height: ${variant.logicalHeight},')
        ..writeln('          child: MediaQuery(')
        ..writeln('            data: MediaQueryData(')
        ..writeln(
          '              size: const Size(${variant.logicalWidth}, '
          '${variant.logicalHeight}),',
        )
        ..writeln(
          '              devicePixelRatio: ${variant.devicePixelRatio},',
        )
        ..writeln(
          '              platformBrightness: Brightness.${variant.brightness.name},',
        )
        ..writeln(
          '              textScaler: TextScaler.linear(${variant.textScaleFactor}),',
        )
        ..writeln('            ),')
        ..writeln('            child: RepaintBoundary(')
        ..writeln('              key: boundaryKey,')
        ..writeln('              child: Builder(')
        ..writeln(
          '                builder: devexPreviewFactories['
          '${jsonEncode(descriptor.key)}]!,',
        )
        ..writeln('              ),')
        ..writeln('            ),')
        ..writeln('          ),')
        ..writeln('        ),')
        ..writeln('      ),')
        ..writeln('    );');
      _writeStabilization(buffer, policy);
      buffer
        ..writeln(
          '    final boundary = boundaryKey.currentContext!'
          '.findRenderObject()! as RenderRepaintBoundary;',
        )
        ..writeln(
          '    final image = await boundary.toImage('
          'pixelRatio: ${variant.devicePixelRatio});',
        )
        ..writeln(
          '    final data = await image.toByteData('
          'format: ui.ImageByteFormat.png);',
        )
        ..writeln('    image.dispose();')
        ..writeln(
          "    if (data == null) throw StateError('PNG encoding failed');",
        )
        ..writeln(
          '    // DEVEX_OUTPUT ${jsonEncode(outputPaths[descriptor.key])}',
        )
        ..writeln(
          "    print('DEVEX_PREVIEW_${protocolToken}_PNG "
          "${base64Encode(utf8.encode(descriptor.key))} "
          "\${base64Encode(data.buffer.asUint8List())}');",
        )
        ..writeln('    } on Object catch (error, stackTrace) {')
        ..writeln(
          "      print('DEVEX_PREVIEW_${protocolToken}_ERROR "
          "${base64Encode(utf8.encode(descriptor.key))} "
          "\${base64Encode(utf8.encode('\$error\\n\$stackTrace'))}');",
        )
        ..writeln('    }');
    }
    buffer
      ..writeln('  }, timeout: const Timeout(Duration(minutes: 4)));')
      ..writeln('}')
      ..writeln()
      ..writeln('Future<void> _loadDevExFonts() async {')
      ..writeln(
        "  await _loadDevExFont('Roboto', 'DEVEX_PREVIEW_ROBOTO_FONT');",
      )
      ..writeln(
        "  await _loadDevExFont('MaterialIcons', "
        "'DEVEX_PREVIEW_MATERIAL_ICONS_FONT');",
      )
      ..writeln('}')
      ..writeln()
      ..writeln(
        'Future<void> _loadDevExFont(String family, String environmentKey) async {',
      )
      ..writeln('  final path = Platform.environment[environmentKey];')
      ..writeln("  if (path == null) throw StateError('Missing capture font');")
      ..writeln('  final bytes = File(path).readAsBytesSync();')
      ..writeln('  final loader = FontLoader(family)')
      ..writeln(
        '    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));',
      )
      ..writeln('  await loader.load();')
      ..writeln('}')
      ..writeln()
      ..writeln('Locale _locale(String tag) {')
      ..writeln("  final parts = tag.split('-');")
      ..writeln('  return Locale.fromSubtags(')
      ..writeln('    languageCode: parts[0],')
      ..writeln('    countryCode: parts.length > 1 ? parts[1] : null,')
      ..writeln('    scriptCode: parts.length > 2 ? parts[1] : null,')
      ..writeln('  );')
      ..writeln('}');
    return buffer.toString();
  }

  void _writeStabilization(
    StringBuffer buffer,
    PreviewStabilizationPolicy policy,
  ) {
    switch (policy.mode) {
      case PreviewStabilizationMode.fixedFrames:
        buffer.writeln(
          '    for (var frame = 0; frame < ${policy.frames}; frame++) '
          '{ await tester.pump(const Duration(milliseconds: 16)); }',
        );
      case PreviewStabilizationMode.fixedDuration:
        buffer.writeln(
          '    await tester.pump(const Duration('
          'microseconds: ${policy.duration.inMicroseconds}));',
        );
      case PreviewStabilizationMode.pumpAndSettle:
        buffer.writeln(
          '    await tester.pumpAndSettle('
          'const Duration(milliseconds: 16), '
          'timeout: const Duration('
          'microseconds: ${policy.timeout.inMicroseconds}));',
        );
    }
  }

  String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  void _requireConfined(String root, String target) {
    if (!p.isWithin(root, target)) {
      throw FileSystemException(
        'Preview scaffold escapes registry root',
        target,
      );
    }
    if (FileSystemEntity.typeSync(target, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('Preview scaffold target is a link', target);
    }
  }

  Future<void> _atomicWrite(String path, String contents) async {
    final temporary = File('$path.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(path);
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }
}

final class PreviewArtifactIngestor {
  const PreviewArtifactIngestor({this.inspector = const PngCaptureInspector()});

  final PngCaptureInspector inspector;

  PreviewCaptureItem ingest({
    required PreviewDescriptor descriptor,
    required Digest captureKey,
    required String path,
    required FileSystemWorkspaceStore store,
  }) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const FormatException('Capture output is not a regular file');
    }
    final bytes = File(path).readAsBytesSync();
    final inspection = inspector.inspect(bytes);
    final artifactDigest = store.putBlob(bytes);
    return PreviewCaptureItem(
      previewId: descriptor.id,
      scenarioId: descriptor.scenarioId,
      variantId: descriptor.variant.id,
      descriptorDigest: descriptor.digest,
      captureKey: captureKey,
      status: PreviewCaptureStatus.collected,
      artifactDigest: artifactDigest,
      pixelDigest: inspection.pixelDigest,
      pixelWidth: inspection.width,
      pixelHeight: inspection.height,
    );
  }
}

final class PreviewCaptureRun {
  const PreviewCaptureRun({required this.manifest, required this.report});

  final PreviewCaptureManifest manifest;
  final PreviewCaptureReport report;
}

final class PreviewCaptureRunner {
  PreviewCaptureRunner({
    required this.store,
    PreviewProcessExecutor? processExecutor,
    this.scaffoldBuilder = const PreviewScaffoldBuilder(),
    this.ingestor = const PreviewArtifactIngestor(),
    Clock? clock,
  }) : processExecutor =
           processExecutor ?? const LocalFlutterTestProcessExecutor(),
       clock = clock ?? SystemClock();

  final FileSystemWorkspaceStore store;
  final PreviewProcessExecutor processExecutor;
  final PreviewScaffoldBuilder scaffoldBuilder;
  final PreviewArtifactIngestor ingestor;
  final Clock clock;

  Future<PreviewCaptureRun> run({
    required String applicationRoot,
    required PreviewManifest previewManifest,
    required EphemeralPreviewRegistry registry,
    required ExecutionFingerprint fingerprint,
    required Digest planDigest,
    required Digest toolchainDigest,
    required Map<String, PreviewStabilizationPolicy> policies,
    required bool syntheticDataConfirmed,
    Map<String, Digest> inputDigests = const <String, Digest>{},
    PreviewCancellationToken? cancellationToken,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (fingerprint.catalogDigest != previewManifest.catalogDigest ||
        fingerprint.renderer != 'flutter-test' ||
        fingerprint.runtimeFidelity != RuntimeFidelity.structural) {
      throw ArgumentError(
        'AutoPreview requires matching catalog, flutter-test renderer, and '
        'structural fidelity',
      );
    }
    final startedAt = clock.nowUtc();
    final captureKeys = <String, Digest>{};
    final items = <String, PreviewCaptureItem>{};
    final runnable = <PreviewDescriptor>[];
    for (final descriptor in previewManifest.descriptors) {
      final policy = policies[descriptor.capturePolicyId];
      final key = _captureKey(
        descriptor: descriptor,
        previewManifest: previewManifest,
        planDigest: planDigest,
        toolchainDigest: toolchainDigest,
        policy: policy,
        inputDigests: inputDigests,
      );
      captureKeys[descriptor.key] = key;
      if (!syntheticDataConfirmed) {
        items[descriptor.key] = _failedItem(
          descriptor,
          key,
          PreviewCaptureStatus.policyDenied,
          code: 'preview.synthetic-data.required',
          message: 'Pixel persistence requires synthetic data confirmation',
        );
      } else if (policy == null) {
        items[descriptor.key] = _failedItem(
          descriptor,
          key,
          PreviewCaptureStatus.unsupported,
          code: 'preview.policy.unsupported',
          message:
              'Capture policy ${descriptor.capturePolicyId} is unavailable',
        );
      } else {
        runnable.add(descriptor);
      }
    }

    final processDiagnostics = <PreviewCaptureDiagnostic>[];
    var completed = items.length;
    onProgress?.call(completed, previewManifest.descriptors.length);
    for (final descriptor in runnable) {
      if (cancellationToken?.isCancelled ?? false) {
        items[descriptor.key] = _failedItem(
          descriptor,
          captureKeys[descriptor.key]!,
          PreviewCaptureStatus.failed,
          code: 'preview.capture.cancelled',
          message: 'AutoPreview collection was cancelled',
        );
        completed += 1;
        onProgress?.call(completed, previewManifest.descriptors.length);
        continue;
      }
      PreviewScaffold? scaffold;
      try {
        scaffold = await scaffoldBuilder.build(
          registry: registry,
          descriptors: <PreviewDescriptor>[descriptor],
          policies: policies,
        );
        final process = await processExecutor.execute(
          workingDirectory: applicationRoot,
          testPath: scaffold.testPath,
          timeout:
              policies[descriptor.capturePolicyId]!.timeout +
              const Duration(seconds: 30),
          completionMarkers: <String>{
            'DEVEX_PREVIEW_${scaffold.protocolToken}_PNG ',
            'DEVEX_PREVIEW_${scaffold.protocolToken}_ERROR ',
          },
          cancellationToken: cancellationToken,
        );
        _materializeProtocolOutput(process, scaffold);
        final output = scaffold.outputPaths[descriptor.key]!;
        if (File(output).existsSync()) {
          try {
            items[descriptor.key] = ingestor.ingest(
              descriptor: descriptor,
              captureKey: captureKeys[descriptor.key]!,
              path: output,
              store: store,
            );
          } on FormatException catch (error) {
            items[descriptor.key] = _failedItem(
              descriptor,
              captureKeys[descriptor.key]!,
              PreviewCaptureStatus.invalid,
              code: 'preview.png.invalid',
              message: _bounded(error.message),
            );
          }
        } else {
          final itemDiagnostic = _itemDiagnostic(
            scaffold.diagnosticPaths[descriptor.key]!,
          );
          items[descriptor.key] = _failedItem(
            descriptor,
            captureKeys[descriptor.key]!,
            PreviewCaptureStatus.failed,
            code: process.timedOut
                ? 'preview.capture.timeout'
                : 'preview.capture.failed',
            message: itemDiagnostic ?? _processDiagnostic(process),
          );
        }
        if (process.exitCode != 0 && !process.protocolCompleted) {
          processDiagnostics.add(
            PreviewCaptureDiagnostic(
              code: 'preview.process.nonzero',
              severity: PreviewDiagnosticSeverity.warning,
              message: _processDiagnostic(process),
            ),
          );
        }
      } on Object catch (error) {
        items[descriptor.key] = _failedItem(
          descriptor,
          captureKeys[descriptor.key]!,
          PreviewCaptureStatus.failed,
          code: 'preview.runner.failed',
          message: _bounded('$error'),
        );
      } finally {
        await scaffold?.cleanup();
        completed += 1;
        onProgress?.call(completed, previewManifest.descriptors.length);
      }
    }

    final captureManifest = PreviewCaptureManifest(
      previewManifestDigest: previewManifest.digest,
      renderer: 'flutter-test',
      toolchainDigest: toolchainDigest,
      executionFingerprintDigest: fingerprint.digest,
      items: items.values.toList(growable: false),
    );
    final collected = items.values
        .where((item) => item.status == PreviewCaptureStatus.collected)
        .length;
    return PreviewCaptureRun(
      manifest: captureManifest,
      report: PreviewCaptureReport(
        captureManifestDigest: captureManifest.digest,
        startedAt: startedAt,
        completedAt: clock.nowUtc(),
        totalItems: items.length,
        collectedItems: collected,
        failedItems: items.length - collected,
        diagnostics: processDiagnostics,
      ),
    );
  }

  Digest _captureKey({
    required PreviewDescriptor descriptor,
    required PreviewManifest previewManifest,
    required Digest planDigest,
    required Digest toolchainDigest,
    required PreviewStabilizationPolicy? policy,
    required Map<String, Digest> inputDigests,
  }) => Digest.semantic(<String, Object?>{
    'descriptorDigest': descriptor.digest.value,
    'previewManifestDigest': previewManifest.digest.value,
    'planDigest': planDigest.value,
    'toolchainDigest': toolchainDigest.value,
    'policyDigest': policy?.digest.value ?? 'unsupported',
    'inputs': <String, Object?>{
      for (final key in inputDigests.keys.toList()..sort())
        key: inputDigests[key]!.value,
    },
  });

  PreviewCaptureItem _failedItem(
    PreviewDescriptor descriptor,
    Digest captureKey,
    PreviewCaptureStatus status, {
    required String code,
    required String message,
  }) => PreviewCaptureItem(
    previewId: descriptor.id,
    scenarioId: descriptor.scenarioId,
    variantId: descriptor.variant.id,
    descriptorDigest: descriptor.digest,
    captureKey: captureKey,
    status: status,
    diagnostics: <PreviewCaptureDiagnostic>[
      PreviewCaptureDiagnostic(
        code: code,
        severity: PreviewDiagnosticSeverity.error,
        message: _bounded(message),
      ),
    ],
  );

  String _processDiagnostic(PreviewProcessResult process) {
    if (process.outputTruncated) {
      return 'Flutter test output exceeded the capture budget';
    }
    if (process.timedOut) return 'Flutter test capture timed out';
    final source = process.stderrTail.trim().isNotEmpty
        ? process.stderrTail.trim()
        : process.stdoutTail.trim();
    return _bounded(
      source.isEmpty
          ? 'Flutter test exited with code ${process.exitCode}'
          : source,
    );
  }

  void _materializeProtocolOutput(
    PreviewProcessResult process,
    PreviewScaffold scaffold,
  ) {
    if (process.outputTruncated) return;
    final pngPrefix = 'DEVEX_PREVIEW_${scaffold.protocolToken}_PNG ';
    final errorPrefix = 'DEVEX_PREVIEW_${scaffold.protocolToken}_ERROR ';
    final seen = <String>{};
    for (final line in const LineSplitter().convert(process.stdoutTail)) {
      final pngAt = line.indexOf(pngPrefix);
      final errorAt = line.indexOf(errorPrefix);
      if (pngAt >= 0) {
        final payload = line
            .substring(pngAt + pngPrefix.length)
            .trim()
            .split(' ');
        if (payload.length != 2) continue;
        final key = _decodeProtocolText(payload[0]);
        final output = key == null ? null : scaffold.outputPaths[key];
        if (output == null || !seen.add('png:$key')) continue;
        try {
          final bytes = base64Decode(payload[1]);
          File(output).writeAsBytesSync(bytes);
        } on FormatException {
          continue;
        }
      } else if (errorAt >= 0) {
        final payload = line
            .substring(errorAt + errorPrefix.length)
            .trim()
            .split(' ');
        if (payload.length != 2) continue;
        final key = _decodeProtocolText(payload[0]);
        final output = key == null ? null : scaffold.diagnosticPaths[key];
        if (output == null || !seen.add('error:$key')) continue;
        final diagnostic = _decodeProtocolText(payload[1]);
        if (diagnostic != null) {
          File(output).writeAsStringSync(_bounded(diagnostic));
        }
      }
    }
  }

  String? _decodeProtocolText(String value) {
    try {
      return utf8.decode(base64Decode(value));
    } on FormatException {
      return null;
    }
  }

  String? _itemDiagnostic(String path) {
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final file = File(path);
    if (file.lengthSync() > 64 * 1024) {
      return 'Preview failure diagnostic exceeded the output budget';
    }
    return _bounded(file.readAsStringSync());
  }

  String _bounded(String value) {
    const max = 2048;
    return value.length <= max ? value : value.substring(value.length - max);
  }
}

final class PreviewEvidenceProvider {
  PreviewEvidenceProvider({
    required this.store,
    required this.repository,
    Clock? clock,
    IdGenerator? ids,
  }) : clock = clock ?? SystemClock(),
       ids = ids ?? SecureIdGenerator();

  final FileSystemWorkspaceStore store;
  final LocalEvidenceRepository repository;
  final Clock clock;
  final IdGenerator ids;

  Evidence persist({
    required PreviewCaptureRun run,
    required ExecutionFingerprint fingerprint,
    ArtifactClassification classification = ArtifactClassification.internal,
  }) {
    if (run.manifest.executionFingerprintDigest != fingerprint.digest ||
        fingerprint.runtimeFidelity != RuntimeFidelity.structural) {
      throw ArgumentError(
        'Preview Evidence fingerprint does not match the run',
      );
    }
    final manifestBytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(run.manifest.toJson())}\n',
    );
    final manifestDigest = store.putBlob(manifestBytes);
    final artifacts = <Digest, Artifact>{
      manifestDigest: Artifact(
        digest: manifestDigest,
        size: manifestBytes.length,
        mediaType: 'application/vnd.devex.preview-capture+json',
        classification: classification,
        role: 'preview.capture-manifest',
      ),
    };
    for (final item in run.manifest.items) {
      final digest = item.artifactDigest;
      if (digest == null || artifacts.containsKey(digest)) continue;
      final bytes = store.readBlob(digest);
      if (bytes == null) {
        throw StateError(
          'Preview artifact ${digest.value} is missing from CAS',
        );
      }
      artifacts[digest] = Artifact(
        digest: digest,
        size: bytes.length,
        mediaType: 'image/png',
        classification: classification,
        role: 'preview.capture',
        pixelDigest: item.pixelDigest,
        width: item.pixelWidth,
        height: item.pixelHeight,
      );
    }
    return repository.persistEvidence(
      Evidence(
        id: 'evidence-${ids.nextId()}',
        subjectDigest: fingerprint.catalogDigest,
        fingerprint: fingerprint,
        observedAt: clock.nowUtc(),
        policyId: 'auto-preview-v1',
        artifacts: artifacts.values.toList(growable: false),
      ),
    );
  }
}

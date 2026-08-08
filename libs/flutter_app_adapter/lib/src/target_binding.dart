import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'app_adapter.dart';
import 'app_adapter_bridge.dart';
import 'app_adapter_relay.dart';

@immutable
final class TargetBinding {
  TargetBinding({
    required this.sessionId,
    required this.nonce,
    required Map<String, String> runtimeConfiguration,
    required Set<String> capabilities,
    this.controllerOrigin,
  }) : runtimeConfiguration = Map<String, String>.unmodifiable(
         runtimeConfiguration,
       ),
       capabilities = Set<String>.unmodifiable(capabilities) {
    if (sessionId.isEmpty) throw ArgumentError.value(sessionId, 'sessionId');
    if (nonce.length < 16) throw ArgumentError.value(nonce, 'nonce');
    final controller = controllerOrigin;
    if (controller != null &&
        (!controller.hasScheme ||
            !const <String>{'http', 'https'}.contains(controller.scheme) ||
            controller.host.isEmpty)) {
      throw ArgumentError.value(controller, 'controllerOrigin');
    }
  }

  final String sessionId;
  final String nonce;
  final Map<String, String> runtimeConfiguration;
  final Set<String> capabilities;
  final Uri? controllerOrigin;
}

final class TargetScope extends InheritedWidget {
  const TargetScope({required this.binding, required super.child, super.key});

  final TargetBinding binding;

  static TargetBinding of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TargetScope>();
    if (scope == null) {
      throw FlutterError('No TargetScope found in this widget tree.');
    }
    return scope.binding;
  }

  @override
  bool updateShouldNotify(TargetScope oldWidget) =>
      !identical(binding, oldWidget.binding);
}

final class FlutterTargetHandle {
  const FlutterTargetHandle({
    required this.adapter,
    required this.bridge,
    this.relay,
  });

  final AppAdapter adapter;
  final AppAdapterBridge bridge;
  final AppAdapterRelay? relay;

  void dispose() => bridge.dispose();
}

final class WidgetCaptureController {
  final GlobalKey boundaryKey = GlobalKey();

  Widget wrap(Widget child) => RepaintBoundary(key: boundaryKey, child: child);

  Future<List<int>> capturePng() async {
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.idle) {
      await binding.endOfFrame;
    }
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('Target capture boundary is not mounted');
    }
    if (renderObject.debugNeedsPaint) {
      binding.ensureVisualUpdate();
      await binding.endOfFrame;
    }
    final image = await renderObject.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Flutter did not encode capture PNG');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}

FlutterTargetHandle runFlutterTarget({
  required TargetBinding binding,
  required Widget app,
  Iterable<AppCapability> capabilities = const <AppCapability>[],
  AppAdapterRelayConfiguration? relayConfiguration,
}) {
  final injectedCapabilities = List<AppCapability>.unmodifiable(capabilities);
  final unadvertised = injectedCapabilities
      .map((capability) => capability.descriptor.id)
      .where((id) => !binding.capabilities.contains(id))
      .toList(growable: false);
  if (unadvertised.isNotEmpty) {
    throw ArgumentError.value(
      unadvertised,
      'capabilities',
      'App Adapter capabilities must be advertised by the binding',
    );
  }
  final capture = WidgetCaptureController();
  final adapter = AppAdapter(
    capabilities: injectedCapabilities,
    captureHandler: (_) => capture.capturePng(),
  );
  final relay = relayConfiguration == null
      ? null
      : AppAdapterRelay(
          adapter: adapter,
          sessionId: binding.sessionId,
          configuration: relayConfiguration,
        );
  if (relay != null) {
    if (relay.hello.runId.value != binding.sessionId) {
      relay.dispose();
      throw ArgumentError(
        'App Adapter relay run must match the target binding session',
      );
    }
    if (relay.hello.nonce.value != binding.nonce) {
      relay.dispose();
      throw ArgumentError(
        'App Adapter relay nonce must match the target binding nonce',
      );
    }
  }
  late final AppAdapterBridge bridge;
  try {
    bridge = startAppAdapterBridge(
      binding: binding,
      adapter: adapter,
      relay: relay,
    );
  } on Object {
    relay?.dispose();
    rethrow;
  }
  runApp(TargetScope(binding: binding, child: capture.wrap(app)));
  return FlutterTargetHandle(adapter: adapter, bridge: bridge, relay: relay);
}

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'devex_app_adapter.dart';
import 'devex_app_adapter_bridge.dart';

@immutable
final class DevExFlutterBinding {
  DevExFlutterBinding({
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

final class DevExTargetScope extends InheritedWidget {
  const DevExTargetScope({
    required this.binding,
    required super.child,
    super.key,
  });

  final DevExFlutterBinding binding;

  static DevExFlutterBinding of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DevExTargetScope>();
    if (scope == null) {
      throw FlutterError('No DevExTargetScope found in this widget tree.');
    }
    return scope.binding;
  }

  @override
  bool updateShouldNotify(DevExTargetScope oldWidget) =>
      !identical(binding, oldWidget.binding);
}

final class DevExFlutterTargetHandle {
  const DevExFlutterTargetHandle({required this.adapter, required this.bridge});

  final DevExAppAdapter adapter;
  final DevExAppAdapterBridge bridge;

  void dispose() => bridge.dispose();
}

final class DevExWidgetCaptureController {
  final GlobalKey boundaryKey = GlobalKey();

  Widget wrap(Widget child) => RepaintBoundary(key: boundaryKey, child: child);

  Future<List<int>> capturePng() async {
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.idle) {
      await binding.endOfFrame;
    }
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('DevEx capture boundary is not mounted');
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

DevExFlutterTargetHandle runDevExFlutterTarget({
  required DevExFlutterBinding binding,
  required Widget app,
}) {
  final capture = DevExWidgetCaptureController();
  final adapter = DevExAppAdapter(
    capabilities: const <DevExCapability>[],
    captureHandler: (_) => capture.capturePng(),
  );
  final bridge = startDevExAppAdapterBridge(binding: binding, adapter: adapter);
  runApp(DevExTargetScope(binding: binding, child: capture.wrap(app)));
  return DevExFlutterTargetHandle(adapter: adapter, bridge: bridge);
}

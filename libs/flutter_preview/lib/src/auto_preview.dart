import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart' show Brightness, Size;

abstract final class PreviewCompatibility {
  static const String flutter = '3.47.x';
  static const String widgetPreviewApi = 'experimental-v2';
}

/// Platform metadata layered on Flutter's official [Preview] annotation.
final class AutoPreview extends Preview {
  const AutoPreview({
    required this.id,
    required this.scenarioId,
    required this.variantId,
    required Size size,
    required this.localeTag,
    required Brightness brightness,
    this.devicePixelRatio = 1,
    this.fixtureRef,
    this.capturePolicyId = 'static-v1',
    super.name,
    super.group = 'Abel',
    super.textScaleFactor = 1,
    super.wrapper,
    super.theme,
    super.localizations,
  }) : assert(id != ''),
       assert(scenarioId != ''),
       assert(variantId != ''),
       assert(localeTag != ''),
       assert(devicePixelRatio > 0 && devicePixelRatio <= 8),
       super(size: size, brightness: brightness);

  final String id;
  final String scenarioId;
  final String variantId;
  final String localeTag;
  final double devicePixelRatio;
  final String? fixtureRef;
  final String capturePolicyId;
}

/// One concrete Scenario variant emitted by [AutoMultiPreview].
final class AutoPreviewVariant extends Preview {
  const AutoPreviewVariant({
    required this.variantId,
    required Size size,
    required this.localeTag,
    required Brightness brightness,
    this.devicePixelRatio = 1,
    super.name,
    super.group = 'Abel',
    super.textScaleFactor = 1,
    super.wrapper,
    super.theme,
    super.localizations,
  }) : assert(variantId != ''),
       assert(localeTag != ''),
       assert(devicePixelRatio > 0 && devicePixelRatio <= 8),
       super(size: size, brightness: brightness);

  final String variantId;
  final String localeTag;
  final double devicePixelRatio;
}

/// Expands multiple visual variants of one existing Scenario.
final class AutoMultiPreview extends MultiPreview {
  const AutoMultiPreview({
    required this.id,
    required this.scenarioId,
    required this.variants,
    this.fixtureRef,
    this.capturePolicyId = 'static-v1',
  }) : assert(id != ''),
       assert(scenarioId != '');

  final String id;
  final String scenarioId;
  final List<AutoPreviewVariant> variants;
  final String? fixtureRef;
  final String capturePolicyId;

  @override
  List<Preview> get previews => variants;
}

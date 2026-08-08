enum DevExInputModality { touch, pointer, keyboard }

final class DevExInteractionPolicy {
  const DevExInteractionPolicy({
    this.pointerTarget = 48,
    this.touchTarget = 48,
    this.focusRingWidth = 2,
  }) : assert(pointerTarget >= 44),
       assert(touchTarget >= 44),
       assert(focusRingWidth > 0);

  final double pointerTarget;
  final double touchTarget;
  final double focusRingWidth;

  double minimumTarget(DevExInputModality modality) => switch (modality) {
    DevExInputModality.touch => touchTarget,
    DevExInputModality.pointer || DevExInputModality.keyboard => pointerTarget,
  };
}

final class DevExMotionPolicy {
  const DevExMotionPolicy({
    this.instant = Duration.zero,
    this.quick = const Duration(milliseconds: 100),
    this.standard = const Duration(milliseconds: 180),
    this.deliberate = const Duration(milliseconds: 260),
  });

  final Duration instant;
  final Duration quick;
  final Duration standard;
  final Duration deliberate;

  Duration resolve(Duration requested, {required bool reduceMotion}) =>
      reduceMotion ? instant : requested;
}

final class DevExZoomPolicy {
  const DevExZoomPolicy({
    this.minimumScale = 0.25,
    this.maximumScale = 3,
    this.detailScale = 0.65,
    this.overscan = 120,
  }) : assert(minimumScale > 0),
       assert(maximumScale > minimumScale),
       assert(detailScale >= minimumScale),
       assert(detailScale <= maximumScale),
       assert(overscan >= 0);

  final double minimumScale;
  final double maximumScale;
  final double detailScale;
  final double overscan;

  bool showsDetail(double scale) => scale >= detailScale;
}

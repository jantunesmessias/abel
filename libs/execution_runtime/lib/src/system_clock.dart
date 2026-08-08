import 'package:experience_engine/experience_engine.dart';

final class SystemClock implements Clock {
  SystemClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  int monotonicMicroseconds() => _stopwatch.elapsedMicroseconds;

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

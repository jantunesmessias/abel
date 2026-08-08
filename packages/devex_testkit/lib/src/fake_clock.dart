import 'package:devex_engine/devex_engine.dart';

final class FakeClock implements Clock {
  FakeClock(this._nowUtc, {this._monotonicMicroseconds = 0});

  DateTime _nowUtc;
  int _monotonicMicroseconds;

  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    _nowUtc = _nowUtc.add(duration);
    _monotonicMicroseconds += duration.inMicroseconds;
  }

  @override
  int monotonicMicroseconds() => _monotonicMicroseconds;

  @override
  DateTime nowUtc() => _nowUtc;
}

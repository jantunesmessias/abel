import 'package:devex_engine/devex_engine.dart';
import 'package:test/test.dart';

void main() {
  test('operation expiry is controlled by the injected clock', () {
    final clock = _FixedClock(DateTime.utc(2026, 8, 9, 12));
    final active = OperationContext(
      operationId: 'op-1',
      correlationId: 'correlation-1',
      deadline: DateTime.utc(2026, 8, 9, 12, 0, 1),
    );
    final expired = OperationContext(
      operationId: 'op-2',
      correlationId: 'correlation-2',
      deadline: DateTime.utc(2026, 8, 9, 11, 59, 59),
    );

    expect(active.isExpired(clock), isFalse);
    expect(expired.isExpired(clock), isTrue);
  });
}

final class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  int monotonicMicroseconds() => 0;

  @override
  DateTime nowUtc() => value;
}

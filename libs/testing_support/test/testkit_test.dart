import 'package:test/test.dart';
import 'package:testing_support/testing_support.dart';

void main() {
  test('fake time and IDs are deterministic', () {
    final clock = FakeClock(DateTime.utc(2026, 8, 9));
    final ids = SequentialIdGenerator(prefix: 'operation');

    clock.advance(const Duration(milliseconds: 25));

    expect(clock.nowUtc(), DateTime.utc(2026, 8, 9, 0, 0, 0, 25));
    expect(clock.monotonicMicroseconds(), 25000);
    expect(ids.nextId(), 'operation-0001');
    expect(ids.nextId(), 'operation-0002');
  });
}

import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('journal resumes ordered events after a cursor', () {
    final journal = HostEventJournal(capacity: 2)
      ..append('one', const <String, Object?>{})
      ..append('two', const <String, Object?>{})
      ..append('three', const <String, Object?>{});

    expect(journal.after(1).map((event) => event.method), <String>[
      'two',
      'three',
    ]);
    expect(() => journal.after(0), throwsA(isA<HostCursorExpiredException>()));
  });
}

import 'dart:convert';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:test/test.dart';

void main() {
  test(
    'frames UTF-8 across chunks and accepts CRLF and a final line',
    () async {
      const decoder = BoundedUtf8LineDecoder(maxLineBytes: 8);
      final chunks = <List<int>>[
        utf8.encode('ol'),
        utf8.encode('á\r\n'),
        utf8.encode('fim'),
      ];

      expect(
        await decoder.bind(Stream<List<int>>.fromIterable(chunks)).toList(),
        <String>['olá', 'fim'],
      );
    },
  );

  test(
    'fails while streaming at the byte limit without retaining the tail',
    () async {
      const decoder = BoundedUtf8LineDecoder(maxLineBytes: 4);
      final chunks = <List<int>>[utf8.encode('1234'), utf8.encode('5' * 1000)];

      await expectLater(
        decoder.bind(Stream<List<int>>.fromIterable(chunks)).drain<void>(),
        throwsFormatException,
      );
    },
  );

  test('rejects malformed UTF-8', () async {
    const decoder = BoundedUtf8LineDecoder(maxLineBytes: 4);

    await expectLater(
      decoder
          .bind(Stream<List<int>>.value(const <int>[0xc3, 0x0a]))
          .drain<void>(),
      throwsFormatException,
    );
  });
}

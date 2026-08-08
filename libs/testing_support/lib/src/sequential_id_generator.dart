import 'package:experience_engine/experience_engine.dart';

final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator({this.prefix = 'test'});

  final String prefix;
  var _next = 1;

  @override
  String nextId() {
    final value = '$prefix-${_next.toString().padLeft(4, '0')}';
    _next += 1;
    return value;
  }
}

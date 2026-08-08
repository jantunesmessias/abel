import 'dart:convert';
import 'dart:math';

import 'package:experience_engine/experience_engine.dart';

final class SecureIdGenerator implements IdGenerator {
  SecureIdGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  String nextId() {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

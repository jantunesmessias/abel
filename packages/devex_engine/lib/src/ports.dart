abstract interface class Clock {
  DateTime nowUtc();

  int monotonicMicroseconds();
}

abstract interface class IdGenerator {
  String nextId();
}

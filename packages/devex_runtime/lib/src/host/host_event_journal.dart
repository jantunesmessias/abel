import 'package:devex_contracts/devex_contracts.dart';

final class HostEvent {
  const HostEvent({
    required this.sequence,
    required this.method,
    required this.params,
  });

  final int sequence;
  final String method;
  final Map<String, Object?> params;

  JsonRpcNotification toNotification() => JsonRpcNotification(
    method: method,
    params: <String, Object?>{'sequence': sequence, ...params},
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'method': method,
    'params': params,
  };
}

final class HostEventJournal {
  HostEventJournal({this.capacity = 256}) {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity');
  }

  final int capacity;
  final List<HostEvent> _events = <HostEvent>[];
  var _nextSequence = 1;

  int get latestSequence => _nextSequence - 1;

  HostEvent append(String method, Map<String, Object?> params) {
    final event = HostEvent(
      sequence: _nextSequence,
      method: method,
      params: Map<String, Object?>.unmodifiable(params),
    );
    _nextSequence += 1;
    _events.add(event);
    if (_events.length > capacity) _events.removeAt(0);
    return event;
  }

  List<HostEvent> after(int cursor) {
    if (cursor < 0) throw ArgumentError.value(cursor, 'cursor');
    if (_events.isNotEmpty && cursor < _events.first.sequence - 1) {
      throw const HostCursorExpiredException();
    }
    return List<HostEvent>.unmodifiable(
      _events.where((event) => event.sequence > cursor),
    );
  }
}

final class HostCursorExpiredException implements Exception {
  const HostCursorExpiredException();
}

import 'package:devex_contracts/devex_contracts.dart';

abstract interface class RemoteSessionConnection {
  Stream<Object?> get messages;

  Future<void> get ready;

  void send(Object message);

  Future<void> close(int code, String reason);
}

typedef RemoteSessionConnectionFactory =
    RemoteSessionConnection Function(RemoteSessionGrant grant);

abstract interface class RemoteWebSessionBootstrapper {
  Future<Uri> bootstrap({
    required RemoteSessionGrant session,
    required String endpointPath,
    required String oneTimeGrant,
  });
}

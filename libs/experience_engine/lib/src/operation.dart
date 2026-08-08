import 'package:experience_contracts/experience_contracts.dart';

import 'ports.dart';

final class OperationContext {
  const OperationContext({
    required this.operationId,
    required this.correlationId,
    required this.deadline,
  });

  final String operationId;
  final String correlationId;
  final DateTime deadline;

  bool isExpired(Clock clock) => !clock.nowUtc().isBefore(deadline);
}

sealed class OperationResult<T extends Object?> {
  const OperationResult();
}

final class OperationSuccess<T extends Object?> extends OperationResult<T> {
  const OperationSuccess(this.value);

  final T value;
}

final class OperationFailure<T extends Object?> extends OperationResult<T> {
  const OperationFailure(this.failure);

  final PlatformFailure failure;
}

abstract interface class Command<T extends Object?> {
  String get operationName;
}

abstract interface class CommandHandler<
  C extends Command<T>,
  T extends Object?
> {
  Future<OperationResult<T>> handle(C command, OperationContext context);
}

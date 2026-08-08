import 'dart:io';

import 'package:hosted_control_plane/src/hosted_migration_runner.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final databaseUrl = Platform.environment['MIGRATION_DATABASE_URL'];
  if (databaseUrl == null || databaseUrl.isEmpty) {
    throw StateError('MIGRATION_DATABASE_URL is required');
  }
  final directory = Directory(
    Platform.environment['MIGRATION_DIRECTORY'] ?? '/app/migrations',
  );
  final database = Pool<String>.withUrl(databaseUrl);
  try {
    final result = await HostedMigrationRunner(database).apply(directory);
    stdout.writeln(
      'hosted migrations applied=${result.applied.length} '
      'existing=${result.alreadyApplied.length}',
    );
  } finally {
    await database.close();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';

final class HostedMigrationResult {
  const HostedMigrationResult({
    required this.applied,
    required this.alreadyApplied,
  });

  final List<String> applied;
  final List<String> alreadyApplied;
}

final class HostedMigrationRunner {
  const HostedMigrationRunner(this.database);

  final SessionExecutor database;

  Future<HostedMigrationResult> apply(Directory directory) async {
    if (!directory.existsSync()) {
      throw FileSystemException(
        'migration directory does not exist',
        directory.path,
      );
    }
    final files =
        directory
            .listSync(followLinks: false)
            .whereType<File>()
            .where(
              (file) =>
                  RegExp(r'/[0-9]{4}_[a-z0-9_]+\.sql$').hasMatch(file.path),
            )
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));
    if (files.isEmpty) throw StateError('no hosted migrations were found');
    return database.runTx(
      (session) async {
        await session.execute(
          "SELECT pg_advisory_xact_lock(hashtextextended('control-plane-migrations-v1', 0))",
        );
        await session.execute(r'''
          CREATE TABLE IF NOT EXISTS public.control_plane_schema_migrations (
            migration_id text PRIMARY KEY,
            content_sha256 text NOT NULL,
            applied_at timestamptz NOT NULL DEFAULT clock_timestamp(),
            CONSTRAINT control_plane_schema_migrations_digest_check
              CHECK (content_sha256 ~ '^[0-9a-f]{64}$')
          )
        ''');
        final rows = await session.execute(
          'SELECT migration_id, content_sha256 FROM public.control_plane_schema_migrations',
        );
        final known = <String, String>{
          for (final row in rows) row[0]! as String: row[1]! as String,
        };
        final applied = <String>[];
        final existing = <String>[];
        for (final file in files) {
          final id = file.uri.pathSegments.last;
          final bytes = file.readAsBytesSync();
          final digest = sha256.convert(bytes).toString();
          final previous = known[id];
          if (previous != null) {
            if (previous != digest) {
              throw StateError('applied migration $id was modified');
            }
            existing.add(id);
            continue;
          }
          final sql = utf8.decode(bytes);
          await session.execute(sql, queryMode: QueryMode.simple);
          await session.execute(
            Sql.named('''
              INSERT INTO public.control_plane_schema_migrations (
                migration_id, content_sha256
              ) VALUES (@id:text, @digest:text)
            '''),
            parameters: <String, Object?>{'id': id, 'digest': digest},
          );
          applied.add(id);
        }
        return HostedMigrationResult(
          applied: List<String>.unmodifiable(applied),
          alreadyApplied: List<String>.unmodifiable(existing),
        );
      },
      settings: TransactionSettings(
        isolationLevel: IsolationLevel.serializable,
        accessMode: AccessMode.readWrite,
      ),
    );
  }
}

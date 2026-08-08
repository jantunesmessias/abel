import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

void main() {
  const builtins = BuiltinModuleCatalog();

  test('round-trips a canonical plan and checks launch identity', () {
    final workspace = Directory.systemTemp.createTempSync('devex-plan-file-');
    addTearDown(() => workspace.deleteSync(recursive: true));
    final catalog = builtins.create(platform: 'linux-x64');
    final plan = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: 'journey-preview',
      configurationSchemas: builtins.configurationSchemas,
    );

    final path = const ResolvedKitPlanFile().write(
      workspaceRoot: workspace.path,
      runId: 'run-1',
      plan: plan,
    );
    final read = const ResolvedKitPlanFile().read(
      path: path,
      catalog: catalog,
      expectedDigest: plan.digest,
    );

    expect(read.digest, plan.digest);
    expect(File(path).readAsStringSync().endsWith('\n'), isFalse);
    expect(
      () => const ResolvedKitPlanFile().read(
        path: path,
        catalog: catalog,
        expectedDigest: Digest(
          'sha256:0000000000000000000000000000000000000000000000000000000000000000',
        ),
      ),
      throwsFormatException,
    );
  });
}

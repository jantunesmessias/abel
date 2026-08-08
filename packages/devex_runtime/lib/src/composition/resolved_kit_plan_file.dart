import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;

final class ResolvedKitPlanFile {
  const ResolvedKitPlanFile();

  String write({
    required String workspaceRoot,
    required String runId,
    required ResolvedKitPlan plan,
  }) {
    OpaqueId.validate(runId, 'Run');
    final root = Directory(workspaceRoot).absolute.resolveSymbolicLinksSync();
    final directory = Directory(
      p.join(root, '.dart_tool', 'devex', 'run', runId),
    )..createSync(recursive: true);
    final path = p.join(directory.path, 'resolved-kit-plan.json');
    if (Link(path).existsSync()) {
      throw FileSystemException('Resolved plan file cannot be a symlink', path);
    }
    final staging = File('$path.tmp-$pid');
    final canonical = const JcsCanonicalizer().canonicalize(plan.toJson());
    try {
      staging.writeAsStringSync(canonical, flush: true);
      staging.renameSync(path);
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
    return path;
  }

  ResolvedKitPlan read({
    required String path,
    required ModuleCatalog catalog,
    Digest? expectedDigest,
  }) {
    final file = File(path).absolute;
    if (Link(file.path).existsSync() || !file.existsSync()) {
      throw FileSystemException(
        'Resolved plan file not found or is a symlink',
        path,
      );
    }
    final bytes = file.readAsBytesSync();
    if (bytes.length > 4 * 1024 * 1024) {
      throw const FormatException('Resolved plan file exceeds 4 MiB');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    final plan = ResolvedKitPlan.fromJson(decoded);
    if (plan.distributionDigest != catalog.digest) {
      throw const FormatException(
        'Resolved plan distribution digest does not match this Host',
      );
    }
    if (expectedDigest != null && plan.digest != expectedDigest) {
      throw const FormatException('Resolved plan digest does not match launch');
    }
    final canonical = utf8.encode(
      const JcsCanonicalizer().canonicalize(plan.toJson()),
    );
    if (!_sameBytes(bytes, canonical)) {
      throw const FormatException('Resolved plan file must be canonical JCS');
    }
    return plan;
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

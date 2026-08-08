import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';

Future<void> main() async {
  final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  Process? target;
  try {
    upstream.listen((request) async {
      if (request.uri.path == '/allowlisted-probe') {
        request.response.statusCode = HttpStatus.noContent;
        request.response.headers.set('x-workspace-upstream', 'allowlisted');
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    target = await Process.start('unshare', <String>[
      '--net',
      '--',
      Platform.resolvedExecutable,
      'run',
      'libs/execution_runtime/tool/web_containment_target.dart',
    ]);
    final result = await _broker(
      target,
      upstream.port,
    ).timeout(const Duration(seconds: 25));
    final targetExit = await target.exitCode;
    final stderrText = await utf8.decoder.bind(target.stderr).join();
    final gatewayPassed = result['gatewayPassed'] == true;
    final egressPassed = result['egressPassed'] == true;
    final report = TargetContainmentReport(
      targetId: 'chromium-linux-netns',
      adapterId: 'linux-netns-stdio-gateway-v1',
      platform: 'web',
      executedAt: DateTime.now().toUtc(),
      networkContainment: gatewayPassed && egressPassed
          ? NetworkContainment.targetEnforced
          : NetworkContainment.gatewayOnly,
      probes: <ContainmentProbeResult>[
        ContainmentProbeResult(
          kind: ContainmentProbeKind.gatewayReachable,
          passed: gatewayPassed,
          detailCode: gatewayPassed
              ? 'allowlisted_passthrough_204'
              : 'gateway_unreachable',
        ),
        ContainmentProbeResult(
          kind: ContainmentProbeKind.directEgressDenied,
          passed: egressPassed,
          detailCode: egressPassed ? 'no_default_route' : 'egress_reachable',
        ),
      ],
    );
    stdout.writeln(const JcsCanonicalizer().canonicalize(report.toJson()));
    if (targetExit != 0 ||
        report.networkContainment != NetworkContainment.targetEnforced) {
      if (stderrText.isNotEmpty) stderr.writeln(stderrText.trim());
      stderr.writeln('Chromium containment probe failed closed.');
      exitCode = 1;
    }
  } finally {
    target?.kill(ProcessSignal.sigkill);
    await upstream.close(force: true);
  }
}

Future<Map<String, Object?>> _broker(Process target, int upstreamPort) async {
  Map<String, Object?>? finalResult;
  await for (final line
      in utf8.decoder.bind(target.stdout).transform(const LineSplitter())) {
    if (!line.trimLeft().startsWith('{')) continue;
    final message = jsonDecode(line) as Map<String, Object?>;
    switch (message['type']) {
      case 'gateway.request':
        final id = message['id']! as int;
        final path = message['path']! as String;
        if (path != '/allowlisted-probe') {
          target.stdin.writeln(
            jsonEncode(<String, Object?>{
              'type': 'gateway.response',
              'id': id,
              'status': HttpStatus.forbidden,
              'allowlisted': false,
            }),
          );
          continue;
        }
        final client = HttpClient()..findProxy = ((_) => 'DIRECT');
        try {
          final outbound = await client.getUrl(
            Uri.parse('http://127.0.0.1:$upstreamPort$path'),
          );
          final response = await outbound.close();
          await response.drain<void>();
          target.stdin.writeln(
            jsonEncode(<String, Object?>{
              'type': 'gateway.response',
              'id': id,
              'status': response.statusCode,
              'allowlisted':
                  response.headers.value('x-workspace-upstream') ==
                  'allowlisted',
            }),
          );
        } finally {
          client.close(force: true);
        }
      case 'result':
        finalResult = message;
      default:
        throw FormatException('Unknown containment child message');
    }
  }
  return finalResult ??
      (throw StateError('Containment target returned no result'));
}

import 'dart:async';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/host/studio_host_client.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Renders only bytes that a [StudioHostResourceClient] has validated.
///
/// Until verification completes, or when verification fails, this component
/// exposes an explicit accessible placeholder and never falls back to the raw
/// Host URL.
final class VerifiedArtifactImage extends StatefulComponent {
  const VerifiedArtifactImage({
    required this.handle,
    required this.client,
    required this.alt,
    required this.classes,
    this.loading = MediaLoading.lazy,
    super.key,
  });

  final ResourceHandle handle;
  final StudioHostResourceClient? client;
  final String alt;
  final String classes;
  final MediaLoading loading;

  @override
  State<VerifiedArtifactImage> createState() => _VerifiedArtifactImageState();
}

final class _VerifiedArtifactImageState extends State<VerifiedArtifactImage> {
  StudioResourceLease? _lease;
  Object? _failure;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateComponent(VerifiedArtifactImage oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.client != component.client ||
        oldComponent.handle.uri != component.handle.uri ||
        oldComponent.handle.digest != component.handle.digest ||
        oldComponent.handle.size != component.handle.size ||
        oldComponent.handle.mediaType != component.handle.mediaType) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _lease?.release();
    _lease = null;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final previous = _lease;
    _lease = null;
    previous?.release();
    _failure = null;
    final client = component.client;
    if (client == null) {
      if (mounted) setState(() => _failure = const _MissingResourceClient());
      return;
    }
    try {
      final lease = await client.openVisualArtifact(component.handle);
      if (!mounted || generation != _generation) {
        lease.release();
        return;
      }
      setState(() => _lease = lease);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _failure = error);
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final lease = _lease;
    if (lease != null) {
      return img(
        src: lease.uri.toString(),
        alt: component.alt,
        classes: component.classes,
        loading: component.loading,
        referrerPolicy: ReferrerPolicy.noReferrer,
      );
    }
    return div(
      classes: '${component.classes} verified-artifact-placeholder',
      attributes: <String, String>{
        'role': 'img',
        'aria-label': _failure == null
            ? '${component.alt}. Validando integridade da imagem.'
            : '${component.alt}. A imagem foi rejeitada na validação de integridade.',
        'data-resource-state': _failure == null ? 'validating' : 'rejected',
      },
      <Component>[
        span(classes: 'sr-only', <Component>[
          Component.text(
            _failure == null
                ? 'Validando imagem'
                : 'Imagem rejeitada por integridade',
          ),
        ]),
      ],
    );
  }
}

final class _MissingResourceClient implements Exception {
  const _MissingResourceClient();
}

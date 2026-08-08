import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:studio/src/host/studio_host_client.dart';

enum VerifiedArtifactImageStatus { loading, validated, rendered, rejected }

typedef VerifiedArtifactLeaseLoader = Future<StudioResourceLease> Function();
typedef VerifiedArtifactImageStatusListener =
    void Function(VerifiedArtifactImageStatus status);

/// Renders only bytes that a [StudioHostResourceClient] has validated.
///
/// Until verification completes, or when verification fails, this component
/// exposes an explicit accessible placeholder and never falls back to the raw
/// Host URL.
final class VerifiedArtifactImage extends StatefulComponent {
  const VerifiedArtifactImage({
    required ResourceHandle handle,
    required StudioHostResourceClient? client,
    required String alt,
    required String classes,
    MediaLoading loading = MediaLoading.lazy,
    VerifiedArtifactImageStatusListener? onStatusChanged,
    Key? key,
  }) : this._(
         handle: handle,
         client: client,
         resourceIdentity: null,
         leaseLoader: null,
         alt: alt,
         classes: classes,
         loading: loading,
         onStatusChanged: onStatusChanged,
         key: key,
       );

  /// Secure indirection used when a parent owns a private resource-handle
  /// vault. Only a stable digest and a validated lease loader cross into the
  /// renderer component.
  const VerifiedArtifactImage.secure({
    required Digest resourceIdentity,
    required VerifiedArtifactLeaseLoader leaseLoader,
    required String alt,
    required String classes,
    MediaLoading loading = MediaLoading.lazy,
    VerifiedArtifactImageStatusListener? onStatusChanged,
    Key? key,
  }) : this._(
         handle: null,
         client: null,
         resourceIdentity: resourceIdentity,
         leaseLoader: leaseLoader,
         alt: alt,
         classes: classes,
         loading: loading,
         onStatusChanged: onStatusChanged,
         key: key,
       );

  const VerifiedArtifactImage._({
    required this.handle,
    required this.client,
    required this._resourceIdentity,
    required this.leaseLoader,
    required this.alt,
    required this.classes,
    required this.loading,
    required this.onStatusChanged,
    super.key,
  });

  final ResourceHandle? handle;
  final StudioHostResourceClient? client;
  final Digest? _resourceIdentity;
  final VerifiedArtifactLeaseLoader? leaseLoader;
  final String alt;
  final String classes;
  final MediaLoading loading;
  final VerifiedArtifactImageStatusListener? onStatusChanged;

  Digest get resourceIdentity => _resourceIdentity ?? handle!.digest;

  @override
  State<VerifiedArtifactImage> createState() => _VerifiedArtifactImageState();
}

final class _VerifiedArtifactImageState extends State<VerifiedArtifactImage> {
  StudioResourceLease? _lease;
  Object? _failure;
  var _generation = 0;
  VerifiedArtifactImageStatus? _reportedStatus;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateComponent(VerifiedArtifactImage oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.client != component.client ||
        oldComponent.resourceIdentity != component.resourceIdentity ||
        oldComponent.handle?.uri != component.handle?.uri ||
        oldComponent.handle?.size != component.handle?.size ||
        oldComponent.handle?.mediaType != component.handle?.mediaType) {
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
    _reportedStatus = null;
    _report(VerifiedArtifactImageStatus.loading);
    final loader = component.leaseLoader;
    final client = component.client;
    final handle = component.handle;
    if (loader == null && (client == null || handle == null)) {
      if (mounted) setState(() => _failure = const _MissingResourceClient());
      _report(VerifiedArtifactImageStatus.rejected);
      return;
    }
    try {
      final lease =
          await (loader?.call() ?? client!.openVisualArtifact(handle!));
      if (!mounted || generation != _generation) {
        lease.release();
        return;
      }
      setState(() => _lease = lease);
      _report(VerifiedArtifactImageStatus.validated);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _failure = error);
        _report(VerifiedArtifactImageStatus.rejected);
      }
    }
  }

  void _report(VerifiedArtifactImageStatus status) {
    if (_reportedStatus == status) return;
    _reportedStatus = status;
    component.onStatusChanged?.call(status);
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
        events: <String, EventCallback>{
          'load': (_) => _report(VerifiedArtifactImageStatus.rendered),
          'error': (_) {
            final failedLease = _lease;
            _lease = null;
            failedLease?.release();
            if (mounted) {
              setState(() => _failure = const _ImageDecodeFailure());
              _report(VerifiedArtifactImageStatus.rejected);
            }
          },
        },
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

final class _ImageDecodeFailure implements Exception {
  const _ImageDecodeFailure();
}

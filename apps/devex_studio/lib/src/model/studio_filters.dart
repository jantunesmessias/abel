import 'package:devex_contracts/devex_contracts.dart';

/// Renderer-independent filters shared by Studio surfaces.
final class StudioFilters {
  const StudioFilters({
    this.query = '',
    this.applicationId,
    this.variantId,
    this.providerId,
    this.status,
    this.freshness,
    this.fidelity,
  });

  final String query;
  final String? applicationId;
  final VariantId? variantId;
  final ModuleId? providerId;
  final VisualEvidenceStatus? status;
  final EvidenceFreshness? freshness;
  final RuntimeFidelity? fidelity;

  bool get isEmpty =>
      query.isEmpty &&
      applicationId == null &&
      variantId == null &&
      providerId == null &&
      status == null &&
      freshness == null &&
      fidelity == null;

  StudioFilters copyWith({
    String? query,
    String? applicationId,
    VariantId? variantId,
    ModuleId? providerId,
    VisualEvidenceStatus? status,
    EvidenceFreshness? freshness,
    RuntimeFidelity? fidelity,
    bool clearApplication = false,
    bool clearVariant = false,
    bool clearProvider = false,
    bool clearStatus = false,
    bool clearFreshness = false,
    bool clearFidelity = false,
  }) => StudioFilters(
    query: query ?? this.query,
    applicationId: clearApplication
        ? null
        : applicationId ?? this.applicationId,
    variantId: clearVariant ? null : variantId ?? this.variantId,
    providerId: clearProvider ? null : providerId ?? this.providerId,
    status: clearStatus ? null : status ?? this.status,
    freshness: clearFreshness ? null : freshness ?? this.freshness,
    fidelity: clearFidelity ? null : fidelity ?? this.fidelity,
  );
}

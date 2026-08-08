import 'package:devex_contracts/devex_contracts.dart';

/// Renderer-independent state for the catalog surface.
sealed class CatalogViewState {
  const CatalogViewState();
}

final class CatalogLoading extends CatalogViewState {
  const CatalogLoading();
}

final class CatalogEmpty extends CatalogViewState {
  const CatalogEmpty();
}

final class CatalogFailure extends CatalogViewState {
  const CatalogFailure(this.message);

  final String message;
}

final class CatalogContent extends CatalogViewState {
  const CatalogContent({
    required this.manifest,
    this.isRefreshing = false,
    this.isStale = false,
  });

  final CatalogManifest manifest;
  final bool isRefreshing;
  final bool isStale;

  CatalogContent copyWith({bool? isRefreshing, bool? isStale}) =>
      CatalogContent(
        manifest: manifest,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        isStale: isStale ?? this.isStale,
      );
}

import 'package:devex_contracts/devex_contracts.dart';

abstract interface class CatalogRepository {
  Future<CatalogManifest> loadCatalog();
}

final class InMemoryCatalogRepository implements CatalogRepository {
  InMemoryCatalogRepository(this.manifest, {this.delay = Duration.zero});

  final CatalogManifest manifest;
  final Duration delay;

  @override
  Future<CatalogManifest> loadCatalog() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return manifest;
  }
}

final class UnavailableCatalogRepository implements CatalogRepository {
  const UnavailableCatalogRepository();

  @override
  Future<Never> loadCatalog() => Future<Never>.error(
    StateError('CatalogRepository was not provided by the DevEx Host'),
  );
}

/// Host-facing repository seam. Transport and protocol remain outside widgets.
final class HostCatalogRepository implements CatalogRepository {
  const HostCatalogRepository(this.fetchManifest);

  final Future<CatalogManifest> Function() fetchManifest;

  @override
  Future<CatalogManifest> loadCatalog() => fetchManifest();
}

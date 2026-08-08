enum StudioMode { review, authoring }

enum StudioGrant { viewCatalog, comment, authorCatalog, approve }

final class StudioAccess {
  StudioAccess({required this.mode, required Set<StudioGrant> grants})
    : grants = Set<StudioGrant>.unmodifiable(grants) {
    if (!this.grants.contains(StudioGrant.viewCatalog)) {
      throw ArgumentError('Every Studio context requires viewCatalog');
    }
    if (mode == StudioMode.review &&
        this.grants.contains(StudioGrant.authorCatalog)) {
      throw ArgumentError('Review mode must not receive authorCatalog');
    }
  }

  static final StudioAccess review = StudioAccess(
    mode: StudioMode.review,
    grants: <StudioGrant>{StudioGrant.viewCatalog, StudioGrant.comment},
  );

  static final StudioAccess authoring = StudioAccess(
    mode: StudioMode.authoring,
    grants: <StudioGrant>{StudioGrant.viewCatalog, StudioGrant.authorCatalog},
  );

  final StudioMode mode;
  final Set<StudioGrant> grants;

  bool allows(StudioGrant grant) => grants.contains(grant);
}

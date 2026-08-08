import 'package:studio/src/access/studio_access.dart';
import 'package:test/test.dart';

void main() {
  test('Review and Authoring share content but never authoring grants', () {
    expect(StudioAccess.review.allows(StudioGrant.viewCatalog), isTrue);
    expect(StudioAccess.authoring.allows(StudioGrant.viewCatalog), isTrue);
    expect(StudioAccess.review.allows(StudioGrant.authorCatalog), isFalse);
    expect(StudioAccess.authoring.allows(StudioGrant.authorCatalog), isTrue);
    expect(
      () => StudioAccess(
        mode: StudioMode.review,
        grants: <StudioGrant>{
          StudioGrant.viewCatalog,
          StudioGrant.authorCatalog,
        },
      ),
      throwsArgumentError,
    );
  });
}

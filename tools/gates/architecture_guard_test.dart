import 'package:test/test.dart';

import 'architecture_guard.dart';

void main() {
  const fragment = 'package:experience_engine/';

  test('allows only the public Engine barrel in the authoring slice', () {
    expect(
      isForbiddenArchitectureFragment(
        root: 'apps/studio/lib',
        filePath:
            'apps/studio/lib/src/authoring/experience_authoring_controller.dart',
        source: "import 'package:experience_engine/experience_engine.dart';",
        fragment: fragment,
      ),
      isFalse,
    );
  });

  test('keeps Engine forbidden outside the authoring slice', () {
    expect(
      isForbiddenArchitectureFragment(
        root: 'apps/studio/lib',
        filePath: 'apps/studio/lib/src/controllers/example.dart',
        source: "import 'package:experience_engine/experience_engine.dart';",
        fragment: fragment,
      ),
      isTrue,
    );
  });

  test('keeps Engine subpaths forbidden inside the authoring slice', () {
    expect(
      isForbiddenArchitectureFragment(
        root: 'apps/studio/lib',
        filePath: 'apps/studio/lib/src/authoring/example.dart',
        source:
            "import 'package:experience_engine/src/authoring/layout_draft_engine.dart';",
        fragment: fragment,
      ),
      isTrue,
    );
  });
}

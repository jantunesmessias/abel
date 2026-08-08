import 'dart:async';

import 'package:web/web.dart' as web;

void revealJourneyScenario(String elementId) {
  scheduleMicrotask(() {
    final element = web.document.getElementById(elementId);
    if (element == null) return;
    element.scrollIntoView(
      web.ScrollIntoViewOptions(
        behavior: 'instant',
        block: 'nearest',
        inline: 'center',
      ),
    );
  });
}

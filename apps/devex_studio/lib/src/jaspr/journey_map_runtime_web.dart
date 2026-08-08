import 'dart:async';

import 'package:web/web.dart' as web;

/// Reveals a deep-linked Scenario after Jaspr commits the updated DOM.
///
/// The map remains an ordered horizontal flow; this only moves its bounded
/// viewport so a selected node never opens off-screen.
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

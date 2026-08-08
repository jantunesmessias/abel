import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

final Map<String, web.HTMLElement?> _modalTriggers =
    <String, web.HTMLElement?>{};

void activateModal(String id) {
  scheduleMicrotask(() {
    final element = web.document.getElementById(id);
    if (element == null || !element.isA<web.HTMLDialogElement>()) return;
    final dialog = element as web.HTMLDialogElement;
    if (dialog.open) return;
    final activeElement = web.document.activeElement;
    _modalTriggers[id] = activeElement?.isA<web.HTMLElement>() == true
        ? activeElement as web.HTMLElement
        : null;
    dialog.showModal();
    final autofocus = dialog.querySelector('[autofocus]');
    if (autofocus?.isA<web.HTMLElement>() == true) {
      (autofocus! as web.HTMLElement).focus();
    }
  });
}

void restoreModalFocus(String id) {
  final trigger = _modalTriggers.remove(id);
  scheduleMicrotask(() {
    if (trigger?.isConnected == true) trigger!.focus();
  });
}

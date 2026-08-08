import 'package:flutter/widgets.dart';

/// Stable runtime selector. Visible text and widget keys are not automation
/// contracts.
final class DevExSemantics extends StatelessWidget {
  const DevExSemantics({
    required this.identifier,
    required this.child,
    this.label,
    this.button,
    super.key,
  });

  final String identifier;
  final String? label;
  final bool? button;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: identifier,
    label: label,
    button: button,
    child: child,
  );
}

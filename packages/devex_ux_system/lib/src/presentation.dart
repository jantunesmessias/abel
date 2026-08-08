/// Semantic tone shared by UX policy and every concrete UI renderer.
///
/// Features choose meaning here; renderers only map that meaning to visual
/// tokens. Keeping this vocabulary in the pure UX package prevents each UI
/// surface from inventing an incompatible status language.
enum DevExTone { neutral, accent, info, positive, warning, critical }

enum DevExEmphasis { quiet, subtle, strong }

enum DevExDisclosureLevel { overview, detail, technical }

enum DevExFeedbackKind { inline, transient, blocking }

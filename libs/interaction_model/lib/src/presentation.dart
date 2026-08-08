/// Semantic tone shared by UX policy and every concrete UI renderer.
///
/// Features choose meaning here; renderers only map that meaning to visual
/// tokens. Keeping this vocabulary in the pure UX package prevents each UI
/// surface from inventing an incompatible status language.
enum PresentationTone { neutral, accent, info, positive, warning, critical }

enum PresentationEmphasis { quiet, subtle, strong }

enum DisclosureLevel { overview, detail, technical }

enum FeedbackKind { inline, transient, blocking }

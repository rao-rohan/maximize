/// Namespace for package-level metadata.
///
/// The package is intentionally near-empty at this point: its purpose right now is
/// to establish the build-and-test pipeline that every later ticket depends on.
/// Domain types arrive with the PRD-derived tickets.
public enum MaximizeCore {
    /// Semantic version of the core package, surfaced in diagnostics and support logs.
    public static let version = "0.0.1"
}

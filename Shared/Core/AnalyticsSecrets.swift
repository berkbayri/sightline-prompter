/// Secrets that must not live in the public repository.
/// The committed file ships an empty value, which keeps Google Analytics silent. On the release machine the value
/// is filled in locally and the file is marked `git update-index --skip-worktree`, so it is never committed.
enum AnalyticsSecrets {
    static let gaAPISecret = ""
}

import Foundation

/// Reads CHANGELOG.md: a `## <version>` heading per release, newest first, with `- ` bullets that may wrap onto
/// indented lines. Anything else, such as the title and intro, is ignored.
public struct Changelog: Sendable, Equatable {
    public struct Release: Sendable, Equatable {
        public let version: String
        public let changes: [String]
    }

    public let releases: [Release]

    public init(markdown: String) {
        var releases: [Release] = []
        var version: String?
        var changes: [String] = []

        func finishRelease() {
            if let version { releases.append(Release(version: version, changes: changes)) }
            changes = []
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                finishRelease()
                version = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if version != nil, trimmed.hasPrefix("- ") {
                changes.append(String(trimmed.dropFirst(2)))
            } else if version != nil, !trimmed.isEmpty, line.first == " ", let last = changes.popLast() {
                changes.append(last + " " + trimmed)
            }
        }
        finishRelease()
        self.releases = releases
    }

    public func release(_ version: String) -> Release? {
        releases.first { $0.version == version }
    }
}

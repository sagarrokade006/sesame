import Testing
@testable import SesameCore

@Suite struct ChangelogTests {
    private let sample = """
    # Changelog

    Intro text that isn't a release.

    ## 1.0.1

    - First change.
    - A change that wraps
      onto a second line.

    ## 1.0.0

    - First public release.
    """

    @Test func readsReleasesNewestFirst() {
        let log = Changelog(markdown: sample)
        #expect(log.releases.map(\.version) == ["1.0.1", "1.0.0"])
    }

    @Test func joinsWrappedBullets() {
        let log = Changelog(markdown: sample)
        #expect(log.release("1.0.1")?.changes == ["First change.", "A change that wraps onto a second line."])
    }

    @Test func unknownVersionIsNil() {
        #expect(Changelog(markdown: sample).release("9.9.9") == nil)
    }

    @Test func ignoresTextBeforeTheFirstRelease() {
        #expect(Changelog(markdown: "# Title\n- not a change\n").releases.isEmpty)
    }
}

import Testing

@testable import SchneeGlassPresentation

@Test
func filterSessionRequestsFocusOnlyOnExplicitSupportedOpen() {
  var session = DesktopGlassFilterSession()
  session.open(ifSupported: false)
  #expect(!session.isVisible)
  let unsupportedFocus = session.consumeFocusRequest()
  #expect(!unsupportedFocus)

  session.open(ifSupported: true)
  #expect(session.isVisible)
  let initialFocus = session.consumeFocusRequest()
  #expect(initialFocus)
  session.open(ifSupported: true)
  let repeatedFocus = session.consumeFocusRequest()
  #expect(!repeatedFocus)
}

@Test
func filterSessionRefreshPreservesFiltersWithoutRestoringFocus() {
  var session = DesktopGlassFilterSession()
  session.open(ifSupported: true)
  session.query = "資料"
  session.kind = .folders
  session.discardFocusRequest()

  let restoredFocus = session.consumeFocusRequest()
  #expect(!restoredFocus)
  #expect(session.isVisible)
  #expect(session.effectiveQuery == "資料")
  #expect(session.effectiveKind == .folders)
}

@Test
func closingFilterResetsBothCriteriaAndPendingFocus() {
  var session = DesktopGlassFilterSession()
  session.open(ifSupported: true)
  session.query = "report"
  session.kind = .files
  session.close()

  #expect(!session.isVisible)
  #expect(session.query.isEmpty)
  #expect(session.kind == .all)
  #expect(session.effectiveQuery.isEmpty)
  #expect(session.effectiveKind == .all)
  let closedFocus = session.consumeFocusRequest()
  #expect(!closedFocus)

  session.open(ifSupported: true)
  let reopenedFocus = session.consumeFocusRequest()
  #expect(reopenedFocus)
  #expect(session.effectiveQuery.isEmpty)
  #expect(session.effectiveKind == .all)
}

@Test
func separateGlassFilterSessionsDoNotShareState() {
  var first = DesktopGlassFilterSession()
  var second = DesktopGlassFilterSession()
  first.open(ifSupported: true)
  second.open(ifSupported: true)
  first.query = "one"
  second.kind = .links
  first.close()

  #expect(second.isVisible)
  #expect(second.effectiveQuery.isEmpty)
  #expect(second.effectiveKind == .links)
  let secondFocus = second.consumeFocusRequest()
  #expect(secondFocus)
}

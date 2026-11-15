import SchneeGlassDomain
import Testing

@testable import SchneeGlassMacOSAdapter

@Test
func individualVisibilityKeepsOtherPanelsAndNewGlassesVisible() {
  let a = GlassID()
  let b = GlassID()
  let new = GlassID()
  var state = DesktopGlassVisibilityState()
  #expect(state.setVisible(false, for: a, currentIDs: [a, b]))
  #expect(!state.presentsPanel(for: a))
  #expect(state.presentsPanel(for: b))
  #expect(state.presentsPanel(for: new))
  #expect(state.setVisible(true, for: a, currentIDs: [a, b]))
  #expect(state.presentsPanel(for: a))
}

@Test
func individualShowAfterHideAllOnlyShowsSelectedGlass() {
  let a = GlassID()
  let b = GlassID()
  let new = GlassID()
  var state = DesktopGlassVisibilityState()
  state.hideAll()
  #expect(!state.presentsPanel(for: a))
  #expect(!state.presentsPanel(for: new))
  #expect(state.setVisible(true, for: a, currentIDs: [a, b]))
  #expect(state.presentsPanel(for: a))
  #expect(!state.presentsPanel(for: b))
  #expect(state.presentsPanel(for: new))
}

@Test
func visibilityCommandsRejectRemovedGlassAndDiscardStaleHiddenIDs() {
  let a = GlassID()
  let b = GlassID()
  var state = DesktopGlassVisibilityState()
  #expect(state.setVisible(false, for: a, currentIDs: [a, b]))
  #expect(!state.setVisible(true, for: a, currentIDs: [b]))
  #expect(!state.presentsPanel(for: a))
  state.retainGlasses([b])
  #expect(state.presentsPanel(for: a))
  #expect(state.presentsPanel(for: b))
}

@Test
func globalShowRescuesIndividuallyHiddenPanelsAndGlobalToggleUsesVisibleSet() {
  let a = GlassID()
  let b = GlassID()
  var state = DesktopGlassVisibilityState()
  #expect(!state.shouldShowAllOnToggle(presentableIDs: []))
  #expect(!state.shouldShowAllOnToggle(presentableIDs: [a, b]))
  state.setVisible(false, for: a, currentIDs: [a, b])
  #expect(!state.shouldShowAllOnToggle(presentableIDs: [a, b]))
  state.setVisible(false, for: b, currentIDs: [a, b])
  #expect(state.shouldShowAllOnToggle(presentableIDs: [a, b]))
  state.showAll()
  #expect(state.presentsPanel(for: a))
  #expect(state.presentsPanel(for: b))
  state.hideAll()
  #expect(state.shouldShowAllOnToggle(presentableIDs: [a, b]))
  #expect(!state.shouldShowAllOnToggle(presentableIDs: []))
  state.showAll()
  #expect(state.presentsPanel(for: a))
  #expect(state.presentsPanel(for: b))
}

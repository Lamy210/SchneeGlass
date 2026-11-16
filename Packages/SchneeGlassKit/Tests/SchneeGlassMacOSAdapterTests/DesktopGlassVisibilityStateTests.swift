import SchneeGlassDomain
import Testing

@testable import SchneeGlassMacOSAdapter

@Test
func individualVisibilityKeepsOtherPanelsAndNewGlassesVisible() {
  let a = GlassID()
  let b = GlassID()
  let new = GlassID()
  var state = DesktopGlassVisibilityState()
  let changed1 = state.setVisible(false, for: a, currentIDs: [a, b])
  #expect(changed1)
  #expect(!state.presentsPanel(for: a))
  #expect(state.presentsPanel(for: b))
  #expect(state.presentsPanel(for: new))
  let changed2 = state.setVisible(true, for: a, currentIDs: [a, b])
  #expect(changed2)
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
  let changed3 = state.setVisible(true, for: a, currentIDs: [a, b])
  #expect(changed3)
  #expect(state.presentsPanel(for: a))
  #expect(!state.presentsPanel(for: b))
  #expect(state.presentsPanel(for: new))
}

@Test
func visibilityCommandsRejectRemovedGlassAndDiscardStaleHiddenIDs() {
  let a = GlassID()
  let b = GlassID()
  var state = DesktopGlassVisibilityState()
  let changed4 = state.setVisible(false, for: a, currentIDs: [a, b])
  #expect(changed4)
  let changed5 = state.setVisible(true, for: a, currentIDs: [b])
  #expect(!changed5)
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

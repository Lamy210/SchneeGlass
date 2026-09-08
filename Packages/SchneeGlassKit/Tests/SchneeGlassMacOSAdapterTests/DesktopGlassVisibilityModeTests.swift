@testable import SchneeGlassMacOSAdapter
import Testing

@Test
func visibilityToggleHidesShownGlasses() {
    #expect(
        DesktopGlassVisibilityMode.shown.toggled(hasGlasses: true) == .hidden
    )
}

@Test
func visibilityToggleShowsHiddenGlasses() {
    #expect(
        DesktopGlassVisibilityMode.hidden.toggled(hasGlasses: true) == .shown
    )
}

@Test
func visibilityToggleDoesNothingWithoutGlasses() {
    #expect(
        DesktopGlassVisibilityMode.shown.toggled(hasGlasses: false) == .shown
    )
    #expect(
        DesktopGlassVisibilityMode.hidden.toggled(hasGlasses: false) == .hidden
    )
}

@Test
func visibilityModeControlsWhetherNewPanelsShouldBePresented() {
    #expect(DesktopGlassVisibilityMode.shown.presentsPanels)
    #expect(!DesktopGlassVisibilityMode.hidden.presentsPanels)
}

import Testing

@testable import SchneeGlassPresentation

@Test
func compactDesktopFileGridDensityUsesSmallerLayoutMetrics() {
  #expect(
    DesktopGlassFileGridDensity.compact.minimumTileWidth
      < DesktopGlassFileGridDensity.comfortable.minimumTileWidth
  )
  #expect(
    DesktopGlassFileGridDensity.compact.maximumTileWidth
      < DesktopGlassFileGridDensity.comfortable.maximumTileWidth
  )
  #expect(
    DesktopGlassFileGridDensity.compact.rowSpacing
      < DesktopGlassFileGridDensity.comfortable.rowSpacing
  )
  #expect(
    DesktopGlassFileGridDensity.compact.columnSpacing
      < DesktopGlassFileGridDensity.comfortable.columnSpacing
  )
}

@Test
func comfortableDesktopFileGridDensityMatchesExistingDesktopMetrics() {
  #expect(DesktopGlassFileGridDensity.comfortable.minimumTileWidth == 74)
  #expect(DesktopGlassFileGridDensity.comfortable.maximumTileWidth == 92)
  #expect(DesktopGlassFileGridDensity.comfortable.rowSpacing == 12)
  #expect(DesktopGlassFileGridDensity.comfortable.columnSpacing == 10)
}

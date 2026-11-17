import SwiftUI
import Testing

@testable import SchneeGlassPresentation

@Test
func fileTileUnmodifiedActivationOpensOncePerKeyDown() {
  for key in [KeyEquivalent.return, .space] {
    #expect(GlassFileTileKeyPolicy.action(key: key, phase: .down, modifiers: []) == .open)
    #expect(GlassFileTileKeyPolicy.action(key: key, phase: .repeat, modifiers: []) == .consume)
    #expect(GlassFileTileKeyPolicy.action(key: key, phase: .up, modifiers: []) == .ignore)
  }
}

@Test
func fileTileLeavesNavigationAndModifierShortcutsAlone() {
  for key in [KeyEquivalent.tab, .escape, .upArrow, .downArrow] {
    #expect(GlassFileTileKeyPolicy.action(key: key, phase: .down, modifiers: []) == .ignore)
  }
  for modifiers in [EventModifiers.command, .shift, .option, .control] {
    #expect(
      GlassFileTileKeyPolicy.action(key: .return, phase: .down, modifiers: modifiers) == .ignore
    )
    #expect(
      GlassFileTileKeyPolicy.action(key: .space, phase: .repeat, modifiers: modifiers) == .ignore
    )
  }
}

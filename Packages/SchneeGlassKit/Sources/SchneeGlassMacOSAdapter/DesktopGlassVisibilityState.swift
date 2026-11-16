import SchneeGlassDomain

/// Session-local panel presentation only; never grants filesystem access.
public struct DesktopGlassVisibilityState: Sendable {
  private var hidesAll = false
  private var individuallyHidden: Set<GlassID> = []

  public init() {}

  public func presentsPanel(for id: GlassID) -> Bool {
    !hidesAll && !individuallyHidden.contains(id)
  }

  public mutating func showAll() {
    hidesAll = false
    individuallyHidden.removeAll()
  }

  public mutating func hideAll() {
    hidesAll = true
    individuallyHidden.removeAll()
  }

  public mutating func retainGlasses(_ currentIDs: Set<GlassID>) {
    individuallyHidden.formIntersection(currentIDs)
  }

  public func shouldShowAllOnToggle(presentableIDs: Set<GlassID>) -> Bool {
    !presentableIDs.isEmpty && !presentableIDs.contains { presentsPanel(for: $0) }
  }

  /// Explicit commands, rather than toggles based on potentially stale menu state.
  @discardableResult
  public mutating func setVisible(
    _ visible: Bool,
    for id: GlassID,
    currentIDs: Set<GlassID>
  ) -> Bool {
    guard currentIDs.contains(id) else {
      return false
    }
    retainGlasses(currentIDs)
    if visible {
      if hidesAll {
        // Exit global hide without making every other existing panel visible.
        hidesAll = false
        individuallyHidden = currentIDs
      }
      individuallyHidden.remove(id)
    } else if !hidesAll {
      individuallyHidden.insert(id)
    }
    return true
  }
}

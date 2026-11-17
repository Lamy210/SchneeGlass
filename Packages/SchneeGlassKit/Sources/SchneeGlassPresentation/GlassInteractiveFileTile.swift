import FileDomain
import SchneeGlassDesignSystem
import SwiftUI

// Both file surfaces must address the exact displayed item, never its index
// or name. Keep existing double-click / context-menu behavior while adding
// keyboard and assistive-technology activation.
struct GlassInteractiveFileTile: View {
  let item: GlassItem
  let onOpen: (GlassItem) -> Void
  let onReveal: (GlassItem) -> Void
  var displayMode: GlassFileDisplayMode = .grid

  var body: some View {
    let presentation = GlassItemPresentation.make(for: item)
    tileLabel(presentation)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      onOpen(item)
    }
    .contextMenu {
      Button("Open") {
        onOpen(item)
      }
      Button("Reveal in Finder") {
        onReveal(item)
      }
    }
    .focusable(interactions: .activate)
    .onKeyPress(keys: [.return, .space], phases: [.down, .repeat]) { press in
      switch GlassFileTileKeyPolicy.action(
        key: press.key, phase: press.phase, modifiers: press.modifiers
      ) {
      case .open:
        onOpen(item)
        return .handled
      case .consume:
        return .handled
      case .ignore:
        return .ignored
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.accessibilityLabel)
    .accessibilityHint("Opens the item")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      onOpen(item)
    }
    .accessibilityAction(named: Text("Reveal in Finder")) {
      onReveal(item)
    }
  }

  @ViewBuilder
  private func tileLabel(_ presentation: GlassItemPresentation) -> some View {
    switch displayMode {
    case .grid:
      SchneeGlassFileTile(systemImage: presentation.systemImage, title: item.displayName)
    case .list:
      HStack(spacing: SchneeGlassSpacing.controlGroup) {
        Image(systemName: presentation.systemImage)
          .font(SchneeGlassTypography.largeSymbol)
          .foregroundStyle(.primary)
          .frame(width: SchneeGlassMetrics.fileIconHeight)
          .accessibilityHidden(true)
        Text(item.displayName)
          .font(SchneeGlassTypography.body)
          .lineLimit(2)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(minHeight: SchneeGlassMetrics.minimumControlHitTarget)
      .padding(.vertical, SchneeGlassSpacing.compactContent)
    }
  }
}

enum GlassFileTileKeyPolicy {
  enum Action: Equatable {
    case open
    case consume
    case ignore
  }

  static func action(
    key: KeyEquivalent, phase: KeyPress.Phases, modifiers: EventModifiers
  ) -> Action {
    guard modifiers.isEmpty, key == .return || key == .space else {
      return .ignore
    }
    switch phase {
    case .down: return .open
    case .repeat: return .consume
    default: return .ignore
    }
  }
}

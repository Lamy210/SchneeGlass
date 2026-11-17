import SchneeGlassDomain
import Testing

@testable import SchneeGlassPresentation

@Test
func glassMenuLabelsPreserveUniqueTitlesAndHandleEmptyInput() {
  let projects = menuLabelEntry("Projects")
  let archive = menuLabelEntry("資料")
  #expect(GlassMenuLabels.make(for: []).isEmpty)
  let labels = GlassMenuLabels.make(for: [projects, archive])
  #expect(labels[projects.id] == "Projects")
  #expect(labels[archive.id] == "資料")
}

@Test
func glassMenuLabelsDisambiguateDuplicatesInConfigurationOrder() {
  let first = menuLabelEntry("Projects")
  let second = menuLabelEntry("Projects")
  let other = menuLabelEntry("Archive")
  let entries = [first, other, second]
  let labels = GlassMenuLabels.make(for: entries)
  #expect(labels[first.id] == "Projects (1 of 2)")
  #expect(labels[second.id] == "Projects (2 of 2)")
  #expect(labels[other.id] == "Archive")
  #expect(GlassMenuLabels.make(for: entries) == labels)

  let remaining = GlassMenuLabels.make(for: [other, second])
  #expect(remaining[second.id] == "Projects")
  #expect(remaining[first.id] == nil)
}

@Test
func glassMenuLabelsNeverCollideWithActualTitlesOrFallbackTitles() {
  let first = menuLabelEntry("Projects")
  let second = menuLabelEntry("Projects")
  let actual = menuLabelEntry("Projects (1 of 2)")
  let fallback = menuLabelEntry("Projects (1 of 2) [2]")
  let entries = [first, second, actual, fallback]
  let labels = GlassMenuLabels.make(for: entries)
  #expect(labels[first.id] == "Projects (1 of 2) [3]")
  #expect(labels[second.id] == "Projects (2 of 2)")
  #expect(labels[actual.id] == actual.title)
  #expect(labels[fallback.id] == fallback.title)
  #expect(labels.count == entries.count)
  #expect(Set(labels.values).count == entries.count)
}

private func menuLabelEntry(_ title: String) -> GlassWorkspaceEntry {
  GlassWorkspaceEntry(id: GlassID(), title: title, contentState: .loading)
}

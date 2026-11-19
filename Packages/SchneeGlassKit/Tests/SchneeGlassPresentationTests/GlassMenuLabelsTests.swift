import Foundation
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

@Test
func localizedMenuLabelsPreserveOriginalTitlesAndDisambiguateJapaneseCollisions() {
  let ja = Locale(identifier: "ja_JP")
  let title = "資料 %1$@"
  let first = menuLabelEntry(title)
  let second = menuLabelEntry(title)
  let actual = menuLabelEntry(title + "（全2件中1件目）")
  let fallback = menuLabelEntry(actual.title + " [2]")
  let entries = [first, second, actual, fallback]
  let labels = GlassMenuLabels.make(for: entries, locale: ja)
  #expect(labels[first.id] == actual.title + " [3]")
  #expect(labels[second.id] == title + "（全2件中2件目）")
  #expect(labels[actual.id] == actual.title)
  #expect(labels[fallback.id] == fallback.title)
  #expect(labels.count == entries.count)
  #expect(Set(labels.values).count == entries.count)
  #expect(GlassMenuLabels.make(for: entries, locale: ja) == labels)

  let remaining = GlassMenuLabels.make(for: [second], locale: ja)
  #expect(remaining[second.id] == title)
}

@Test
func localizedMenuLabelsKeepLegacyEnglishAndUnsupportedLocaleFallback() {
  let first = menuLabelEntry("Projects")
  let second = menuLabelEntry("Projects")
  let entries = [first, second]
  let english = GlassMenuLabels.make(for: entries)
  #expect(english[first.id] == "Projects (1 of 2)")
  #expect(GlassMenuLabels.make(for: entries, locale: Locale(identifier: "en_US")) == english)
  #expect(GlassMenuLabels.make(for: entries, locale: Locale(identifier: "fr_FR")) == english)
}

private func menuLabelEntry(_ title: String) -> GlassWorkspaceEntry {
  GlassWorkspaceEntry(id: GlassID(), title: title, contentState: .loading)
}

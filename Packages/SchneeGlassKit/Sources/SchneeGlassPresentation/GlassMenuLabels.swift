import Foundation
import SchneeGlassDomain

/// Menu labels are presentation-only; all commands still target the original Glass ID.
public enum GlassMenuLabels {
  public static func make(for entries: [GlassWorkspaceEntry]) -> [GlassID: String] {
    make(for: entries, locale: Locale(identifier: "en"))
  }

  public static func make(
    for entries: [GlassWorkspaceEntry], locale: Locale
  ) -> [GlassID: String] {
    var counts: [String: Int] = [:]
    for entry in entries {
      counts[entry.title, default: 0] += 1
    }

    // Reserve every actual title so a generated label cannot impersonate another Glass.
    var reserved = Set(counts.keys)
    var occurrences: [String: Int] = [:]
    var labels: [GlassID: String] = [:]
    for entry in entries {
      let title = entry.title
      let count = counts[title, default: 0]
      guard count > 1 else {
        labels[entry.id] = title
        continue
      }

      occurrences[title, default: 0] += 1
      let ordinal = occurrences[title, default: 0]
      let format = GlassLocalizedText.menuDuplicateTitle.resolve(locale: locale)
      let base = String(format: format, locale: locale, title, String(ordinal), String(count))
      var label = base
      var suffix = 2
      while !reserved.insert(label).inserted {
        label = "\(base) [\(suffix)]"
        suffix += 1
      }
      labels[entry.id] = label
    }
    return labels
  }
}

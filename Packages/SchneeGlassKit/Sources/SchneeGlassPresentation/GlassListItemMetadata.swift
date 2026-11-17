import FileDomain
import Foundation

/// Display only metadata already present in the observed snapshot.
/// Directory, package and link sizes must never imply a recursive or target size.
struct GlassListItemMetadata: Equatable {
  let size: String?
  let modified: String?

  static func make(for item: GlassItem) -> Self {
    let size: String?
    if item.kind == .regular, let count = item.fileSize, count >= 0 {
      size = ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    } else {
      size = nil
    }
    return Self(
      size: size,
      modified: item.modificationDate?.formatted(date: .abbreviated, time: .shortened)
    )
  }

  var displayText: String? {
    let parts = [size, modified].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  var accessibilityText: String {
    var parts: [String] = []
    if let size {
      parts.append("Size: \(size)")
    }
    if let modified {
      parts.append("Modified: \(modified)")
    }
    return parts.joined(separator: ", ")
  }
}

import SchneeGlassDesignSystem
import SwiftUI

public enum DesktopGlassFileGridDensity: String, CaseIterable, Sendable {
  case comfortable
  case compact

  var minimumTileWidth: CGFloat {
    switch self {
    case .comfortable:
      SchneeGlassMetrics.desktopFileTileMinimumWidth
    case .compact:
      58
    }
  }

  var maximumTileWidth: CGFloat {
    switch self {
    case .comfortable:
      SchneeGlassMetrics.fileTileMaximumWidth
    case .compact:
      76
    }
  }

  var rowSpacing: CGFloat {
    switch self {
    case .comfortable:
      SchneeGlassSpacing.fileGrid
    case .compact:
      8
    }
  }

  var columnSpacing: CGFloat {
    switch self {
    case .comfortable:
      SchneeGlassSpacing.fileGridColumn
    case .compact:
      8
    }
  }
}

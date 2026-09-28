import Foundation

public enum DesktopGlassOpacityPreset: Double, CaseIterable, Sendable {
  case full = 1.0
  case ninety = 0.9
  case eighty = 0.8
  case seventy = 0.7

  public var percentageLabel: String {
    "\(Int((rawValue * 100).rounded()))%"
  }
}

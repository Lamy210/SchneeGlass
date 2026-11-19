import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedDropApprovalPreservesCopiesAndOriginalFilenames() throws {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  let single = try localizedDropApprovalPlan(names: ["100%_設計.pdf"])
  let japanese = GlassInteractionPresentation.dropValid(
    plan: single, glassTitle: "開発", surface: .desktop, locale: ja)
  let english = GlassInteractionPresentation.dropValid(
    plan: single, glassTitle: "開発", surface: .desktop, locale: en)
  #expect(japanese?.title == "100%_設計.pdfを開発にコピー")
  #expect(english?.title == "Copy 100%_設計.pdf to 開発")
  #expect(japanese?.indicator == .symbol("doc.on.doc"))
  #expect(japanese?.detail == "元のファイルは元の場所に残ります。")
  #expect(english?.detail == "Original files stay where they are.")

  let multiple = try localizedDropApprovalPlan(names: ["one.txt", "two.txt"])
  let workspace = GlassInteractionPresentation.dropValid(
    plan: multiple, glassTitle: "Projects", surface: .workspace, locale: ja)
  #expect(workspace?.title == "2件のファイルをProjectsにコピー")
  #expect(workspace?.indicator == .symbol("plus.circle.fill"))
}

@Test
func localizedDropApprovalPreservesNonCopyFallbackContract() {
  let ja = Locale(identifier: "ja_JP")
  let workspace = GlassInteractionPresentation.dropValid(
    plan: .noOperation, glassTitle: "Projects", surface: .workspace, locale: ja)
  #expect(workspace?.title == "Projectsにコピー")
  #expect(workspace?.detail == "元のファイルは元の場所に残ります。")
  #expect(
    GlassInteractionPresentation.dropValid(
      plan: .noOperation, glassTitle: "Projects", surface: .desktop, locale: ja) == nil)
}

private func localizedDropApprovalPlan(names: [String]) throws -> DropPlan {
  let root = URL(fileURLWithPath: "/tmp/SchneeGlassDropApproval", isDirectory: true)
  return .copy(
    try CopyBatchPlan(
      destination: DestinationDescriptor(
        glassID: GlassID(),
        folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: root),
        url: root,
        capabilities: StorageCapabilities(locationKind: .localFixed, isWritable: true)
      ),
      items: names.map { name in
        CopyItemPlan(
          sourceURL: URL(fileURLWithPath: "/tmp").appendingPathComponent(name),
          originalFilename: name,
          destinationFilename: name,
          expectedSize: 1
        )
      }
    )
  )
}

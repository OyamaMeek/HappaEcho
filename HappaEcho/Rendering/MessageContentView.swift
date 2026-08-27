import SwiftUI
struct MessageContentView: View { let content:String; var body: some View { VStack(alignment:.leading, spacing:10) { ForEach(Array(MessageDocumentParser().parse(content).nodes.enumerated()), id:\.offset) { _, node in MessageNodeView(node:node) } }.textSelection(.enabled) } }
private struct MessageNodeView: View { let node:MessageDocument.Node; var body: some View { switch node { case .heading(_,let text): Text(text).font(.headline); case .paragraph(let text): markdown(text); case .quote(let text): Text(text).italic().padding(.leading,8).overlay(alignment:.leading) { Rectangle().fill(.secondary).frame(width:3) }; case .list(let text): Label(text,systemImage:"circle.fill").font(.body); case .code(let language,let text): CodeBlockView(language:language,code:text); case .table(let cells): ScrollView(.horizontal) { HStack { ForEach(cells,id:\.self) { Text($0).padding(6).background(.quaternary, in:RoundedRectangle(cornerRadius:4)) } } }; case .displayMath(let expression): LaTeXView(expression:expression) } }
 @ViewBuilder private func markdown(_ text:String)->some View {
  let renderedText = LaTeXTextFormatter().formatInlineMath(in: text)
  if let value = try? AttributedString(markdown: renderedText) { Text(value) } else { Text(renderedText) }
 }
}

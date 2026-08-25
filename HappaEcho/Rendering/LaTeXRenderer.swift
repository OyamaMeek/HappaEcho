import SwiftUI
import UIKit
enum LaTeXRenderError: Error { case unsupported }
struct LaTeXRenderer { func render(_ expression:String, displayMode:Bool)->Result<Image,LaTeXRenderError> { guard !expression.contains("\\") else { return .failure(.unsupported) }; let size=UIFont.preferredFont(forTextStyle:displayMode ? .title2:.body).pointSize; let renderer=UIGraphicsImageRenderer(size:CGSize(width: CGFloat(max(1, expression.count)) * size, height: size * 1.5)); return .success(Image(uiImage:renderer.image { _ in (expression as NSString).draw(at:.zero,withAttributes:[.font:UIFont.systemFont(ofSize:size)]) })) } }
struct LaTeXView:View { let expression:String; var body:some View { switch LaTeXRenderer().render(expression,displayMode:true) { case .success(let image): image.accessibilityLabel("公式 \(expression)"); case .failure: Text("$$\(expression)$$").font(.system(.body,design:.monospaced)) } } }

import SwiftUI
import UIKit
enum LaTeXRenderError: Error { case unsupported }
struct LaTeXRenderer {
 func render(_ expression:String, displayMode:Bool)->Result<Image,LaTeXRenderError> {
  let text = LaTeXTextFormatter().format(expression)
  let font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: displayMode ? .title2 : .body).pointSize, weight: .regular)
  let bounds = (text as NSString).boundingRect(
   with: CGSize(width: 720, height: CGFloat.greatestFiniteMagnitude),
   options: [.usesLineFragmentOrigin, .usesFontLeading],
   attributes: [.font: font],
   context: nil
  ).integral
  let imageSize = CGSize(width: max(1, bounds.width), height: max(font.lineHeight, bounds.height))
  let renderer = UIGraphicsImageRenderer(size: imageSize)
  return .success(Image(uiImage:renderer.image { _ in
   (text as NSString).draw(
    in: CGRect(origin: .zero, size: imageSize),
    withAttributes: [.font: font, .foregroundColor: UIColor.label]
   )
  }))
 }
}

struct LaTeXTextFormatter {
 func format(_ expression: String) -> String {
  var value = expression
  for command in ["mathrm", "text", "mathbf", "mathit"] {
   value = replace("\\\(command){", in: value)
  }
  value = fractions(in: value)
  let replacements = [
   "\\qquad": "  ", "\\quad": " ", "\\,": " ", "\\;": " ", "\\:": " ",
   "\\cdot": "⋅", "\\times": "×", "\\div": "÷", "\\pm": "±", "\\mp": "∓",
   "\\leq": "≤", "\\geq": "≥", "\\neq": "≠", "\\approx": "≈", "\\infty": "∞",
   "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ", "\\theta": "θ",
   "\\lambda": "λ", "\\mu": "μ", "\\pi": "π", "\\sigma": "σ", "\\omega": "ω",
   "\\ldots": "…", "\\cdots": "⋯", "\\dots": "…", "\\sqrt": "√"
  ]
  for (command, replacement) in replacements { value = value.replacingOccurrences(of: command, with: replacement) }
  value = value.replacingOccurrences(of: "\\left", with: "").replacingOccurrences(of: "\\right", with: "")
  value = value.replacingOccurrences(of: "\\", with: "")
  value = scripts(in: value)
  return value.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
 }

 func formatInlineMath(in text: String) -> String {
  var output = replaceDelimitedMath(in: text, opening: "\\(", closing: "\\)")
  output = replaceDelimitedMath(in: output, opening: "$", closing: "$")
  return output
 }

 private func replace(_ prefix: String, in value: String) -> String {
  var output = value
  while let start = output.range(of: prefix) {
   guard let end = output[start.upperBound...].firstIndex(of: "}") else { break }
   output.replaceSubrange(start.lowerBound...end, with: output[start.upperBound..<end])
  }
  return output
 }

 private func fractions(in value: String) -> String {
  var output = value
  while let range = output.range(of: "\\frac{") {
   let numeratorStart = range.upperBound
   guard let numeratorEnd = matchingBrace(in: output, from: numeratorStart),
         numeratorEnd < output.endIndex,
         output.index(after: numeratorEnd) < output.endIndex,
         output[output.index(after: numeratorEnd)] == "{"
   else { break }

   let denominatorStart = output.index(after: output.index(after: numeratorEnd))
   guard let denominatorEnd = matchingBrace(in: output, from: denominatorStart) else { break }

   let numerator = String(output[numeratorStart..<numeratorEnd])
   let denominator = String(output[denominatorStart..<denominatorEnd])
   output.replaceSubrange(range.lowerBound...denominatorEnd, with: "(\(numerator))⁄(\(denominator))")
  }
  while let range = output.range(of: "\\frac") {
   let numeratorIndex = range.upperBound
   guard numeratorIndex < output.endIndex,
         output[numeratorIndex] != "{"
   else { break }
   let denominatorIndex = output.index(after: numeratorIndex)
   guard denominatorIndex < output.endIndex else { break }
   let numerator = output[numeratorIndex]
   let denominator = output[denominatorIndex]
   output.replaceSubrange(range.lowerBound...denominatorIndex, with: "\(numerator)⁄\(denominator)")
  }
  return output
 }

 private func replaceDelimitedMath(in value: String, opening: String, closing: String) -> String {
  var output = value
  var searchStart = output.startIndex
  while let openingRange = output.range(of: opening, range: searchStart..<output.endIndex) {
    let expressionStart = openingRange.upperBound
    guard let closingRange = output.range(of: closing, range: expressionStart..<output.endIndex) else { break }
    let expression = String(output[expressionStart..<closingRange.lowerBound])
   let renderedExpression = format(expression)
   let replacementOffset = output.distance(from: output.startIndex, to: openingRange.lowerBound)
   output.replaceSubrange(openingRange.lowerBound..<closingRange.upperBound, with: renderedExpression)
   searchStart = output.index(
    output.startIndex,
    offsetBy: replacementOffset + renderedExpression.count,
    limitedBy: output.endIndex
   ) ?? output.endIndex
  }
  return output
 }

 private func matchingBrace(in value: String, from contentStart: String.Index) -> String.Index? {
  var depth = 1
  var index = contentStart
  while index < value.endIndex {
   switch value[index] {
   case "{": depth += 1
   case "}":
    depth -= 1
    if depth == 0 { return index }
   default: break
   }
   index = value.index(after: index)
  }
  return nil
 }

 private func scripts(in value: String) -> String {
  var output = ""
  var index = value.startIndex
  while index < value.endIndex {
   let character = value[index]
   if (character == "_" || character == "^"), value.index(after: index) < value.endIndex {
    let superscript = character == "^"
    var next = value.index(after: index)
    let content: String
    if value[next] == "{" {
     let start = value.index(after: next)
     guard let end = value[start...].firstIndex(of: "}") else { output.append(character); index = next; continue }
     content = String(value[start..<end])
     next = value.index(after: end)
    } else {
     content = String(value[next])
     next = value.index(after: next)
    }
    output += content.map { script($0, superscript: superscript) }.joined()
    index = next
   } else {
    output.append(character)
    index = value.index(after: index)
   }
  }
  return output
 }

 private func script(_ character: Character, superscript: Bool) -> String {
  let superscripts: [Character: String] = ["0":"⁰","1":"¹","2":"²","3":"³","4":"⁴","5":"⁵","6":"⁶","7":"⁷","8":"⁸","9":"⁹","+":"⁺","-":"⁻","=":"⁼","(":"⁽",")":"⁾","n":"ⁿ","i":"ⁱ"]
  let subscripts: [Character: String] = ["0":"₀","1":"₁","2":"₂","3":"₃","4":"₄","5":"₅","6":"₆","7":"₇","8":"₈","9":"₉","+":"₊","-":"₋","=":"₌","(":"₍",")":"₎","a":"ₐ","e":"ₑ","h":"ₕ","i":"ᵢ","j":"ⱼ","k":"ₖ","l":"ₗ","m":"ₘ","n":"ₙ","o":"ₒ","p":"ₚ","r":"ᵣ","s":"ₛ","t":"ₜ","u":"ᵤ","v":"ᵥ","x":"ₓ"]
  return (superscript ? superscripts : subscripts)[character] ?? String(character)
 }
}
struct LaTeXView:View { let expression:String; var body:some View { switch LaTeXRenderer().render(expression,displayMode:true) { case .success(let image): image.accessibilityLabel("公式 \(expression)"); case .failure: Text("$$\(expression)$$").font(.system(.body,design:.monospaced)) } } }

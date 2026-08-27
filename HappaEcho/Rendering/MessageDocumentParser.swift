import Foundation

struct MessageDocument: Equatable {
    enum Node: Equatable {
        case heading(Int, String)
        case paragraph(String)
        case quote(String)
        case list(String)
        case code(String, String)
        case table([String])
        case displayMath(String)
    }

    var nodes: [Node]
}

struct MessageDocumentParser {
    func parse(_ source: String) -> MessageDocument {
        var nodes: [MessageDocument.Node] = []
        var paragraph: [String] = []
        var code: [String] = []
        var displayMath: [String]?
        var language = "plain"
        var fenced = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            nodes.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushParagraph()
                if fenced {
                    nodes.append(.code(language, code.joined(separator: "\n")))
                    code.removeAll()
                } else {
                    language = String(line.dropFirst(3)).nilIfBlank ?? "plain"
                }
                fenced.toggle()
                continue
            }

            if fenced {
                code.append(line)
                continue
            }

            if displayMath != nil {
                if trimmed == "$$" {
                    let expression = displayMath!.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !expression.isEmpty {
                        nodes.append(.displayMath(expression))
                    }
                    displayMath = nil
                } else {
                    displayMath!.append(line)
                }
                continue
            }

            if trimmed == "$$" {
                flushParagraph()
                displayMath = []
                continue
            }

            if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 {
                flushParagraph()
                nodes.append(.displayMath(String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)))
                continue
            }

            if line.hasPrefix("#") {
                flushParagraph()
                let count = line.prefix(while: { $0 == "#" }).count
                nodes.append(.heading(count, String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraph()
                nodes.append(.quote(String(line.dropFirst(2))))
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                nodes.append(.list(String(line.dropFirst(2))))
                continue
            }

            if line.contains("|"), !trimmed.hasPrefix("|---") {
                flushParagraph()
                nodes.append(.table(line.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }))
                continue
            }

            if line.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
        }

        if let displayMath {
            let expression = displayMath.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !expression.isEmpty {
                nodes.append(.displayMath(expression))
            }
        }
        flushParagraph()
        if fenced {
            nodes.append(.paragraph("```\(language)\n\(code.joined(separator: "\n"))"))
        }
        return MessageDocument(nodes: nodes)
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}

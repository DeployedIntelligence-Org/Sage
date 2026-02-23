import SwiftUI

/// Renders a markdown string as SwiftUI views without any external dependencies.
///
/// Supported syntax:
/// - Headings: `# H1`, `## H2`, `### H3`
/// - Bold/italic/inline code via `AttributedString(markdown:)`
/// - Fenced code blocks: ` ``` ``` `
/// - Bullet lists: `- item` or `* item`
/// - Numbered lists: `1. item`
/// - Plain paragraphs (separated by blank lines)
struct MarkdownTextView: View {

    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let content):
            inlineText(content)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let content, let level):
            inlineText(content)
                .font(headingFont(level))
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level == 1 ? 4 : 2)

        case .codeBlock(let code, _):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(10)
            }
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        inlineText(item)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1).")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 20, alignment: .trailing)
                        inlineText(item)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Inline text (bold/italic/code via AttributedString)

    private func inlineText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .headline
        default: return .subheadline
        }
    }

    // MARK: - Parsing

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(text)
    }
}

// MARK: - Block types

private enum MarkdownBlock {
    case paragraph(String)
    case heading(String, level: Int)
    case codeBlock(String, language: String?)
    case bulletList([String])
    case numberedList([String])
}

// MARK: - Parser

private enum MarkdownParser {

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // consume closing ```
                // Trim trailing blank lines from code block
                while codeLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                    codeLines.removeLast()
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n"), language: language.isEmpty ? nil : language))
                continue
            }

            // Heading
            if line.hasPrefix("#") {
                var level = 0
                var rest = line[line.startIndex...]
                while rest.first == "#" { level += 1; rest = rest.dropFirst() }
                let content = rest.trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    blocks.append(.heading(content, level: min(level, 3)))
                    i += 1
                    continue
                }
            }

            // Bullet list: collect consecutive bullet lines
            if isBullet(line) {
                var items: [String] = []
                while i < lines.count && isBullet(lines[i]) {
                    let stripped = lines[i].drop(while: { $0 == "-" || $0 == "*" || $0 == " " })
                    items.append(String(stripped).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Numbered list: collect consecutive numbered lines
            if isNumbered(line) {
                var items: [String] = []
                while i < lines.count && isNumbered(lines[i]) {
                    // Strip "1. " or "10. " prefix
                    let rest = lines[i].drop(while: { $0.isNumber }).drop(while: { $0 == "." || $0 == " " })
                    items.append(String(rest).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.numberedList(items))
                continue
            }

            // Blank line separator — skip
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Paragraph: collect consecutive non-special lines
            var paragraphLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                if l.trimmingCharacters(in: .whitespaces).isEmpty { break }
                if l.hasPrefix("```") || l.hasPrefix("#") || isBullet(l) || isNumbered(l) { break }
                paragraphLines.append(l)
                i += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    private static func isBullet(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .init(charactersIn: " "))
        return (t.hasPrefix("- ") || t.hasPrefix("* ")) && t.count > 2
    }

    private static func isNumbered(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .init(charactersIn: " "))
        guard let dot = t.firstIndex(of: ".") else { return false }
        let prefix = t[t.startIndex..<dot]
        return prefix.allSatisfy(\.isNumber) && !prefix.isEmpty
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MarkdownTextView(text: """
# Heading 1
## Heading 2

Here is a **bold** word and an *italic* one. Inline `code` works too.

- First bullet
- Second bullet
- Third bullet

1. Step one
2. Step two
3. Step three

```swift
func greet(_ name: String) -> String {
    return "Hello, \\(name)!"
}
```

A final paragraph with no special formatting.
""")
        .padding()
    }
}

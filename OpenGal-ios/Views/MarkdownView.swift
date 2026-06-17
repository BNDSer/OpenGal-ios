import SwiftUI
import WebKit

/// Full markdown + LaTeX renderer using a single WKWebView.
/// Handles: bold, italic, inline code, $...$ inline math, $$...$$ display math.
/// No CDN dependency for markdown — only KaTeX is loaded from CDN.
struct MarkdownView: View {
    let text: String
    @State private var height: CGFloat = 28

    var body: some View {
        MarkdownWebView(text: text, height: $height)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.1), value: height)
    }
}

private struct MarkdownWebView: UIViewRepresentable {
    let text: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "h")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        context.coordinator.webView = wv
        context.coordinator.lastText = text
        wv.loadHTMLString(html(text), baseURL: nil)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.lastText != text else { return }
        context.coordinator.lastText = text
        uiView.loadHTMLString(html(text), baseURL: nil)
    }

    // MARK: - HTML builder

    private func html(_ markdown: String) -> String {
        let body = renderMarkdown(markdown)
        return """
        <!DOCTYPE html><html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"
                onload="boot()"></script>
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        html,body{background:transparent;overflow:hidden}
        body{font-family:-apple-system,sans-serif;font-size:16px;line-height:1.75;
             word-break:break-word;padding:0 2px}
        @media(prefers-color-scheme:dark){body{color:#f0f0f0}}
        code{font-family:ui-monospace,monospace;font-size:.9em;
             background:rgba(128,128,128,.15);padding:1px 4px;border-radius:4px}
        .katex-display{margin:.5em 0;overflow-x:auto}
        p{margin:0;padding:0}
        p+p{margin-top:0.4em}
        br{display:block;content:'';margin:0}
        </style>
        </head>
        <body id="b">\(body)</body>
        <script>
        function boot(){
          renderMathInElement(document.getElementById('b'),{
            delimiters:[
              {left:'$$',right:'$$',display:true},
              {left:'$', right:'$', display:false}
            ],
            throwOnError:false,strict:false
          });
          report();
        }
        function report(){
          var h=document.getElementById('b').scrollHeight;
          window.webkit.messageHandlers.h.postMessage(h);
        }
        setTimeout(report,2000);
        </script>
        </html>
        """
    }

    /// Convert markdown subset to HTML. Preserves $ so KaTeX can find them.
    private func renderMarkdown(_ md: String) -> String {
        var lines = md.components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if t.hasPrefix("```") {
                let lang = String(t.dropFirst(3))
                var code = ""
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code += htmlEscape(lines[i]) + "\n"; i += 1
                }
                out.append("<pre><code>\(code)</code></pre>")
                i += 1; continue
            }
            // Headings
            if t.hasPrefix("### ") { out.append("<h3>\(inline(String(t.dropFirst(4))))</h3>"); i += 1; continue }
            if t.hasPrefix("## ")  { out.append("<h2>\(inline(String(t.dropFirst(3))))</h2>"); i += 1; continue }
            if t.hasPrefix("# ")   { out.append("<h1>\(inline(String(t.dropFirst(2))))</h1>"); i += 1; continue }
            // Divider
            if t == "---" || t == "***" { out.append("<hr>"); i += 1; continue }
            // Bullet
            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                out.append("<li>\(inline(String(t.dropFirst(2))))</li>"); i += 1; continue
            }
            // Numbered list
            if let sp = t.firstIndex(of: " "), t[t.startIndex..<sp].hasSuffix("."),
               let _ = Int(String(t[t.startIndex..<sp].dropLast())) {
                out.append("<li>\(inline(String(t[t.index(after: sp)...])))</li>"); i += 1; continue
            }
            // Table
            if t.hasPrefix("|") && t.hasSuffix("|") {
                let next = i + 1 < lines.count ? lines[i+1].trimmingCharacters(in: .whitespaces) : ""
                if next.hasPrefix("|") && next.contains("-") {
                    let headers = tableRow(t)
                    i += 2
                    var rows: [[String]] = []
                    while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                        rows.append(tableRow(lines[i].trimmingCharacters(in: .whitespaces))); i += 1
                    }
                    let cellStyle = "border:1px solid #ccc;padding:6px 10px;white-space:nowrap"
                    var tbl = "<div style='overflow-x:auto'><table style='border-collapse:collapse'>"
                    tbl += "<tr>" + headers.map {
                        "<th style='\(cellStyle);text-align:left;background:rgba(128,128,128,.12)'>\(inline($0))</th>"
                    }.joined() + "</tr>"
                    for row in rows {
                        tbl += "<tr>" + row.map {
                            "<td style='\(cellStyle)'>\(inline($0))</td>"
                        }.joined() + "</tr>"
                    }
                    tbl += "</table></div>"
                    out.append(tbl); continue
                }
            }
            // Blank
            if t.isEmpty { out.append("<br>"); i += 1; continue }
            // Paragraph
            out.append("<p>\(inline(raw))</p>"); i += 1
        }
        return out.joined(separator: "\n")
    }

    /// Apply inline formatting: bold, italic, code. Preserves $ for KaTeX.
    private func inline(_ s: String) -> String {
        // Escape HTML except $
        var r = htmlEscape(s)
        // Bold
        r = r.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>", options: .regularExpression)
        // Italic
        r = r.replacingOccurrences(of: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)",
            with: "<em>$1</em>", options: .regularExpression)
        // Inline code
        r = r.replacingOccurrences(of: "`(.+?)`",
            with: "<code>$1</code>", options: .regularExpression)
        return r
    }

    private func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func tableRow(_ line: String) -> [String] {
        var s = line
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|") { s = String(s.dropLast()) }
        // Split by | but not inside $...$
        var cells: [String] = []
        var current = ""
        var inMath = false
        var idx = s.startIndex
        while idx < s.endIndex {
            let ch = s[idx]
            if ch == "$" { inMath.toggle() }
            if ch == "|" && !inMath {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
            idx = s.index(after: idx)
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: MarkdownWebView
        var lastText = ""
        weak var webView: WKWebView?

        init(_ p: MarkdownWebView) { parent = p }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let v = message.body as? NSNumber else { return }
            let h = CGFloat(v.doubleValue)
            guard h > 4 else { return }
            DispatchQueue.main.async {
                if abs(h - self.parent.height) > 1 { self.parent.height = h }
            }
        }
    }
}

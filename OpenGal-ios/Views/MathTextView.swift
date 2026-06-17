import SwiftUI
import WebKit

/// Renders a paragraph of mixed markdown text and LaTeX.
/// Uses KaTeX auto-render: $...$ = inline, $$...$$ = display block.
struct MathTextView: UIViewRepresentable {
    let markdown: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "heightChanged")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        context.coordinator.webView = wv
        wv.loadHTMLString(buildHTML(markdown), baseURL: nil)
        context.coordinator.lastMarkdown = markdown
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.lastMarkdown != markdown else { return }
        context.coordinator.lastMarkdown = markdown
        uiView.loadHTMLString(buildHTML(markdown), baseURL: nil)
    }

    private func buildHTML(_ text: String) -> String {
        // Convert markdown inline formatting to HTML, preserve $ delimiters for KaTeX
        let html = markdownToHTML(text)
        return """
        <!DOCTYPE html><html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"
                onload="go()"></script>
        <style>
          * { margin:0; padding:0; box-sizing:border-box; }
          html, body { background:transparent; overflow:hidden; }
          body {
            font-family: -apple-system, sans-serif;
            font-size: 16px;
            line-height: 1.7;
            padding: 0 1px;
            word-break: break-word;
          }
          @media (prefers-color-scheme: dark) { body { color: #fff; } }
          .katex-display { margin: 0.5em 0; overflow-x: visible; }
          .katex-display > .katex { white-space: normal; }
        </style>
        </head>
        <body id="b">\(html)</body>
        <script>
        function go() {
          renderMathInElement(document.getElementById('b'), {
            delimiters: [
              {left:'$$', right:'$$', display:true},
              {left:'$',  right:'$',  display:false}
            ],
            throwOnError: false,
            strict: false
          });
          reportHeight();
        }
        function reportHeight() {
          var h = document.getElementById('b').scrollHeight;
          window.webkit.messageHandlers.heightChanged.postMessage(h);
        }
        // Re-report after fonts/images settle
        window.addEventListener('load', function(){ setTimeout(reportHeight, 200); });
        </script>
        </html>
        """
    }

    /// Minimal markdown → HTML: bold, italic, inline code, escaping.
    /// Does NOT escape $ so KaTeX can find math delimiters.
    private func markdownToHTML(_ text: String) -> String {
        var s = text
        // HTML-escape only < > & (not $)
        s = s.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        // Bold **...**
        s = applyPattern(s, pattern: #"\*\*(.+?)\*\*"#, template: "<strong>$1</strong>")
        // Italic *...*  (after bold so ** is handled first)
        s = applyPattern(s, pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, template: "<em>$1</em>")
        // Inline code `...`
        s = applyPattern(s, pattern: #"`(.+?)`"#, template: "<code>$1</code>")
        return s
    }

    private func applyPattern(_ input: String, pattern: String, template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return re.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: MathTextView
        var lastMarkdown: String = ""
        weak var webView: WKWebView?

        init(_ p: MathTextView) { parent = p }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let raw = message.body as? NSNumber else { return }
            let h = CGFloat(raw.doubleValue)
            guard h > 4 else { return }
            DispatchQueue.main.async {
                // Add padding so descenders aren't clipped
                let padded = h + 8
                if abs(padded - self.parent.height) > 1 {
                    self.parent.height = padded
                }
            }
        }
    }
}

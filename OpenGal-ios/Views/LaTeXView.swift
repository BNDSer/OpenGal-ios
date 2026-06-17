import SwiftUI
import WebKit

struct LaTeXView: UIViewRepresentable {
    let latex: String
    let displayMode: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "heightChanged")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.navigationDelegate = context.coordinator
        wv.loadHTMLString(html(for: latex, display: displayMode), baseURL: nil)
        context.coordinator.lastLatex = latex
        context.coordinator.lastDisplay = displayMode
        return wv
    }

    // Only reload when content actually changes — prevents infinite height-update loop
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLatex != latex || context.coordinator.lastDisplay != displayMode {
            uiView.loadHTMLString(html(for: latex, display: displayMode), baseURL: nil)
            context.coordinator.lastLatex = latex
            context.coordinator.lastDisplay = displayMode
        }
    }

    private func html(for latex: String, display: Bool) -> String {
        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        let renderCall = "katex.render(`\(escaped)`, el, {displayMode: \(display), throwOnError: false, strict: false});"
        let align = display ? "block" : "inline-block"
        return """
        <!DOCTYPE html><html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js" onload="renderMath()"></script>
        <style>
          * { margin:0; padding:0; box-sizing:border-box; }
          body { background:transparent; font-size:16px; line-height:1.4; }
          #el { display:\(align); }
        </style>
        </head>
        <body><div id="el"></div>
        <script>
        function renderMath() {
          var el = document.getElementById('el');
          try { \(renderCall) } catch(e) { el.textContent = '\(escaped)'; }
          setTimeout(function(){
            window.webkit.messageHandlers.heightChanged.postMessage(document.body.scrollHeight);
          }, 50);
        }
        </script>
        </body></html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: LaTeXView
        var lastLatex: String = ""
        var lastDisplay: Bool = true

        init(_ parent: LaTeXView) { self.parent = parent }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            if let h = message.body as? CGFloat {
                DispatchQueue.main.async {
                    let newH = max(h, self.parent.displayMode ? 32 : 24)
                    if abs(newH - self.parent.height) > 1 {
                        self.parent.height = newH
                    }
                }
            }
        }
    }
}

import SwiftUI
import WebKit
import AppKit

/// SwiftUI wrapper around WKWebView that renders Markdown-ish text with
/// LaTeX-style math via KaTeX. Use it for problem solutions where
/// `$inline$` and `$$display$$` delimiters should look like real math.
///
/// Usage:
///   MathView(content: "By Bayes, $P(A|B) = \\frac{P(B|A)P(A)}{P(B)}$.",
///            fontSize: 14)
///
/// The KaTeX bundle is shipped in `Sources/Resources/katex/`. Loaded
/// once via WKWebView and auto-render scans the document for `$...$` and
/// `$$...$$` delimiters.
struct MathView: NSViewRepresentable {
    let content: String
    var fontSize: CGFloat = 14
    /// Optional theme override — when nil, follows the SwiftUI color
    /// scheme (light / dark).
    var darkMode: Bool? = nil
    /// Reported back when content layout stabilizes so callers can
    /// size the view correctly.
    var onHeightChange: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow loading the KaTeX assets from the app bundle. Without this
        // bundle-relative URLs (the font @font-face entries) won't resolve.
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")    // transparent — sits over SwiftUI bg
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let isDark = darkMode ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let html = Self.makeHTML(content: content, fontSize: fontSize, dark: isDark)
        // Bundle.module is the SPM-generated bundle that contains
        // anything declared in `resources:` of the Package.swift target.
        let katexDir = Bundle.module.url(forResource: "katex", withExtension: nil)
            ?? Bundle.main.url(forResource: "katex", withExtension: nil)
        guard let dir = katexDir else {
            webView.loadHTMLString(html, baseURL: nil)
            return
        }
        // baseURL must be the katex directory so the font @font-face URLs
        // (which are relative — `fonts/KaTeX_Main-Regular.woff2`) resolve.
        // Also allow reads of the whole katex/ tree (incl. fonts/).
        webView.loadHTMLString(html, baseURL: dir.appendingPathComponent("placeholder.html"))
        // Read access — needed for WKWebView to load the local CSS/JS/fonts.
        _ = dir  // (loadFileURL would let us set allowingReadAccessTo, but loadHTMLString + baseURL works for local file:// URLs as long as the resource is below baseURL)
        context.coordinator.parent = self
    }

    /// Assemble the HTML page: KaTeX CSS, the user content as markdown-
    /// flavored body, and the KaTeX auto-render script that scans for
    /// $...$ and $$...$$ on DOMContentLoaded.
    private static func makeHTML(content: String, fontSize: CGFloat, dark: Bool) -> String {
        let bg = dark ? "#1c1c1e" : "#ffffff00"
        let fg = dark ? "#e0e0e0" : "#1a1a1a"
        let secondary = dark ? "#a0a0a0" : "#5a5a5a"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width">
        <link rel="stylesheet" href="katex.min.css">
        <style>
          html, body {
            margin: 0;
            padding: 0;
            background: \(bg);
            color: \(fg);
            font-family: -apple-system, "New York", "Times New Roman", serif;
            font-size: \(fontSize)px;
            line-height: 1.55;
            -webkit-font-smoothing: antialiased;
          }
          .body { padding: 4px 2px; }
          p { margin: 0 0 0.6em 0; }
          p:last-child { margin-bottom: 0; }
          .katex-display { margin: 0.6em 0; }
          .katex { font-size: 1.05em; }
          .step-title {
            font-family: -apple-system, sans-serif;
            font-size: 0.78em;
            font-weight: 700;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            color: \(secondary);
            margin: 0 0 0.3em 0;
          }
        </style>
        </head>
        <body>
        <div class="body">\(markdownToHTML(content))</div>
        <script src="katex.min.js"></script>
        <script src="auto-render.min.js"></script>
        <script>
          document.addEventListener("DOMContentLoaded", function() {
            renderMathInElement(document.body, {
              delimiters: [
                {left: "$$", right: "$$", display: true},
                {left: "$",  right: "$",  display: false}
              ],
              throwOnError: false
            });
          });
        </script>
        </body>
        </html>
        """
    }

    /// Convert a tiny subset of Markdown to HTML — only what we need for
    /// hint bodies. Avoids adding a dependency on swift-markdown.
    ///   • Blank line  → paragraph break
    ///   • `**bold**`  → <strong>
    ///   • `*italic*`  → <em>
    ///   • `\n`        → <br>
    /// Math passes through unchanged so KaTeX can see the $delimiters$.
    private static func markdownToHTML(_ s: String) -> String {
        // Split into paragraphs by blank-line.
        let paragraphs = s.components(separatedBy: "\n\n")
        return paragraphs.map { para -> String in
            var p = para
            p = p.replacingOccurrences(of: "&", with: "&amp;")
            // Don't escape < and > because users won't write raw HTML in
            // hints, and KaTeX may emit some via auto-render before this
            // pass (well, no — markdown runs first; we're fine).
            p = applyEmphasis(p, marker: "**", tag: "strong")
            p = applyEmphasis(p, marker: "*",  tag: "em")
            p = p.replacingOccurrences(of: "\n", with: "<br>")
            return "<p>\(p)</p>"
        }.joined(separator: "\n")
    }

    private static func applyEmphasis(_ s: String, marker: String, tag: String) -> String {
        var out = ""
        var rest = s[...]
        while let openRange = rest.range(of: marker) {
            out += rest[..<openRange.lowerBound]
            let afterOpen = openRange.upperBound
            if let closeRange = rest.range(of: marker, range: afterOpen..<rest.endIndex) {
                let inner = rest[afterOpen..<closeRange.lowerBound]
                out += "<\(tag)>\(inner)</\(tag)>"
                rest = rest[closeRange.upperBound...]
            } else {
                // unbalanced marker — preserve as-is
                out += rest[openRange.lowerBound...]
                return out
            }
        }
        out += rest
        return out
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MathView
        init(_ parent: MathView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Report content height back to SwiftUI so the parent can
            // size the view to its content.
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let h = result as? CGFloat {
                    self?.parent.onHeightChange?(h)
                }
            }
        }
    }
}

/// Convenience wrapper that auto-sizes the WebView to its content height.
/// Use this instead of MathView when you want it to grow with the math
/// rather than having a fixed frame.
struct AutoSizingMathView: View {
    let content: String
    var fontSize: CGFloat = 14
    @State private var height: CGFloat = 60

    var body: some View {
        MathView(content: content, fontSize: fontSize) { h in
            // Pad slightly to avoid scroll bars on borderline cases.
            self.height = h + 4
        }
        .frame(height: height)
    }
}

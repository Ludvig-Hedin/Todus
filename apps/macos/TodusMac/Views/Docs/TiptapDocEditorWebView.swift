import SwiftUI
import WebKit
import AppKit

/// Local bundled Tiptap — no `app.todus.app` load; `WKScriptMessageHandler` for JSON + plaintext.
struct TiptapDocEditorWebView: NSViewRepresentable {
    /// Changes when opening another document — new injection.
    var documentId: String
    var initialContent: DocJSONValue?
    var isDark: Bool
    var onContentChange: (DocJSONValue?, String) -> Void
    var onWebViewReady: ((WKWebView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "todusDoc")
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.parent = self
        context.coordinator.onContentChange = onContentChange
        context.coordinator.webView = web
        onWebViewReady?(web)

        if let indexURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "DocEditor"
        ) {
            let dir = indexURL.deletingLastPathComponent()
            web.loadFileURL(indexURL, allowingReadAccessTo: dir)
        } else {
            AppLogger.shared.log(
                "[TiptapDocEditor] DocEditor/index.html missing — bun run --filter @zero/macos-doc-editor build"
            )
            // Show a visible failure instead of a permanently blank white pane.
            web.loadHTMLString(Self.editorMissingHTML, baseURL: nil)
        }
        return web
    }

    /// Shown when the bundled editor resource is absent (build step skipped).
    private static let editorMissingHTML = """
    <!doctype html><html><head><meta charset="utf-8">
    <style>
      html,body{height:100%;margin:0;background:transparent;
        font-family:-apple-system,system-ui,sans-serif;color:#8a8a8e;}
      .wrap{height:100%;display:flex;align-items:center;justify-content:center;
        text-align:center;padding:24px;box-sizing:border-box;}
      .title{font-size:14px;font-weight:600;color:#c7c7cc;margin-bottom:6px;}
      .sub{font-size:12px;line-height:1.4;max-width:360px;}
    </style></head>
    <body><div class="wrap"><div>
      <div class="title">Editor failed to load</div>
      <div class="sub">The document editor isn’t available in this build.</div>
    </div></div></body></html>
    """

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.onContentChange = onContentChange
        if context.coordinator.injectedForDocId != documentId {
            context.coordinator.injectedForDocId = documentId
            let c = initialContent ?? TiptapDocEditorWebView.emptyDocument
            context.coordinator.pendingInject = c
            context.coordinator.tryInjectIfReady()
        }
        let theme: String = isDark ? "dark" : "light"
        if context.coordinator.appliedTheme != theme {
            context.coordinator.appliedTheme = theme
            webView.evaluateJavaScript("window.todusEditor && window.todusEditor.setTheme('\(theme)');", completionHandler: nil)
        }
    }

    fileprivate static let emptyDocument: DocJSONValue = .object([
        "type": .string("doc"),
        "content": .array([.object(["type": .string("paragraph")])]),
    ])

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: TiptapDocEditorWebView?
        var onContentChange: ((DocJSONValue?, String) -> Void)?
        weak var webView: WKWebView?
        var injectedForDocId: String?
        var pendingInject: DocJSONValue?
        var appliedTheme: String?
        var editorReady = false

        func userContentController(
            _: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "todusDoc",
                  let body = message.body as? [String: Any] else { return }
            let type = body["type"] as? String
            if type == "ready" {
                editorReady = true
                tryInjectIfReady()
                return
            }
            if type == "change" {
                let text = (body["contentText"] as? String) ?? ""
                if let c = body["content"],
                   let data = try? JSONSerialization.data(withJSONObject: c),
                   let v = try? JSONDecoder().decode(DocJSONValue.self, from: data) {
                    onContentChange?(v, text)
                } else {
                    onContentChange?(nil, text)
                }
            }
        }

        func tryInjectIfReady() {
            guard editorReady, let web = webView, let payload = pendingInject else { return }
            pendingInject = nil
            guard let data = try? JSONEncoder().encode(payload) else { return }
            let b64 = data.base64EncodedString()
            let script = """
            (function(){
              if(!window.todusEditor) return;
              const b64 = '\(b64)';
              const bin = atob(b64);
              const bytes = new Uint8Array(bin.length);
              for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
              const raw = new TextDecoder('utf-8').decode(bytes);
              window.todusEditor.setContent(JSON.parse(raw));
            })();
            """
            web.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

// MARK: - Toolbar (bridged to bundled `window.todusEditor.run`)

enum TiptapRunCommand: String, CaseIterable {
    case bold
    case italic
    case heading1
    case heading2
    case bulletList
    case orderedList
    case taskList
    case paragraph
    case undo
    case redo
}

@MainActor
func tiptapRun(_ command: TiptapRunCommand, in webView: WKWebView) {
    let js = "window.todusEditor && window.todusEditor.run('\(command.rawValue)');"
    webView.evaluateJavaScript(js, completionHandler: nil)
}

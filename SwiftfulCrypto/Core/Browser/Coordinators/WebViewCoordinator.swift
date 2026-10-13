//
//  WebViewCoordinator.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import Foundation
import WebKit
import Combine

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    weak var webView: WKWebView?
    let viewModel: BrowserViewModel
    let rpcService: Web3RPCService

    private var cancellables = Set<AnyCancellable>()

    init(viewModel: BrowserViewModel, rpcService: Web3RPCService) {
        self.viewModel = viewModel
        self.rpcService = rpcService
        super.init()

        // Setup callbacks from RPC service back to web view
        rpcService.$responseToSend
            .compactMap { $0 }
            .sink { [weak self] response in
                self?.sendResponseToJS(responseJSON: response)
            }
            .store(in: &cancellables)
    }

    deinit {
        // Remove message handler to prevent memory leaks
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.viewModel.isLoading = true
            self.viewModel.canGoBack = webView.canGoBack
            self.viewModel.canGoForward = webView.canGoForward
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.viewModel.isLoading = false
            self.viewModel.canGoBack = webView.canGoBack
            self.viewModel.canGoForward = webView.canGoForward

            if let url = webView.url {
                self.viewModel.url = url
            }
        }

        // Ensure everything is correct after page load - force patch request method to guarantee we get called
        let ensureScript = """
        (function() {
            console.log("[native] ========== DEBUG START ==========");
            console.log("[native] Ensuring everything is correct...");

            // 1. FORCE ensure window.trustwallet.postMessage is our bridge
            window.trustwallet = window.trustwallet || {};
            window.trustwallet.postMessage = function(obj) {
                console.log("✅ [native-force] window.trustwallet.postMessage called!", JSON.stringify(obj));
                try {
                    window.webkit.messageHandlers.ethereum.postMessage(JSON.stringify(obj));
                    console.log("✅ [native-force] Message sent!");
                } catch (e) {
                    console.error("❌ [native-force] Failed to send:", e);
                }
            };
            console.log("[native] ✅ Force-set window.trustwallet.postMessage done");

            // 2. Create if missing
            try {
                if (typeof window.trustwallet !== 'undefined'
                    && typeof window.trustwallet.Provider === 'function'
                    && typeof window.ethereum === 'undefined') {
                    console.log("[native] Creating window.ethereum now...");
                    window.ethereum = new window.trustwallet.Provider({
                        isDebug: false,
                        ethereum: {
                            address: '',
                        }
                    });
                    window.ethereum.isMetaMask = true;
                    console.log("[native] ✅ window.ethereum created after page load");
                }
            } catch (e) {
                console.error("[native] ❌ Error creating window.ethereum:", e);
            }

            // 🔥 3. FINAL PATCH: Patch window.ethereum.request to log and guarantee delivery
            if (window.ethereum && typeof window.ethereum.request === 'function') {
                const originalRequest = window.ethereum.request;
                window.ethereum.request = function(args) {
                    console.log("✅ [native-patch] 👉 window.ethereum.request called with args:", args);
                    console.log("✅ [native-patch] Forwarding to original request...");
                    const result = originalRequest.call(window.ethereum, args);
                    console.log("✅ [native-patch] request returned:", result);
                    return result;
                };
                console.log("[native] ✅ Patched window.ethereum.request for logging");
            }

            var result = {
                trustwalletExists: typeof window.trustwallet !== 'undefined',
                trustwalletPostMessageExists: typeof window.trustwallet !== 'undefined' && typeof window.trustwallet.postMessage === 'function',
                ethereumExists: typeof window.ethereum !== 'undefined',
                ethereumInTrustwallet: window.trustwallet && typeof window.trustwallet.ethereum !== 'undefined',
                trustwalletHas: Object.keys(window.trustwallet || {}),
                ethereumRequestExists: window.ethereum && typeof window.ethereum.request === 'function'
            };

            console.log("[native] Result:", JSON.stringify(result));
            console.log("[native] ========== DEBUG END ==========");

            return JSON.stringify(result);
        })();
        """
        webView.evaluateJavaScript(ensureScript, completionHandler: { result, error in
            if let error = error {
                print("🌐 [debug] Check script error: \(error.localizedDescription)")
            } else if let resultStr = result as? String {
                print("🌐 [debug] Injection check result: \(resultStr)")
            }
        })
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async {
            self.viewModel.isLoading = false
        }
        print("WebView navigation error: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async {
            self.viewModel.isLoading = false
        }
        print("WebView provisional navigation error: \(error.localizedDescription)")
    }

    // Observe loading progress
    func observeProgress(webView: WKWebView) {
        webView.addObserver(
            self,
            forKeyPath: #keyPath(WKWebView.estimatedProgress),
            options: .new,
            context: nil
        )
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == #keyPath(WKWebView.estimatedProgress),
           let webView = object as? WKWebView {
            DispatchQueue.main.async {
                self.viewModel.progress = webView.estimatedProgress
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // trust-min.js sends messages via "ethereum" message handler
        guard message.name == "ethereum" else {
            print("🌐 [Web3Bridge] Received message from unknown handler: \(message.name)")
            return
        }

        // The message should be a JSON string containing the RPC request
        guard let jsonString = message.body as? String else {
            print("🌐 [Web3Bridge] Invalid message format: expected string, got \(type(of: message.body))")
            return
        }

        print("🌐 [Web3Bridge] Received message from JS: \(jsonString.prefix(200))...")
        handleIncomingMessage(jsonString)
    }

    private func handleIncomingMessage(_ jsonString: String) {
        do {
            // trust-min.js calls window.webkit.messageHandlers.ethereum.postMessage(JSON.stringify(obj))
            // So jsonString is already stringified JSON, we just parse it
            guard let data = jsonString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("🌐 [Web3Bridge] ❌ Failed to parse trust-min message: \(jsonString.prefix(100))")
                return
            }

            let id = json["id"] as? Int ?? 0
            guard let methodName = json["name"] as? String else {
                print("🌐 [Web3Bridge] ❌ Missing name in trust-min message")
                return
            }

            let params = json["object"]

            print("🌐 [Web3Bridge] ✅ trust-min request received: method=\(methodName), id=\(id)")

            // Convert trust method names to standard ETH JSON-RPC methods
            let rpcMethod: String
            switch methodName {
            case "requestAccounts": rpcMethod = "eth_requestAccounts"
            case "signMessage": rpcMethod = "personal_sign"
            case "signTransaction": rpcMethod = "eth_signTransaction"
            case "sendTransaction": rpcMethod = "eth_sendTransaction"
            default: rpcMethod = methodName
            }

            // Build standard JSON-RPC format
            let rpcRequest: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "method": rpcMethod,
                "params": params is [Any] ? params : [params]
            ]

            let rpcData = try JSONSerialization.data(withJSONObject: rpcRequest, options: [])
            if let rpcJsonString = String(data: rpcData, encoding: .utf8) {
                print("🌐 [Web3Bridge] 🔄 Converted to JSON-RPC: \(rpcJsonString.prefix(200))...")
                try rpcService.handleIncomingRPC(jsonString: rpcJsonString) { [weak self] needsApproval, pending in
                    if needsApproval, let pending = pending {
                        DispatchQueue.main.async {
                            print("🌐 [Web3Bridge] 🎉 Needs user approval, popping up sheet...")
                            self?.viewModel.pendingRequest = pending
                            self?.viewModel.showSigningPrompt = true
                        }
                    }
                }
            }

        } catch {
            print("🌐 [Web3Bridge] ❌ Failed to handle RPC message: \(error.localizedDescription)")
        }
    }

    private func sendResponseToJS(responseJSON: String) {
        // trust-min.js expects:
        // - responseJSON is already the full JSON-RPC response
        // We need to extract id and result then call window.ethereum.sendResponse

        do {
            // Parse the JSON-RPC response to get id and result/error
            guard let data = responseJSON.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("🌐 [Web3Bridge] Invalid response JSON")
                return
            }

            let id = json["id"] as? Int ?? 0

            if let error = json["error"] {
                // Send error back to trust-min
                let errorMsg: String
                if let errorDict = error as? [String: Any], let message = errorDict["message"] as? String {
                    errorMsg = message
                } else {
                    errorMsg = String(describing: error)
                }
                let script = """
                if (window.ethereum && typeof window.ethereum.sendError === 'function') {
                    console.log("[native] Sending error back to trust-min id=\(id): \(errorMsg)");
                    window.ethereum.sendError(\(id), \(errorMsg));
                } else {
                    console.warn("[trust-min] window.ethereum.sendError not found");
                }
                """
                webView?.evaluateJavaScript(script, completionHandler: { result, error in
                    if let error = error {
                        print("🌐 [Web3Bridge] Error sending error to JS: \(error.localizedDescription)")
                    }
                })
            } else if let result = json["result"] {
                // Send success result back to trust-min
                print("🌐 [Web3Bridge] Sending success response back to trust-min id=\(id)")
                let resultJSON = try JSONSerialization.data(withJSONObject: result)
                let resultStr = String(data: resultJSON, encoding: .utf8)!
                let script = """
                if (window.ethereum && typeof window.ethereum.sendResponse === 'function') {
                    console.log("[native] Sending success response back to trust-min id=\(id)");
                    window.ethereum.sendResponse(\(id), \(resultStr));
                } else {
                    console.warn("[trust-min] window.ethereum.sendResponse not found");
                }
                """
                webView?.evaluateJavaScript(script, completionHandler: { result, error in
                    if let error = error {
                        print("🌐 [Web3Bridge] Error sending response to JS: \(error.localizedDescription)")
                    } else {
                        print("🌐 [Web3Bridge] Response sent to JS successfully")
                    }
                })
            }
        } catch {
            print("🌐 [Web3Bridge] Failed to serialize response: \(error.localizedDescription)")
        }
    }
}

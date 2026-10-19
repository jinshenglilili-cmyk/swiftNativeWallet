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
            // 0. 先装 console 转发：把 JS 控制台/全局错误打到原生日志（WKWebView 的 console 默认不可见）
            try {
                var nativeLog = function(level, args) {
                    try {
                        var text = Array.prototype.map.call(args, function(a) {
                            if (a instanceof Error) return a.name + ': ' + a.message + '\\n' + (a.stack || '');
                            if (typeof a === 'object' && a !== null) { try { return JSON.stringify(a); } catch(e2) { return String(a); } }
                            return String(a);
                        }).join(' ');
                        window.webkit.messageHandlers.ethereum.postMessage(JSON.stringify({
                            name: '__jsLog', id: 0, object: { level: level, text: text }
                        }));
                    } catch (e3) {}
                };
                ['log', 'warn', 'error'].forEach(function(level) {
                    var orig = console[level];
                    console[level] = function() { nativeLog(level, arguments); if (orig) orig.apply(console, arguments); };
                });
                window.onerror = function(msg, src, line, col, err) {
                    nativeLog('onerror', [msg + ' @' + src + ':' + line + ':' + col, err || '']);
                };
                window.addEventListener('unhandledrejection', function(ev) {
                    nativeLog('unhandledrejection', [ev.reason]);
                });
            } catch (e0) {}

            console.log("[native] ========== DEBUG START ==========");
            console.log("[native] Ensuring everything is correct...");

            // 1. FORCE ensure window.trustwallet.postMessage is our bridge
            //    注意：trust-min 的 Provider 按 (name, id, object) 三参数调用，
            //    这里必须用 ...args 透传，不能只收一个 obj（之前的单参数签名会丢参数）
            window.trustwallet = window.trustwallet || {};
            window.trustwallet.postMessage = function() {
                console.log("✅ [native-force] window.trustwallet.postMessage called!", JSON.stringify(Array.prototype.slice.call(arguments)));
                try {
                    var a = arguments;
                    var payload = (a.length >= 3) ? { name: a[0], id: a[1], object: a[2] } : a[0];
                    window.webkit.messageHandlers.ethereum.postMessage(JSON.stringify(payload));
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

            // 3+4. 完全接管 request：不再调用 trust-min 原生的 request
            //      （实测其内部 that._request 在页面加载后某刻会丢失——dApp 自带的
            //      CoinbaseWalletSDK 等脚本会动 provider 对象）。自包含实现：
            //      request → postMessage 桥 → 原生 sendResponse/sendError 兑现 Promise。
            (function() {
                if (!window.ethereum) return;
                var pendingCallbacks = {};
                var methodToHandler = {
                    'eth_requestAccounts': 'requestAccounts',
                    'personal_sign': 'signMessage',
                    'eth_signTransaction': 'signTransaction',
                    'eth_sendTransaction': 'sendTransaction'
                };
                function dispatch(payload) {
                    return new Promise(function(resolve, reject) {
                        var id = Math.floor(Math.random() * 900000000) + 100000000;
                        var handler = methodToHandler[payload.method] || payload.method;
                        var params = (payload.params && payload.params.length === 1) ? payload.params[0] : (payload.params || []);
                        pendingCallbacks[id] = { resolve: resolve, reject: reject };
                        console.log("[bridge] request ->", payload.method, "id=" + id);
                        try {
                            window.webkit.messageHandlers.ethereum.postMessage(JSON.stringify({
                                name: handler, id: id, object: params
                            }));
                        } catch (e) {
                            delete pendingCallbacks[id];
                            reject(e);
                        }
                    });
                }
                // _request 兜底：sendAsync / enable 等旧路径仍会调它
                window.ethereum._request = function(payload) {
                    return dispatch(typeof payload === 'string' ? { method: payload } : payload);
                };
                // 回调入口与 pendingCallbacks 配对（覆盖原型上的旧实现，
                // 旧实现查自己的 callbacks map，永远找不到我们的 id）
                window.ethereum.sendResponse = function(id, result) {
                    console.log("[bridge] sendResponse id=" + id);
                    var cb = pendingCallbacks[id];
                    if (cb) { delete pendingCallbacks[id]; cb.resolve(result); }
                };
                window.ethereum.sendError = function(id, error) {
                    console.log("[bridge] sendError id=" + id, error);
                    var cb = pendingCallbacks[id];
                    if (cb) { delete pendingCallbacks[id]; cb.reject(new Error(String(error))); }
                };
                // 接管 request：每次调用都走我们自己的 dispatch，不经 trust-min 的 request
                window.ethereum.request = function(args) {
                    console.log("👉 [bridge] request called:", JSON.stringify(args));
                    var payload = (typeof args === 'string') ? { method: args } : Object.assign({}, args);
                    return dispatch(payload);
                };
                // 回调状态挂到 window.__wcBridge：页面自带 SDK（实测 test-dapp 的
                // CoinbaseWalletSDK 会在加载后替换 window.ethereum，导致批准时
                // sendResponse 丢失），独立全局对象不受影响
                window.__wcBridge = {
                    dispatch: dispatch,
                    sendResponse: window.ethereum.sendResponse,
                    sendError: window.ethereum.sendError
                };
                // 锁定 window.ethereum，防止后续被页面脚本替换
                try {
                    Object.defineProperty(window, 'ethereum', {
                        value: window.ethereum, writable: false, configurable: false
                    });
                    console.log("[native] ✅ window.ethereum locked");
                } catch (eLock) {
                    console.warn("[bridge] lock ethereum failed:", String(eLock));
                }
                console.log("[native] ✅ full bridge request override installed");
            })();

            var result = {
                trustwalletExists: typeof window.trustwallet !== 'undefined',
                trustwalletPostMessageExists: typeof window.trustwallet !== 'undefined' && typeof window.trustwallet.postMessage === 'function',
                ethereumExists: typeof window.ethereum !== 'undefined',
                ethereumInTrustwallet: window.trustwallet && typeof window.trustwallet.ethereum !== 'undefined',
                trustwalletHas: Object.keys(window.trustwallet || {}),
                ethereumRequestExists: window.ethereum && typeof window.ethereum.request === 'function'
            };

            // 原型链探针：定位 _request 缺失的原因（实例到底是谁构造的）
            if (window.ethereum) {
                result.hasUnderscoreRequest = typeof window.ethereum._request;
                result.providerFnName = window.trustwallet.Provider && window.trustwallet.Provider.name;
                result.instanceOfProvider = window.trustwallet.Provider ? (window.ethereum instanceof window.trustwallet.Provider) : null;
                try {
                    var proto = Object.getPrototypeOf(window.ethereum);
                    result.instanceProtoMethods = proto ? Object.getOwnPropertyNames(proto).join('|') : 'null';
                    var chain = [];
                    var p = window.ethereum;
                    while (p && Object.getPrototypeOf(p)) {
                        p = Object.getPrototypeOf(p);
                        chain.push((p.constructor && p.constructor.name) || '?');
                    }
                    result.protoChain = chain.join(' -> ');
                } catch (e4) { result.protoErr = String(e4); }
            }

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

            // JS 控制台转发：仅打印，不进入 RPC 分发
            if methodName == "__jsLog" {
                let level = (json["object"] as? [String: Any])?["level"] as? String ?? "log"
                let text = (json["object"] as? [String: Any])?["text"] as? String ?? ""
                print("🌐 [JS.\(level)] \(text)")
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
                // errorMsg 必须作为 JS 字符串字面量注入（转义引号/反斜杠/换行），
                // 否则 sendError(id, 网络请求失败) 是非法 JS，错误永远送不回 dApp
                let escaped = errorMsg
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                let script = """
                (function() {
                    var err = "\(escaped)";
                    if (window.__wcBridge && typeof window.__wcBridge.sendError === 'function') {
                        console.log("[native] Sending error via __wcBridge id=\(id)");
                        window.__wcBridge.sendError(\(id), err);
                    } else if (window.ethereum && typeof window.ethereum.sendError === 'function') {
                        console.log("[native] Sending error via ethereum id=\(id)");
                        window.ethereum.sendError(\(id), err);
                    } else {
                        console.warn("[bridge] no sendError target; ethereum type=" + typeof window.ethereum);
                    }
                })()
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
                (function() {
                    // 优先走 __wcBridge（页面 SDK 可能已替换 window.ethereum）
                    if (window.__wcBridge && typeof window.__wcBridge.sendResponse === 'function') {
                        console.log("[native] Sending success response via __wcBridge id=\(id)");
                        window.__wcBridge.sendResponse(\(id), \(resultStr));
                    } else if (window.ethereum && typeof window.ethereum.sendResponse === 'function') {
                        console.log("[native] Sending success response via ethereum id=\(id)");
                        window.ethereum.sendResponse(\(id), \(resultStr));
                    } else {
                        console.warn("[bridge] no sendResponse target; ethereum type=" + typeof window.ethereum);
                    }
                })()
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

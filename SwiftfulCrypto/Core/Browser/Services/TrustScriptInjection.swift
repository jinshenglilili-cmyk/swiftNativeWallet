//
//  TrustScriptInjection.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import Foundation
import WebKit

/// Service to load and provide trust-min.js for injection into web view
class TrustScriptInjection {
    static let shared = TrustScriptInjection()

    private(set) var scriptContent: String?
    private(set) var userScript: WKUserScript?

    private init() {
        loadTrustScript()
    }

    private func loadTrustScript() {
        // First try bundle resource
        if let url = Bundle.main.url(forResource: "trust-min", withExtension: "js") {
            do {
                let content = try String(contentsOf: url)
                self.scriptContent = content
                createUserScript(content: content)
                return
            } catch {
                print("ERROR: Failed to load from bundle: \(error.localizedDescription)")
            }
        }

        // Fallback: load directly from project source
        let projectPath = "/Users/liwei/Desktop/newAPP/SwiftfulCrypto/trust-min.js"
        if FileManager.default.fileExists(atPath: projectPath) {
            do {
                let content = try String(contentsOfFile: projectPath)
                self.scriptContent = content
                createUserScript(content: content)
                print("SUCCESS: Loaded trust-min.js from project path (\(content.count) characters)")
                return
            } catch {
                print("ERROR: Failed to load from project path: \(error.localizedDescription)")
            }
        }

        print("ERROR: trust-min.js not found in any location")
    }

    private func createUserScript(content: String) {
        // FINAL CORRECT ORDER:
        // 1. trust-min.js runs first → it creates window.trustwallet = { Provider: ... }
        // 2. we run AFTER trust-min.js → ADD postMessage to the existing window.trustwallet
        // 3. then we create window.ethereum = new Provider()
        // This way trust-min doesn't overwrite us (since we add after it)!
        let glueCode = """
        (function() {
            console.log("[glue] ✅ trust-min.js loaded, now adding bridge...");

            // 1. Add postMessage to existing window.trustwallet that trust-min created
            // trust-min calls: window.trustwallet.postMessage(name, id, object) → 3 arguments!
            window.trustwallet = window.trustwallet || {};
            const ourPostMessage = function(name, id, object) {
                const obj = { name: name, id: id, object: object };
                console.log("✅ [trust-min] outgoing postMessage called!", JSON.stringify(obj));
                try {
                    console.log("✅ [trust-min] Sending to native...");
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ethereum) {
                        window.webkit.messageHandlers.ethereum.postMessage(JSON.stringify(obj));
                        console.log("✅ [trust-min] Message sent to native successfully!");
                    } else {
                        console.error("❌ [trust-min] window.webkit.messageHandlers.ethereum not found!");
                    }
                } catch (e) {
                    console.error("❌ [trust-min] Error sending postMessage:", e);
                }
            };
            window.trustwallet.postMessage = ourPostMessage;
            console.log("[glue] ✅ window.trustwallet.postMessage added after trust-min.js");

            // 2. Create window.ethereum - trust-min doesn't do it automatically
            // Provider requires a complete config object
            if (typeof window.trustwallet.Provider === 'function' && !window.ethereum) {
                console.log("[glue] Creating window.ethereum from Provider...");
                window.ethereum = new window.trustwallet.Provider({
                    isDebug: false,
                    ethereum: {
                        address: '',  // Required field expected by constructor
                    }
                });
                // MetaMask flag for DApps that check it
                window.ethereum.isMetaMask = true;

                // 🔥 FORCE OVERRIDE: ensure the provider uses OUR postMessage!
                // Even if something went wrong with constructor capturing, we fix it here
                if (window.ethereum && typeof window.ethereum.postMessage === 'function') {
                    const originalPostMessage = window.ethereum.postMessage;
                    window.ethereum.postMessage = function(...args) {
                        console.log("✅ [ethereum.postMessage] forcing to our bridge", args);
                        ourPostMessage(...args);
                    };
                    console.log("[glue] ✅ Forced override of ethereum.postMessage done");
                }

                console.log("[glue] ✅ window.ethereum created successfully! isMetaMask =", window.ethereum.isMetaMask);
            } else if (window.ethereum) {
                console.log("[glue] window.ethereum already exists, skipping creation");
                // Still force override to be sure!
                if (window.ethereum && typeof window.ethereum.postMessage === 'function') {
                    const originalPostMessage = window.ethereum.postMessage;
                    window.ethereum.postMessage = function(...args) {
                        console.log("✅ [ethereum.postMessage] forcing to our bridge (existing)", args);
                        ourPostMessage(...args);
                    };
                }
            } else {
                console.error("[glue] ❌ window.trustwallet.Provider is not a function");
                console.error("[glue] window.trustwallet keys:", Object.keys(window.trustwallet));
            }
        })();
        """

        // FINAL CORRECT ORDER: trust-min.js → our glue code (add postMessage + create ethereum)
        // trust-min creates the object, we just add the method we need
        let fullContent = content + "\n" + glueCode

        // Create user script with injection at document start
        // This ensures window.ethereum is available before DApp JS executes
        self.userScript = WKUserScript(
            source: fullContent,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )

        print("🌐 [TrustInjection] Created user script with glue code after trust-min, total size: \(fullContent.count) characters")
    }

    /// Get the configured user script for injection
    func getTrustUserScript() -> WKUserScript? {
        return userScript
    }

    /// Check if the script was loaded successfully
    var isScriptLoaded: Bool {
        return scriptContent != nil && userScript != nil
    }
}

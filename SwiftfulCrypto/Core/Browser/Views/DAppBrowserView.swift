//
//  DAppBrowserView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import SwiftUI
import WebKit

struct DAppBrowserView: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel
    let rpcService: Web3RPCService

    init(viewModel: BrowserViewModel, rpcService: Web3RPCService) {
        self.viewModel = viewModel
        self.rpcService = rpcService
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Add trust-min.js injection before page loads
        if let trustScript = TrustScriptInjection.shared.getTrustUserScript() {
            config.userContentController.addUserScript(trustScript)
        }

        // Register message handler for ethereum events from JS
        config.userContentController.add(context.coordinator, name: "ethereum")

        // Enable JavaScript - required for DApps
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Allow inline media playback
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Start observing progress
        context.coordinator.observeProgress(webView: webView)

        // Load initial URL
        if let initialURL = viewModel.initialURL {
            webView.load(URLRequest(url: initialURL))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Handle URL changes from view model
        if let url = viewModel.urlToLoad, url != webView.url {
            webView.load(URLRequest(url: url))
            viewModel.urlToLoad = nil
        }

        // Handle back/forward
        if viewModel.navigateBack && webView.canGoBack {
            webView.goBack()
            viewModel.navigateBack = false
        }

        if viewModel.navigateForward && webView.canGoForward {
            webView.goForward()
            viewModel.navigateForward = false
        }

        // Handle reload
        if viewModel.shouldReload {
            webView.reload()
            viewModel.shouldReload = false
        }

        // Update state async to avoid publishing during view update
        DispatchQueue.main.async {
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward
        }
    }

    func makeCoordinator() -> WebViewCoordinator {
        return WebViewCoordinator(viewModel: viewModel, rpcService: rpcService)
    }
}

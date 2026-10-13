//
//  BrowserViewModel.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import Foundation
import Combine
import WebKit

@MainActor
class BrowserViewModel: ObservableObject {
    // MARK: - Published state
    @Published var url: URL
    @Published var urlText: String = ""
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0
    @Published var showSigningPrompt: Bool = false
    @Published var pendingRequest: PendingRequest?

    // Navigation commands for DAppBrowserView
    @Published var urlToLoad: URL?
    @Published var navigateBack: Bool = false
    @Published var navigateForward: Bool = false
    @Published var shouldReload: Bool = false

    // MARK: - Dependencies
    let rpcService: Web3RPCService

    // MARK: - Constants
    private let defaultHomeURLString = "https://metamask.github.io/test-dapp/"
    var initialURL: URL? {
        URL(string: defaultHomeURLString)
    }

    init() {
        self.rpcService = Web3RPCService(profileViewModel: nil)
        // Set default URL
        self.url = URL(string: defaultHomeURLString)!
        self.urlText = defaultHomeURLString
    }

    // MARK: - Browser actions

    func loadURLFromText() {
        var urlString = urlText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add scheme if missing
        if !urlString.lowercased().starts(with: "http://") && !urlString.lowercased().starts(with: "https://") {
            urlString = "https://" + urlString
        }

        guard let newURL = URL(string: urlString) else {
            // Invalid URL, try searching
            print("Invalid URL: \(urlString)")
            return
        }

        url = newURL
        urlToLoad = newURL
        urlText = newURL.absoluteString
    }

    func goBack() {
        if canGoBack {
            navigateBack = true
        }
    }

    func goForward() {
        if canGoForward {
            navigateForward = true
        }
    }

    func reload() {
        shouldReload = true
    }

    func stopLoading() {
        isLoading = false
    }

    // MARK: - Request handling

    func approvePendingRequest() {
        guard let request = pendingRequest else { return }

        rpcService.approveRequest(requestId: request.requestId)
        pendingRequest = nil
        showSigningPrompt = false
    }

    func rejectPendingRequest() {
        guard let request = pendingRequest else { return }

        rpcService.rejectRequest(requestId: request.requestId)
        pendingRequest = nil
        showSigningPrompt = false
    }
}

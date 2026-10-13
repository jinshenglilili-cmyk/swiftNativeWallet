//
//  BrowserToolbarView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import SwiftUI

struct BrowserToolbarView: View {
    @Binding var urlText: String
    @Binding var progress: Double
    @Binding var isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let onGoBack: () -> Void
    let onGoForward: () -> Void
    let onReload: () -> Void
    let onStopLoading: () -> Void
    let onSubmitUrl: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Back button
                Button(action: onGoBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundColor(canGoBack ? Color.theme.accent : Color.theme.secondaryText)
                }
                .disabled(!canGoBack)

                // Forward button
                Button(action: onGoForward) {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(canGoForward ? Color.theme.accent : Color.theme.secondaryText)
                }
                .disabled(!canGoForward)

                // Refresh/Stop button
                Button(action: isLoading ? onStopLoading : onReload) {
                    Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(Color.theme.accent)
                }

                // Address bar
                TextField("Enter URL", text: $urlText, onCommit: onSubmitUrl)
                    .padding(8)
                    .background(Color.theme.background)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.theme.accent.opacity(0.3), lineWidth: 1)
                    )
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            .padding(.horizontal)

            // Progress bar
            if isLoading || progress < 1.0 {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color.theme.background.opacity(0.9))
    }
}

struct BrowserToolbarView_Previews: PreviewProvider {
    static var previews: some View {
        BrowserToolbarView(
            urlText: .constant("https://app.uniswap.org"),
            progress: .constant(0.7),
            isLoading: .constant(true),
            canGoBack: true,
            canGoForward: false,
            onGoBack: {},
            onGoForward: {},
            onReload: {},
            onStopLoading: {},
            onSubmitUrl: {}
        )
    }
}

//
//  SigningRequestView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import SwiftUI

struct SigningRequestView: View {
    let request: PendingRequest
    let accountAddress: String?
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.largeTitle)
                            .foregroundColor(Color.theme.accent)
                        Text(request.displayName)
                            .font(.title)
                            .fontWeight(.bold)
                        Text(request.description)
                            .font(.subheadline)
                            .foregroundColor(Color.theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)

                    // Account information
                    if let accountAddress = accountAddress {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("From Account")
                                .font(.headline)
                                .foregroundColor(Color.theme.accent)
                            Text(accountAddress)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color.theme.secondaryText)
                                .padding()
                                .background(Color.theme.background)
                                .cornerRadius(8)
                        }
                    }

                    // Request details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Method")
                            .font(.headline)
                            .foregroundColor(Color.theme.accent)
                        Text(request.method)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color.theme.secondaryText)
                            .padding()
                            .background(Color.theme.background)
                            .cornerRadius(8)

                        if let chainId = request.chainId {
                            Text("Chain ID")
                                .font(.headline)
                                .foregroundColor(Color.theme.accent)
                            Text("\(chainId)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color.theme.secondaryText)
                                .padding()
                                .background(Color.theme.background)
                                .cornerRadius(8)
                        }
                    }

                    Spacer()

                    // Buttons
                    HStack(spacing: 16) {
                        Button(action: onReject) {
                            Text("Reject")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(10)
                        }

                        Button(action: onApprove) {
                            Text("Approve")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.theme.accent)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.vertical)
                }
                .padding()
            }
            .background(Color.theme.background)
            .navigationBarTitle("Request Approval", displayMode: .inline)
        }
    }
}

struct SigningRequestView_Previews: PreviewProvider {
    static var previews: some View {
        SigningRequestView(
            request: PendingRequest(
                id: "1",
                method: "eth_sendTransaction",
                parameters: nil,
                chainId: 1,
                requestId: 1
            ),
            accountAddress: "0x742d35Cc6634C0532925a3b8865264350f352fef",
            onApprove: {},
            onReject: {}
        )
    }
}

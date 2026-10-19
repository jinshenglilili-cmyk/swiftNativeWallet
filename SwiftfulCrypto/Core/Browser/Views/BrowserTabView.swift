//
//  BrowserTabView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import SwiftUI

struct BrowserTabView: View {
    @EnvironmentObject private var profileVM: ProfileViewModel
    @EnvironmentObject private var externalWalletService: ExternalWalletService
    @StateObject private var viewModel: BrowserViewModel
    @State private var urlText: String = ""

    init() {
        // @StateObject can be initialized empty, we'll get real profile from environment on appear
        _viewModel = StateObject(wrappedValue: BrowserViewModel())
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Top toolbar with address bar and navigation buttons
                BrowserToolbarView(
                    urlText: $urlText,
                    progress: $viewModel.progress,
                    isLoading: $viewModel.isLoading,
                    canGoBack: viewModel.canGoBack,
                    canGoForward: viewModel.canGoForward,
                    onGoBack: { viewModel.goBack() },
                    onGoForward: { viewModel.goForward() },
                    onReload: { viewModel.reload() },
                    onStopLoading: { viewModel.stopLoading() },
                    onSubmitUrl: { viewModel.loadURLFromText() }
                )

                // dApp 端：连接外部钱包（MetaMask / Trust 等）入口
                externalWalletBar

                // Web view
                DAppBrowserView(
                    viewModel: viewModel,
                    rpcService: viewModel.rpcService
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 让网页延伸到屏幕物理底部（tab bar 之后区域），
                // 避免底部露出一条页面背景色断层；WKWebView 会自动处理
                // 底部安全区 inset，滚动到页面底部时内容不会被 tab bar 挡住
                .ignoresSafeArea(edges: .bottom)

                Spacer(minLength: 0)
            }
            .background(Color.theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $viewModel.showSigningPrompt) {
                if let request = viewModel.pendingRequest {
                    SigningRequestView(
                        request: request,
                        accountAddress: viewModel.rpcService.selectedAccount?.address,
                        onApprove: { viewModel.approvePendingRequest() },
                        onReject: { viewModel.rejectPendingRequest() }
                    )
                }
            }
            .onAppear {
                urlText = viewModel.urlText
            }
            .onChange(of: viewModel.urlText) { newValue in
                urlText = newValue
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            urlText = viewModel.urlText
            // Set initial selected account
            viewModel.rpcService.profileViewModel = profileVM
            viewModel.rpcService.selectedAccount = profileVM.selectedAccount
        }
        // Listen for selected account changes from profile
        .onChange(of: profileVM.selectedAccount) { newValue in
            viewModel.rpcService.selectedAccount = newValue
        }
    }

    /// 外部钱包状态条：未连接 → 「连接外部钱包」；已连接 → 钱包名 + 简要地址 + 断开
    @ViewBuilder private var externalWalletBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(externalWalletService.isConnected ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)

            if externalWalletService.isConnected {
                Text(externalWalletService.walletName ?? "外部钱包")
                    .font(.caption)
                    .foregroundColor(Color.theme.accent)
                if let address = externalWalletService.address {
                    Text("\(address.prefix(6))...\(address.suffix(4))")
                        .font(.caption2)
                        .foregroundColor(Color.theme.secondaryText)
                }
                Spacer()
                Button("断开") {
                    externalWalletService.disconnect()
                }
                .font(.caption)
                .foregroundColor(.red)
            } else {
                Text("未连接外部钱包")
                    .font(.caption)
                    .foregroundColor(Color.theme.secondaryText)
                Spacer()
                Button {
                    externalWalletService.presentWalletModal()
                } label: {
                    Label("连接外部钱包", systemImage: "link")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.theme.secondaryText.opacity(0.06))
        .overlay(
            // 请求出错/签名结果提示（轻量，3 秒后自动消失由下次操作覆盖）
            Group {
                if let error = externalWalletService.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        )
    }
}

struct BrowserTabView_Previews: PreviewProvider {
    static var previews: some View {
        BrowserTabView()
            .environmentObject(ProfileViewModel())
    }
}

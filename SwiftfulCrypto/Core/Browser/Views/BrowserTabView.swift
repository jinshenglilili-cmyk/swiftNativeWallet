//
//  BrowserTabView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import SwiftUI

struct BrowserTabView: View {
    @EnvironmentObject private var profileVM: ProfileViewModel
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
}

struct BrowserTabView_Previews: PreviewProvider {
    static var previews: some View {
        BrowserTabView()
            .environmentObject(ProfileViewModel())
    }
}

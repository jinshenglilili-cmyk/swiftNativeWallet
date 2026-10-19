//
//  MainTabView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var profileVM: ProfileViewModel
    // WalletConnect 钱包端（被 dApp 连接）与 dApp 端（连接外部钱包）服务
    @StateObject private var wcService: WalletConnectService
    @StateObject private var externalWalletService: ExternalWalletService

    init() {
        let vm = ProfileViewModel()
        _profileVM = StateObject(wrappedValue: vm)
        _wcService = StateObject(wrappedValue: WalletConnectService(profileViewModel: vm))
        _externalWalletService = StateObject(wrappedValue: ExternalWalletService())
    }

    var body: some View {
        TabView {
            homeTab
            browserTab
            profileTab
        }
        .environmentObject(profileVM)
        .environmentObject(wcService)
        .environmentObject(externalWalletService)
        // WC 会话请求可能在任意 tab 到达，审批弹窗挂在根部
        .modifier(WCApprovalSheets(
            service: wcService,
            accountAddress: { profileVM.selectedAccount?.address },
            // 配对 sheet 打开期间根部休眠，弹窗由配对页内的挂载点负责
            suppressed: wcService.pairSheetVisible
        ))
        .onAppear {
            wcService.configureIfNeeded()
            externalWalletService.configureIfNeeded()
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { wcService.alertMessage != nil },
                set: { if !$0 { wcService.alertMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(wcService.alertMessage ?? "")
        }
    }
}

/// WC 审批弹窗统一挂载点（会话提案 / 签名请求 / 全局错误提示）。
/// 这些弹窗可能出现在任意页面 —— 包括其他 sheet 已经弹出时
/// （SwiftUI 根部无法在已展示的 sheet 之上再弹 sheet），因此
/// 根部（MainTabView）和「连接 dApp」配对页（WCPairView）各挂载一份。
/// 两处绑定了同一个 service 状态，必须互斥：`suppressed` 为 true 的挂载点
/// 不参与弹出（配对页打开期间根部休眠），否则弹窗会闪现后被另一处取消。
struct WCApprovalSheets: ViewModifier {
    @ObservedObject var service: WalletConnectService
    let accountAddress: () -> String?
    /// true 时本挂载点休眠（不弹任何东西）
    var suppressed: Bool = false

    /// suppressed 期间 get 恒为 nil，本挂载点不会弹出；set 正常写回（关闭时清状态）
    private var pendingBinding: Binding<PendingRequest?> {
        Binding(
            get: { suppressed ? nil : service.pendingRequest },
            set: { service.pendingRequest = $0 }
        )
    }

    private var proposalBinding: Binding<WCProposalDisplay?> {
        Binding(
            get: { suppressed ? nil : service.proposal },
            set: { service.proposal = $0 }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: pendingBinding) { pending in
                SigningRequestView(
                    request: pending,
                    accountAddress: accountAddress()
                ) {
                    service.approvePendingRequest()
                } onReject: {
                    service.rejectPendingRequest()
                }
            }
            .sheet(item: proposalBinding) { proposal in
                WCProposalApprovalView(
                    proposal: proposal,
                    walletAddress: accountAddress()
                ) {
                    service.approveProposal()
                } onReject: {
                    service.rejectProposal()
                }
            }
            .alert(
                "提示",
                isPresented: Binding(
                    get: { !suppressed && service.alertMessage != nil },
                    set: { if !$0 { service.alertMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(service.alertMessage ?? "")
            }
    }
}

extension MainTabView {

    private var homeTab: some View {
        NavigationView {
            HomeView()
                .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .tabItem {
            Image(systemName: "house.fill")
            Text("首页")
        }
        .tag(0)
    }

    private var browserTab: some View {
        BrowserTabView()
            .tabItem {
                Image(systemName: "safari.fill")
                Text("浏览")
            }
            .tag(1)
    }

    private var profileTab: some View {
        Group {
            if #available(iOS 16.0, *) {
                // NavigationStack 修复了老 NavigationView 的 pop 过渡 bug：
                // 父页面隐藏导航栏 + 子页面显示导航栏时，返回会导致列表条目闪动
                NavigationStack {
                    ProfileView()
                        .toolbar(.hidden, for: .navigationBar)
                }
            } else {
                NavigationView {
                    ProfileView()
                        .navigationBarHidden(true)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .tabItem {
            Image(systemName: "person.fill")
            Text("我的")
        }
        .tag(2)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(DeveloperPreview.instance.homeVM)
    }
}

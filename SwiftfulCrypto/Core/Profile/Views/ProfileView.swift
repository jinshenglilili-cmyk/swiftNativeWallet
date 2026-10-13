//
//  ProfileView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import SwiftUI

struct ProfileView: View {

    @EnvironmentObject private var vm: ProfileViewModel
    @State private var showSettings: Bool = false
    @State private var showAccountSelector: Bool = false

    var body: some View {
        ZStack {
            // 使用与 List 一致的系统分组背景色（light=浅灰 #F2F2F7，dark=纯黑），
            // 避免 light 模式下头部是纯白、与下方 List 区域割裂；
            // ignoresSafeArea 让背景填满整个屏幕（含底部 tab bar 之后区域）
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                headerSection

                // 始终保留空间，只做显示/隐藏，避免布局跳动
                if let selectedAccount = vm.selectedAccount {
                    accountInfoSection(selectedAccount: selectedAccount)
                        .opacity(1)
                } else {
                    accountInfoSectionPlaceholder
                        .opacity(0)
                }

                commonFunctionsSection

                Spacer()
            }
            .padding(.top)
        }
        // 注意：不能加 .navigationTitle —— 宿主 MainTabView 已 navigationBarHidden(true)，
        // 两者同时存在会在滚动时弹出白色系统导航栏（头部白条的来源之一）
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showAccountSelector) {
            AccountSelectorView(vm: vm) { account in
                vm.selectAccount(account: account)
            }
        }
        // 不需要动画，因为布局不变，根本不会跳动
    }
}

extension ProfileView {

    private var headerSection: some View {
        HStack {
            Text("我的")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Color.theme.accent)

            Spacer()

            Button(action: {
                showSettings.toggle()
            }) {
                CircleButtonView(iconName: "gear")
            }
        }
        .padding(.horizontal)
    }

    private func accountInfoSection(selectedAccount: AccountModel) -> some View {
        VStack(spacing: 15) {
            Button {
                showAccountSelector.toggle()
            } label: {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前账号")
                                .font(.caption)
                                .foregroundColor(Color.theme.secondaryText)
                            HStack(alignment: .center, spacing: 4) {
                                Text(selectedAccount.name)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color.theme.accent)
                                if vm.selectedAccount?.id == selectedAccount.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .frame(width: 28, height: 28)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down.circle")
                            .foregroundColor(Color.theme.accent)
                            .font(.title)
                    }

                    HStack {
                        Text("[\(selectedAccount.chain.symbol)] \(formatAddress(selectedAccount.address))")
                            .font(.caption)
                                .foregroundColor(Color.theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }
                .padding()
                .background(Color.theme.secondaryText.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }

    // 占位符始终占据相同空间，避免布局跳动
    private var accountInfoSectionPlaceholder: some View {
        VStack(spacing: 15) {
            EmptyView()
        }
        .padding(.horizontal)
        .frame(height: 110) // 和实际高度保持一致
    }

    private var commonFunctionsSection: some View {
        List {
            // 标题作为 Section header 放在 List 内部，
            // 系统会自动让 header 紧贴分组卡片上方，无需手动抵消顶部留白
            Section(header: Text("常用功能")
                .font(.headline)
                .foregroundColor(Color.theme.accent)
            ) {
                    NavigationLink {
                        CreateAccountByMnemonicView(vm: vm)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundColor(.green)
                                .frame(width: 25)
                            Text("助记词创建账号")
                                .foregroundColor(Color.theme.accent)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.theme.background.opacity(0.5))

                    NavigationLink {
                        ImportAccountByPrivateKeyView(vm: vm)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("私钥导入账号")
                                .foregroundColor(Color.theme.accent)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.theme.background.opacity(0.5))

                    // 始终占据空间，只改变透明度，避免布局跳动
                    NavigationLink {
                        TransactionListView(selectedAccount: vm.selectedAccount)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.arrow.left.circle.fill")
                                .foregroundColor(.orange)
                                .frame(width: 25)
                            Text("转账")
                                .foregroundColor(Color.theme.accent)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.theme.background.opacity(0.5))
                    .opacity(vm.selectedAccount != nil ? 1 : 0)
                    .disabled(vm.selectedAccount == nil)

                    NavigationLink {
                        ExportAccountView()
                    } label: {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.purple)
                                .frame(width: 25)
                            Text("导出账号")
                                .foregroundColor(Color.theme.accent)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.theme.background.opacity(0.5))
                    .opacity(vm.selectedAccount != nil ? 1 : 0)
                    .disabled(vm.selectedAccount == nil)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private func formatAddress(_ address: String) -> String {
        if address.count <= 16 {
            return address
        }
        let prefix = String(address.prefix(8))
        let suffix = String(address.suffix(8))
        return "\(prefix)...\(suffix)"
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProfileView()
                .navigationBarHidden(true)
        }
    }
}

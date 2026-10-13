//
//  AddAccountView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import SwiftUI
import UIKit

struct AddAccountView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: ProfileViewModel

    @State private var accountName: String = ""
    @State private var accountAddress: String = ""
    @State private var selectedChain: ChainType = .bitcoin

    var body: some View {
        NavigationView {
            ZStack {
                Color.theme.background
                    .ignoresSafeArea()

                Form {
                    accountInfoSection
                }
                .background(Color.theme.background)
            }
            .navigationTitle("添加账号")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        save()
                    }
                    .foregroundColor(Color.theme.accent)
                    .disabled(!canSave)
                }
            }
        }
    }
}

extension AddAccountView {

    private var canSave: Bool {
        !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accountAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var accountInfoSection: some View {
        Section {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("账号名称")
                        .foregroundColor(Color.theme.accent)
                        .font(.headline)
                    TextField("例如: 我的主钱包", text: $accountName)
                        .foregroundColor(Color.theme.accent)
                        .padding()
                        .background(Color.theme.secondaryText.opacity(0.1))
                        .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("公链")
                        .foregroundColor(Color.theme.accent)
                        .font(.headline)
                    Picker("选择公链", selection: $selectedChain) {
                        ForEach(ChainType.allCases) { chain in
                            Text(chain.name).tag(chain)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("钱包地址")
                        .foregroundColor(Color.theme.accent)
                        .font(.headline)
                    TextField("输入钱包地址", text: $accountAddress)
                        .foregroundColor(Color.theme.accent)
                        .padding()
                        .background(Color.theme.secondaryText.opacity(0.1))
                        .cornerRadius(8)
                }

                HStack {
                    Button {
                        // 异步读取确保拿到剪切板最新内容
                        DispatchQueue.main.async {
                            if let pasteboardString = UIPasteboard.general.string {
                                accountAddress = pasteboardString.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    } label: {
                        Text("粘贴剪贴板")
                            .foregroundColor(.blue)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    Spacer()
                }
                .padding(.top, 8)
            }
            .listRowBackground(Color.theme.background.opacity(0.5))
        }
    }

    private func save() {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = accountAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty && !trimmedAddress.isEmpty else { return }

        vm.addAccount(name: trimmedName, address: trimmedAddress, chain: selectedChain)
        dismiss()
    }
}

struct AddAccountView_Previews: PreviewProvider {
    static var previews: some View {
        AddAccountView(vm: ProfileViewModel())
    }
}

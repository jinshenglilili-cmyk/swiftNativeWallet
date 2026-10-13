//
//  AccountSelectorView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import SwiftUI

struct AccountSelectorView: View {

    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var vm: ProfileViewModel
    let onSelect: (AccountModel) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                Color.theme.background
                    .ignoresSafeArea()

                List {
                    ForEach(vm.accounts) { account in
                        Button {
                            onSelect(account)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name)
                                        .font(.headline)
                                        .foregroundColor(Color.theme.accent)
                                    Text("[\(account.chain.name)] \(formatAddress(account.address))")
                                        .font(.caption)
                                        .foregroundColor(Color.theme.secondaryText)
                                }
                                Spacer()
                                if vm.selectedAccount?.id == account.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(Color.theme.background.opacity(0.5))
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("选择账号")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(Color.theme.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .foregroundColor(Color.theme.accent)
                }
            }
        }
    }
}

extension AccountSelectorView {

    private func formatAddress(_ address: String) -> String {
        if address.count <= 16 {
            return address
        }
        let prefix = String(address.prefix(8))
        let suffix = String(address.suffix(8))
        return "\(prefix)...\(suffix)"
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            let account = vm.accounts[offset]
            vm.deleteAccount(account: account)
        }
    }
}

struct AccountSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        AccountSelectorView(vm: ProfileViewModel(), onSelect: { _ in })
    }
}

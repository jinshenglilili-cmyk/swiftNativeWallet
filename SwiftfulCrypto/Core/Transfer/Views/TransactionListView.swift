//
//  TransactionListView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/23.
//

import SwiftUI

struct TransactionListView: View {

    @StateObject private var vm = TransactionListViewModel()
    @State private var showCreateTransaction = false
    @Environment(\.presentationMode) private var presentationMode

    let selectedAccount: AccountModel?

    init(selectedAccount: AccountModel?) {
        self.selectedAccount = selectedAccount
    }

    var body: some View {
        ZStack {
            Color.theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection

                if vm.transactions.isEmpty {
                    emptyState
                } else {
                    transactionsList
                }
            }
        }
        .navigationTitle("转账记录")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreateTransaction) {
            if let selectedAccount = selectedAccount {
                CreateTransactionView(
                    selectedAccount: selectedAccount,
                    isPresented: $showCreateTransaction,
                    onTransactionCreated: {
                        showCreateTransaction = false
                    },
                    vm: vm
                )
            }
        }
    }
}

extension TransactionListView {

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("转账记录")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.theme.accent)

                Spacer()

                Button(action: {
                    vm.refreshTransactions()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Color.theme.accent)
                        .font(.title2)
                        .rotationEffect(Angle(degrees: vm.isLoading ? 360 : 0))
                        .animation(vm.isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.isLoading)
                }
                .disabled(vm.isLoading)

                Button(action: {
                    if selectedAccount != nil {
                        showCreateTransaction = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("新建转账")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedAccount != nil ? Color.theme.accent : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(selectedAccount == nil)
            }

            if selectedAccount == nil {
                Text("请先在'我的'页面选择一个账户")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color.theme.background)
    }

    private var transactionsList: some View {
        List {
            ForEach(vm.transactions) { transaction in
                TransactionRowView(transaction: transaction)
                    .listRowBackground(Color.theme.background.opacity(0.5))
            }
            .onDelete(perform: vm.deleteTransaction)
        }
        .listStyle(InsetGroupedListStyle())
        .refreshable {
            vm.refreshTransactions()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.right.arrow.left.circle")
                .font(.system(size: 60))
                .foregroundColor(Color.theme.secondaryText)
            Text("暂无转账记录")
                .font(.title2)
                .foregroundColor(Color.theme.accent)
            Text("点击上方\"新建转账\"开始您的第一次转账")
                .font(.caption)
                .foregroundColor(Color.theme.secondaryText)
            if selectedAccount == nil {
                Text("提示：请先在'我的'页面选择一个账户")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TransactionRowView: View {

    let transaction: TransactionModel

    var body: some View {
        VStack(spacing: 12) {
            // 金额和状态
            HStack {
                Text("\(amountString) \(transaction.chain.symbol)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.theme.accent)

                Spacer()

                StatusTag(status: transaction.status)
            }

            // 发送地址
            HStack {
                Text("发件地址：")
                    .font(.caption)
                    .foregroundColor(Color.theme.secondaryText)

                Text(formatAddress(transaction.fromAddress))
                    .font(.caption)
                    .foregroundColor(Color.theme.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }

            // 接收地址
            HStack {
                Text("接收地址：")
                    .font(.caption)
                    .foregroundColor(Color.theme.secondaryText)

                Text(formatAddress(transaction.toAddress))
                    .font(.caption)
                    .foregroundColor(Color.theme.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }

            // 链和时间
            HStack {
                Text(transaction.chain.name)
                    .font(.caption)
                    .foregroundColor(Color.theme.accent)

                Spacer()

                Text(transaction.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(Color.theme.secondaryText)
            }

            // 如果有交易哈希，显示出来
            if let txHash = transaction.txHash {
                HStack {
                    Text("交易哈希：")
                        .font(.caption)
                        .foregroundColor(Color.theme.secondaryText)

                    Text(formatTxHash(txHash))
                        .font(.caption)
                        .foregroundColor(Color.theme.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var amountString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSNumber(value: transaction.amount)) ?? "\(transaction.amount)"
    }

    private func formatAddress(_ address: String) -> String {
        if address.count <= 16 {
            return address
        }
        let prefix = String(address.prefix(8))
        let suffix = String(address.suffix(8))
        return "\(prefix)...\(suffix)"
    }

    private func formatTxHash(_ hash: String) -> String {
        if hash.count <= 20 {
            return hash
        }
        let prefix = String(hash.prefix(10))
        let suffix = String(hash.suffix(10))
        return "\(prefix)...\(suffix)"
    }
}

struct StatusTag: View {
    let status: TransactionStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor)
            .cornerRadius(4)
    }

    private var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .success: return .green
        case .failed: return .red
        }
    }
}

struct TransactionListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TransactionListView(selectedAccount: nil)
        }
    }
}

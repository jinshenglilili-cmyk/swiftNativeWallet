//
//  TransactionListViewModel.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/23.
//

import Foundation
import Combine

class TransactionListViewModel: ObservableObject {

    @Published var transactions: [TransactionModel] = []
    @Published var isLoading: Bool = false

    private let userDefaultsKey = "savedTransactions"
    private let cancellables = CancelBag()

    init() {
        loadTransactions()
    }

    func addTransaction(
        fromAccountId: UUID,
        fromAddress: String,
        toAddress: String,
        amount: Double,
        chain: ChainType
    ) -> TransactionModel {
        let transaction = TransactionModel(
            fromAccountId: fromAccountId,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            chain: chain,
            status: .pending
        )

        // 插入到最前面，最新的显示在最上面
        transactions.insert(transaction, at: 0)
        saveTransactions()

        // 模拟网络延迟更新状态
        simulateTransactionConfirmation(transaction: transaction)

        return transaction
    }

    func updateTransactionStatus(id: UUID, status: TransactionStatus, txHash: String? = nil) {
        guard let index = transactions.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updatedTransaction = transactions[index]
        updatedTransaction.updateStatus(status, txHash: txHash)
        transactions[index] = updatedTransaction
        saveTransactions()
    }

    func deleteTransaction(at offsets: IndexSet) {
        transactions.remove(atOffsets: offsets)
        saveTransactions()
    }

    func refreshTransactions() {
        isLoading = true
        // 模拟刷新延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isLoading = false
            self?.loadTransactions()
        }
    }

    private func simulateTransactionConfirmation(transaction: TransactionModel) {
        // 模拟区块链确认延迟：随机 3-10 秒
        let delay = Double.random(in: 3...10)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }

            // 90% 概率成功，10% 概率失败（模拟真实场景）
            let isSuccess = Double.random(in: 0...1) > 0.1

            if isSuccess {
                // 生成一个模拟的tx hash
                let mockTxHash = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                self.updateTransactionStatus(
                    id: transaction.id,
                    status: .success,
                    txHash: mockTxHash
                )
            } else {
                self.updateTransactionStatus(
                    id: transaction.id,
                    status: .failed
                )
            }
        }
    }

    private func saveTransactions() {
        do {
            let data = try JSONEncoder().encode(transactions)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Error saving transactions: \(error)")
        }
    }

    private func loadTransactions() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            transactions = []
            return
        }
        do {
            transactions = try JSONDecoder().decode([TransactionModel].self, from: data)
        } catch {
            print("Error loading transactions: \(error)")
            transactions = []
        }
    }
}

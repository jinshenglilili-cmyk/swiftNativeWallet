//
//  WCWalletSocketFactory.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation
import ReownWalletKit

/// 基于 URLSessionWebSocketTask 的 WebSocketFactory（reown-swift 不自带实现，
/// 官方示例用 Starscream，这里用系统 API 避免额外依赖）
final class WCWalletSocketFactory: WebSocketFactory {

    func create(with url: URL) -> WebSocketConnecting {
        WCWalletSocket(url: url)
    }
}

final class WCWalletSocket: NSObject, WebSocketConnecting {

    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private let workQueue = DispatchQueue(label: "com.swiftfulcrypto.wc.socket", qos: .utility)

    var isConnected: Bool {
        webSocketTask != nil
    }

    init(url: URL) {
        request = URLRequest(url: url)
        // 长连接会话：禁用默认超时，保持 SDK 自行管理重连
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = .infinity
        session = URLSession(configuration: configuration)
        super.init()
    }

    func connect() {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let task = self.session.webSocketTask(with: self.request)
            task.delegate = self
            self.webSocketTask = task
            task.resume()
            self.receiveNextMessage()
        }
    }

    func disconnect() {
        workQueue.async { [weak self] in
            guard let task = self?.webSocketTask else { return }
            self?.webSocketTask = nil
            task.cancel(with: .goingAway, reason: nil)
        }
        onDisconnect?(nil)
    }

    func write(string: String, completion: (() -> Void)?) {
        workQueue.async { [weak self] in
            guard let task = self?.webSocketTask else {
                completion?()
                return
            }
            task.send(.string(string)) { _ in
                completion?()
            }
        }
    }

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.onText?(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.onText?(text)
                    }
                @unknown default:
                    break
                }
                // Relay 依赖持续接收，继续挂起下一次
                self?.receiveNextMessage()
            case .failure(let error):
                guard self?.webSocketTask != nil else { return } // 主动断开导致的取消
                self?.webSocketTask = nil
                self?.onDisconnect?(error)
            }
        }
    }
}

extension WCWalletSocket: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        onConnect?()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard isConnected else { return }
        self.webSocketTask = nil
        onDisconnect?(nil)
    }
}

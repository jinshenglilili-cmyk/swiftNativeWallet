//
//  AccountModel.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import Foundation

struct AccountModel: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let address: String
    let chain: ChainType
    let createdAt: Date
    // 敏感字段：随账号 JSON 一起存入 Keychain（不存 UserDefaults）
    // 助记词账号存 mnemonic，私钥导入账号存 privateKeyHex
    var mnemonic: String?
    var privateKeyHex: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case chain
        case createdAt
        case mnemonic
        case privateKeyHex
    }

    init(id: UUID = UUID(), name: String, address: String, chain: ChainType, mnemonic: String? = nil, privateKeyHex: String? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.chain = chain
        self.createdAt = Date()
        self.mnemonic = mnemonic
        self.privateKeyHex = privateKeyHex
    }

    // 自定义 Codable：旧版本存储的数据没有 mnemonic/privateKeyHex 字段，
    // 用 decodeIfPresent 保证旧数据能继续解码
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        chain = try container.decode(ChainType.self, forKey: .chain)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        mnemonic = try container.decodeIfPresent(String.self, forKey: .mnemonic)
        privateKeyHex = try container.decodeIfPresent(String.self, forKey: .privateKeyHex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(chain, forKey: .chain)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(mnemonic, forKey: .mnemonic)
        try container.encodeIfPresent(privateKeyHex, forKey: .privateKeyHex)
    }
}

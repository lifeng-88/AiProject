//
//  FavoriteModels.swift
//  bbb
//
//  ShopInterface 收藏：POST/DELETE/GET /v1/favorites（swagger v1/shop_interface.proto）
//

import Foundation

// MARK: - Create / Delete

struct CreateFavoriteResponse: Codable {
    let ok: Bool?
}

struct DeleteFavoriteResponse: Codable {
    let ok: Bool?
}

// MARK: - List (GET /v1/favorites)

struct FavoriteListItem: Codable, Identifiable {
    let targetType: Int32
    let targetId: String
    let coverUrl: String?
    let createTs: String?

    var id: String { "\(targetType):\(targetId)" }

    enum CodingKeys: String, CodingKey {
        case targetType
        case targetId
        case coverUrl
        case createTs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetType = try FavoriteListItem.decodeInt32(from: c, key: .targetType)
        targetId = try FavoriteListItem.decodeTargetId(from: c)
        coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        createTs = try c.decodeIfPresent(String.self, forKey: .createTs)
    }

    private static func decodeInt32(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Int32 {
        if let v = try? c.decode(Int32.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int32(s) { return v }
        throw DecodingError.typeMismatch(Int32.self, DecodingError.Context(codingPath: c.codingPath + [key], debugDescription: "targetType"))
    }

    private static func decodeTargetId(from c: KeyedDecodingContainer<CodingKeys>) throws -> String {
        if let s = try? c.decode(String.self, forKey: .targetId) { return s }
        if let n = try? c.decode(Int64.self, forKey: .targetId) { return String(n) }
        return ""
    }
}

struct ListFavoritesResponse: Decodable {
    let favorites: [FavoriteListItem]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case favorites
        case nextPageToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try c.decodeIfPresent([FavoriteListItem].self, forKey: .favorites) ?? []
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

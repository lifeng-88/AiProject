//
//  FavoritesAPI.swift
//  bbb
//
//  ShopInterface：GET/POST /v1/favorites，DELETE /v1/favorites/{targetType}/{targetId}
//

import Foundation

struct FavoritesAPI {
    static let client = APIClient.shared

    /// 收藏资源（POST /v1/favorites）
    static func createFavorite(targetType: Int32, targetId: String) async -> Result<CreateFavoriteResponse, AppError> {
        let body: [String: Any] = [
            "targetType": targetType,
            "targetId": targetId
        ]
        return await client.request(
            "/v1/favorites",
            method: .post,
            parameters: body
        )
    }

    /// 取消收藏（DELETE /v1/favorites/{targetType}/{targetId}）
    static func deleteFavorite(targetType: Int32, targetId: String) async -> Result<DeleteFavoriteResponse, AppError> {
        let encodedId = targetId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? targetId
        return await client.request(
            "/v1/favorites/\(targetType)/\(encodedId)",
            method: .delete
        )
    }

    /// 收藏列表（GET /v1/favorites）；`targetType == 0` 表示全部分类
    static func listFavorites(targetType: Int32? = nil, pageSize: Int32? = nil, pageToken: String? = nil) async -> Result<ListFavoritesResponse, AppError> {
        var params: [String: Any] = [:]
        if let t = targetType { params["targetType"] = t }
        if let s = pageSize { params["pageSize"] = s }
        if let tok = pageToken, !tok.isEmpty { params["pageToken"] = tok }
        return await client.request(
            "/v1/favorites",
            method: .get,
            parameters: params.isEmpty ? nil : params
        )
    }

    /// 首页爱心：收藏 / 取消收藏
    static func setFavorite(templateId: String, kind: TemplateResourceKind, favorited: Bool) async -> Result<Bool, AppError> {
        let tt = kind.favoriteTargetType
        if favorited {
            let r = await createFavorite(targetType: tt, targetId: templateId)
            switch r {
            case .success(let resp):
                if resp.ok == false {
                    return .failure(.serverError(code: 200, message: "Favorite failed"))
                }
                return .success(true)
            case .failure(let e):
                return .failure(e)
            }
        } else {
            let r = await deleteFavorite(targetType: tt, targetId: templateId)
            switch r {
            case .success(let resp):
                if resp.ok == false {
                    return .failure(.serverError(code: 200, message: "Unfavorite failed"))
                }
                return .success(true)
            case .failure(let e):
                return .failure(e)
            }
        }
    }
}

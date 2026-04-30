//
//  FeedbackAPI.swift
//  glam
//
//  User feedback API (POST /v1/feedback, GET /v1/feedbacks, GET /v1/feedbacks/{id}).
//  See glam-svr/docs/user-feedback-api.md.
//

import Foundation

struct FeedbackAPI {
    static let client = APIClient.shared

    /// Submit feedback
    static func submitFeedback(request: CreateFeedbackRequest) async -> Result<CreateFeedbackResponse, AppError> {
        await client.request(
            "/v1/feedback",
            method: .post,
            parameters: request.toParameters()
        )
    }

    /// List current user's feedbacks (paginated)；查询参数与 swagger `page_size` / `page_token` 一致
    static func listFeedbacks(pageToken: String? = nil, pageSize: Int32 = 20) async -> Result<ListFeedbacksResponse, AppError> {
        var params: [String: Any] = ["page_size": pageSize]
        if let t = pageToken, !t.isEmpty {
            params["page_token"] = t
        }
        return await client.request(
            "/v1/feedbacks",
            method: .get,
            parameters: params.isEmpty ? nil : params
        )
    }

    /// Get feedback detail by id
    static func getFeedback(id: Int64) async -> Result<FeedbackItem, AppError> {
        let result: Result<GetFeedbackResponseWrapper, AppError> = await client.request(
            "/v1/feedbacks/\(id)",
            method: .get
        )
        switch result {
        case .success(let w): return .success(w.item)
        case .failure(let e): return .failure(e)
        }
    }
}

private struct GetFeedbackResponseWrapper: Decodable {
    let item: FeedbackItem
    enum CodingKeys: String, CodingKey { case item }
}

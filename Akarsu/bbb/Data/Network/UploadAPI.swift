//
//  UploadAPI.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Foundation

/// 上传响应模型
struct UploadResponse: Codable {
    let url: String
}

/// 上传相关 API
struct UploadAPI {
    static let client = APIClient.shared
    
    /// 上传图片
    /// - Parameters:
    ///   - imageData: 图片数据
    ///   - fileName: 文件名（可选，默认使用时间戳）
    ///   - type: 上传类型（如："input"）
    ///   - progressHandler: 进度回调（0.0 - 1.0）
    /// - Returns: 上传结果，包含图片 URL
    static func uploadImage(
        imageData: Data,
        fileName: String? = nil,
        type: String = "input",
        progressHandler: ((Double) -> Void)? = nil
    ) async -> Result<UploadResponse, AppError> {
        let finalFileName = fileName ?? "image_\(Int(Date().timeIntervalSince1970)).jpg"
        let mimeType = "image/jpeg"
        
        let parameters: [String: String] = [
            "type": type
        ]
        
        return await client.uploadFile(
            "/v1/upload",
            fileData: imageData,
            fileName: finalFileName,
            mimeType: mimeType,
            parameters: parameters,
            progressHandler: progressHandler
        )
    }
}

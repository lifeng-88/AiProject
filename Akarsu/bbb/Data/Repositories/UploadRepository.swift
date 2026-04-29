//
//  UploadRepository.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Foundation

/// 上传 Repository
struct UploadRepository {
    static let shared = UploadRepository()
    
    private init() {}
    
    /// 上传图片（带重试机制）
    /// - Parameters:
    ///   - imageData: 图片数据
    ///   - fileName: 文件名（可选）
    ///   - type: 上传类型（默认："input"）
    ///   - maxRetries: 最大重试次数（默认：3）
    ///   - progressHandler: 进度回调
    /// - Returns: 上传结果，包含图片 URL
    func uploadImage(
        imageData: Data,
        fileName: String? = nil,
        type: String = "input",
        maxRetries: Int = 3,
        progressHandler: ((Double) -> Void)? = nil
    ) async -> Result<String, AppError> {
        var lastError: AppError?
        
        for attempt in 1...maxRetries {
            if attempt > 1 {
                // 重试前等待（指数退避）
                let delay = min(Double(attempt - 1) * 0.5, 2.0)
                print("🔄 [UploadRepository] Retrying upload (attempt \(attempt)/\(maxRetries)) after \(delay)s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            let result = await UploadAPI.uploadImage(
                imageData: imageData,
                fileName: fileName,
                type: type,
                progressHandler: progressHandler
            )
            
            switch result {
            case .success(let response):
                print("✅ [UploadRepository] Upload successful: \(response.url)")
                return .success(response.url)
            case .failure(let error):
                lastError = error
                print("❌ [UploadRepository] Upload failed (attempt \(attempt)/\(maxRetries)): \(error)")
                
                // 如果是 401 错误，不重试（Token 刷新已经在 APIClient 中处理）
                if case .unauthorized = error {
                    return .failure(error)
                }
                
                // 如果是客户端错误（4xx），不重试
                if case .serverError(let code, _) = error, (400..<500).contains(code) {
                    return .failure(error)
                }
            }
        }
        
        // 所有重试都失败
        return .failure(lastError ?? .networkError("Upload failed after \(maxRetries) attempts"))
    }
    
    /// 批量上传图片
    /// - Parameters:
    ///   - images: 图片数据数组
    ///   - type: 上传类型（默认："input"）
    ///   - progressHandler: 总进度回调（0.0 - 1.0）
    /// - Returns: 上传结果，包含所有图片 URL 数组
    func uploadImages(
        images: [Data],
        type: String = "input",
        progressHandler: ((Double) -> Void)? = nil
    ) async -> Result<[String], AppError> {
        var uploadedURLs: [String] = []
        let totalCount = images.count
        
        for (index, imageData) in images.enumerated() {
            // 计算当前图片的进度范围
            let startProgress = Double(index) / Double(totalCount)
            let endProgress = Double(index + 1) / Double(totalCount)
            
            let imageProgressHandler: ((Double) -> Void)? = progressHandler.map { handler in
                { progress in
                    // 将单个图片的进度映射到总进度
                    let totalProgress = startProgress + (endProgress - startProgress) * progress
                    handler(totalProgress)
                }
            }
            
            let result = await uploadImage(
                imageData: imageData,
                type: type,
                progressHandler: imageProgressHandler
            )
            
            switch result {
            case .success(let url):
                uploadedURLs.append(url)
            case .failure(let error):
                print("❌ [UploadRepository] Failed to upload image \(index + 1)/\(totalCount): \(error)")
                return .failure(error)
            }
        }
        
        return .success(uploadedURLs)
    }
}

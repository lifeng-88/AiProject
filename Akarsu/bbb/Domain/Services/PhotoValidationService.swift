//
//  PhotoValidationService.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Foundation
import UIKit
import Vision

/// 照片质量验证错误类型
enum PhotoValidationError: LocalizedError, Hashable {
    case noPersonFound
    case multiplePeopleDetected
    case faceSeverelyOffsetOrObscured
    
    var errorDescription: String? {
        switch self {
        case .noPersonFound:
            return AppLanguageStore.localized("photo_validation.error.no_person")
        case .multiplePeopleDetected:
            return AppLanguageStore.localized("photo_validation.error.multiple_people")
        case .faceSeverelyOffsetOrObscured:
            return AppLanguageStore.localized("photo_validation.error.face_offset_or_obscured")
        }
    }
}

/// 照片质量验证结果
struct PhotoValidationResult {
    let isValid: Bool
    let errors: [PhotoValidationError]
}

/// 照片质量验证服务
/// 使用 Vision 框架进行人脸检测和质量验证
class PhotoValidationService {
    static let shared = PhotoValidationService()
    
    private init() {}
    
    /// 验证照片质量
    /// - Parameter image: 待验证的照片
    /// - Returns: 验证结果
    @MainActor
    func validatePhoto(_ image: UIImage) async -> PhotoValidationResult {
        guard let cgImage = image.cgImage else {
            print("❌ [PhotoValidationService] Failed to get CGImage from UIImage")
            return PhotoValidationResult(isValid: false, errors: [.noPersonFound])
        }
        
        // Vision 请求必须在后台线程执行
        return await Task.detached(priority: .userInitiated) {
            await self.performFaceDetection(cgImage: cgImage)
        }.value
    }
    
    /// 执行人脸检测（在后台线程）
    private func performFaceDetection(cgImage: CGImage) async -> PhotoValidationResult {
        var errors: [PhotoValidationError] = []
        
        // 获取图片方向（如果需要）
        let orientation: CGImagePropertyOrientation = .up
        
        // 创建人脸检测请求（使用更宽松的配置以提高检测率）
        let faceDetectionRequest = VNDetectFaceLandmarksRequest { request, error in
            if let error = error {
                let nsError = error as NSError
                // 检查是否是 inference context 错误（Code 9）
                if nsError.code == 9 {
                    print("⚠️ [PhotoValidationService] Vision inference context error (Code 9) - This may occur in simulator or due to image format issues")
                } else {
                    print("❌ [PhotoValidationService] Face detection error: \(error)")
                }
            }
        }
        
        // 设置更宽松的检测配置
        // revision 2 使用更准确的检测算法
        faceDetectionRequest.revision = VNDetectFaceLandmarksRequestRevision2
        
        // 执行人脸检测
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        
        do {
            try handler.perform([faceDetectionRequest])
            
            guard let observations = faceDetectionRequest.results, !observations.isEmpty else {
                // 未检测到人脸，尝试使用更简单的人脸矩形检测作为备选
                print("⚠️ [PhotoValidationService] No faces detected with landmarks, trying rectangle detection...")
                return await tryAlternativeFaceDetection(cgImage: cgImage, orientation: orientation)
            }
            
            print("✅ [PhotoValidationService] Detected \(observations.count) face(s)")
            
            // 验证人脸数量
            if observations.count > 1 {
                print("⚠️ [PhotoValidationService] Multiple people detected: \(observations.count)")
                errors.append(.multiplePeopleDetected)
            } else {
                // 只有一个人脸，验证人脸角度和质量
                if let faceObservation = observations.first {
                    let confidence = faceObservation.confidence
                    let boundingBox = faceObservation.boundingBox
                    
                    print("📊 [PhotoValidationService] Face confidence: \(confidence), boundingBox: \(boundingBox)")
                    
                    // 降低置信度阈值，提高检测灵敏度（从0.5降到0.3）
                    // 降低 boundingBox 大小阈值（从0.1降到0.05），允许更小的人脸
                    if confidence < 0.3 || boundingBox.width < 0.05 || boundingBox.height < 0.05 {
                        print("⚠️ [PhotoValidationService] Face quality too low: confidence=\(confidence), size=\(boundingBox.width)x\(boundingBox.height)")
                        errors.append(.faceSeverelyOffsetOrObscured)
                    } else {
                        // 检查人脸角度（roll 角度）
                        // roll 角度表示人脸绕 Z 轴的旋转（左右转头）
                        // 正面为 0 度，超过 90 度（±90度）则认为人脸严重偏移
                        // roll 值以弧度为单位，范围约为 -π 到 π（-180度到180度）
                        if let rollNumber = faceObservation.roll {
                            let roll = rollNumber.doubleValue // 转换为 Double
                            let rollAngleDegrees = abs(roll) * 180 / .pi // 转换为度数
                            
                            print("📐 [PhotoValidationService] Face roll angle: \(rollAngleDegrees) degrees")
                            
                            // 转头角度超过 90 度则提示错误
                            if rollAngleDegrees > 90 {
                                print("⚠️ [PhotoValidationService] Face severely rotated: \(rollAngleDegrees) degrees")
                                errors.append(.faceSeverelyOffsetOrObscured)
                            }
                        } else {
                            // 如果无法检测到 roll 角度，但置信度足够高，仍然认为有效
                            // 只有在置信度很低时才认为是错误
                            if confidence < 0.4 {
                                print("⚠️ [PhotoValidationService] Low confidence without roll angle: \(confidence)")
                                errors.append(.faceSeverelyOffsetOrObscured)
                            }
                        }
                    }
                }
            }
            
            // 返回验证结果
            let result = PhotoValidationResult(
                isValid: errors.isEmpty,
                errors: errors
            )
            
            if result.isValid {
                print("✅ [PhotoValidationService] Photo validation passed")
            } else {
                print("❌ [PhotoValidationService] Photo validation failed: \(errors)")
            }
            
            return result
            
        } catch {
            let nsError = error as NSError
            print("❌ [PhotoValidationService] Face detection failed: \(error)")
            
            // 如果是 inference context 错误（Code 9），可能是模拟器限制或图片格式问题
            // 在这种情况下，提供一个降级方案：允许通过验证（因为可能是环境限制）
            if nsError.code == 9 {
                print("⚠️ [PhotoValidationService] Vision inference context error detected. This may be due to simulator limitations. Allowing photo to pass validation.")
                // 在模拟器或 Vision 无法工作的环境中，允许通过验证
                return PhotoValidationResult(isValid: true, errors: [])
            }
            
            // 尝试备选检测方法
            return await tryAlternativeFaceDetection(cgImage: cgImage, orientation: orientation)
        }
    }
    
    /// 尝试使用更简单的人脸矩形检测作为备选方案
    private func tryAlternativeFaceDetection(cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> PhotoValidationResult {
        let faceRectRequest = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                let nsError = error as NSError
                if nsError.code == 9 {
                    print("⚠️ [PhotoValidationService] Vision inference context error in rectangle detection (Code 9)")
                } else {
                    print("❌ [PhotoValidationService] Face rectangle detection error: \(error)")
                }
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        
        do {
            try handler.perform([faceRectRequest])
            
            guard let observations = faceRectRequest.results, !observations.isEmpty else {
                print("❌ [PhotoValidationService] No faces detected with rectangle detection either")
                return PhotoValidationResult(isValid: false, errors: [.noPersonFound])
            }
            
            print("✅ [PhotoValidationService] Detected \(observations.count) face(s) with rectangle detection")
            
            // 验证人脸数量
            if observations.count > 1 {
                return PhotoValidationResult(isValid: false, errors: [.multiplePeopleDetected])
            } else {
                // 只有一个人脸，检查基本质量
                if let faceObservation = observations.first {
                    let confidence = faceObservation.confidence
                    let boundingBox = faceObservation.boundingBox
                    
                    // 使用更宽松的阈值
                    if confidence < 0.3 || boundingBox.width < 0.05 || boundingBox.height < 0.05 {
                        return PhotoValidationResult(isValid: false, errors: [.faceSeverelyOffsetOrObscured])
                    } else {
                        // 使用矩形检测时，无法获取角度信息，只要检测到人脸且质量足够就认为有效
                        print("✅ [PhotoValidationService] Photo validation passed (rectangle detection)")
                        return PhotoValidationResult(isValid: true, errors: [])
                    }
                }
            }
            
            return PhotoValidationResult(isValid: false, errors: [.noPersonFound])
            
        } catch {
            let nsError = error as NSError
            print("❌ [PhotoValidationService] Face rectangle detection failed: \(error)")
            
            // 如果是 inference context 错误，允许通过验证（可能是环境限制）
            if nsError.code == 9 {
                print("⚠️ [PhotoValidationService] Vision inference context error in rectangle detection. Allowing photo to pass validation.")
                return PhotoValidationResult(isValid: true, errors: [])
            }
            
            return PhotoValidationResult(isValid: false, errors: [.noPersonFound])
        }
    }
}

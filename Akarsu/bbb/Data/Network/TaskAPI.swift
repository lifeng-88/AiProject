//
//  TaskAPI.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Foundation

/// 创建任务请求模型
struct CreateTaskRequest: Codable {
    let taskType: Int32
    let tid: String
    let userParams: String
    
    enum CodingKeys: String, CodingKey {
        case taskType
        case tid
        case userParams
    }
}

/// 创建任务时 `userParams` 的 JSON 体：用户上传后的输入图 URL 列表
struct CreateTaskUserParams: Encodable {
    let inputImages: [String]

    enum CodingKeys: String, CodingKey {
        case inputImages = "input_images"
    }
}

extension CreateTaskUserParams {
    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let s = String(data: data, encoding: .utf8) else {
            throw AppError.encodingError("userParams")
        }
        return s
    }
}

/// 创建任务响应模型
struct CreateTaskResponse: Codable {
    let taskId: String
    
    enum CodingKeys: String, CodingKey {
        case taskId
    }
}

/// 任务状态枚举
enum TaskStatus: Int32, Codable {
    case pending = 0    // 等待中
    case running = 1     // 生成中
    case success = 2    // 成功
    case failed = 3     // 失败
}

/// 查询任务响应模型
struct GetTaskResponse: Codable {
    let taskId: String
    let taskType: Int32
    let tid: String
    let status: Int32  // 0: PENDING; 1: RUNNING; 2: SUCCESS; 3: FAILED
    let createTs: String
    let execTs: String?
    let finishTs: String?
    let userParams: String?
    let resultUrl: String?
    let waitSeconds: Int32?
    let execSeconds: Int32?
    
    enum CodingKeys: String, CodingKey {
        case taskId
        case taskType
        case tid
        case status
        case createTs
        case execTs
        case finishTs
        case userParams
        case resultUrl
        case waitSeconds
        case execSeconds
    }
    
    /// 获取任务状态枚举
    var taskStatus: TaskStatus {
        return TaskStatus(rawValue: status) ?? .pending
    }
}

/// 任务列表项模型（用于列表接口）
struct TaskListItem: Decodable, Hashable, Identifiable {
    var id: String { taskId }
    let taskId: String
    let taskType: Int32
    let tid: String
    let totalStage: Int32?
    let currentStage: Int32?
    let status: Int32  // 0: PENDING; 1: RUNNING; 2: SUCCESS; 3: FAILED
    let userParams: String?
    let resultUrl: String?
    let createTs: String  // 时间戳（字符串格式的 int64）
    let execTs: String?    // 时间戳（字符串格式的 int64）
    let finishTs: String? // 时间戳（字符串格式的 int64）
    let waitSeconds: Int32?
    let execSeconds: Int32?
    let readStatus: Int32? // 已读状态（0: 未读, 1: 已读）
    let consumedGold: Int64? // 任务消耗金币（服务端 ListTask 返回）
    
    enum CodingKeys: String, CodingKey {
        case taskId
        case taskType
        case tid
        case totalStage
        case currentStage
        case status
        case userParams
        case resultUrl
        case createTs
        case execTs
        case finishTs
        case waitSeconds
        case execSeconds
        case readStatus
        case consumedGold
        case consumedGoldSnake = "consumed_gold"
    }

    init(
        taskId: String,
        taskType: Int32,
        tid: String,
        totalStage: Int32?,
        currentStage: Int32?,
        status: Int32,
        userParams: String?,
        resultUrl: String?,
        createTs: String,
        execTs: String?,
        finishTs: String?,
        waitSeconds: Int32?,
        execSeconds: Int32?,
        readStatus: Int32?,
        consumedGold: Int64?
    ) {
        self.taskId = taskId
        self.taskType = taskType
        self.tid = tid
        self.totalStage = totalStage
        self.currentStage = currentStage
        self.status = status
        self.userParams = userParams
        self.resultUrl = resultUrl
        self.createTs = createTs
        self.execTs = execTs
        self.finishTs = finishTs
        self.waitSeconds = waitSeconds
        self.execSeconds = execSeconds
        self.readStatus = readStatus
        self.consumedGold = consumedGold
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try c.decode(String.self, forKey: .taskId)
        taskType = try c.decode(Int32.self, forKey: .taskType)
        tid = try c.decode(String.self, forKey: .tid)
        totalStage = try c.decodeIfPresent(Int32.self, forKey: .totalStage)
        currentStage = try c.decodeIfPresent(Int32.self, forKey: .currentStage)
        status = try c.decode(Int32.self, forKey: .status)
        userParams = try c.decodeIfPresent(String.self, forKey: .userParams)
        resultUrl = try c.decodeIfPresent(String.self, forKey: .resultUrl)
        createTs = try c.decode(String.self, forKey: .createTs)
        execTs = try c.decodeIfPresent(String.self, forKey: .execTs)
        finishTs = try c.decodeIfPresent(String.self, forKey: .finishTs)
        waitSeconds = try c.decodeIfPresent(Int32.self, forKey: .waitSeconds)
        execSeconds = try c.decodeIfPresent(Int32.self, forKey: .execSeconds)
        readStatus = try c.decodeIfPresent(Int32.self, forKey: .readStatus)

        // consumedGold 兼容 number / string，同时兼容 consumed_gold 命名
        if let num = try? c.decodeIfPresent(Int64.self, forKey: .consumedGold) {
            consumedGold = num
        } else if let str = try? c.decodeIfPresent(String.self, forKey: .consumedGold), let parsed = Int64(str) {
            consumedGold = parsed
        } else if let num = try? c.decodeIfPresent(Int64.self, forKey: .consumedGoldSnake) {
            consumedGold = num
        } else if let str = try? c.decodeIfPresent(String.self, forKey: .consumedGoldSnake), let parsed = Int64(str) {
            consumedGold = parsed
        } else {
            consumedGold = nil
        }
    }
    
    /// 获取任务状态枚举
    var taskStatus: TaskStatus {
        return TaskStatus(rawValue: status) ?? .pending
    }
    
    /// 判断任务是否已过期（超过24小时）
    /// 注意：只有成功完成的任务才判断过期，未完成的任务不算过期
    /// 根据PRD：24-48小时和超过48小时都显示为"expired"
    var isExpired: Bool {
        // 只有成功状态的任务才判断过期
        guard taskStatus == .success,
              let finishTsString = finishTs,
              let finishTsValue = Int64(finishTsString) else {
            return false
        }
        
        // 时间戳可能是毫秒或秒，需要判断
        let timeInterval: TimeInterval
        if finishTsValue > 1_000_000_000_000 {
            // 毫秒时间戳（13位数字）
            timeInterval = TimeInterval(finishTsValue / 1000)
        } else {
            // 秒时间戳（10位数字）
            timeInterval = TimeInterval(finishTsValue)
        }
        
        let finishTime = Date(timeIntervalSince1970: timeInterval)
        let now = Date()
        let hoursSinceFinish = now.timeIntervalSince(finishTime) / 3600.0
        
        // 超过 24 小时就算过期（包括24-48小时和超过48小时）
        return hoursSinceFinish > 24
    }
    
    /// 判断任务是否即将过期（24-48小时之间）
    /// 注意：只有成功完成的任务才判断即将过期
    var isExpiringSoon: Bool {
        // 只有成功状态的任务才判断即将过期
        guard taskStatus == .success,
              let finishTsString = finishTs,
              let finishTsValue = Int64(finishTsString) else {
            return false
        }
        
        // 时间戳可能是毫秒或秒，需要判断
        let timeInterval: TimeInterval
        if finishTsValue > 1_000_000_000_000 {
            // 毫秒时间戳（13位数字）
            timeInterval = TimeInterval(finishTsValue / 1000)
        } else {
            // 秒时间戳（10位数字）
            timeInterval = TimeInterval(finishTsValue)
        }
        
        let finishTime = Date(timeIntervalSince1970: timeInterval)
        let now = Date()
        let hoursSinceFinish = now.timeIntervalSince(finishTime) / 3600.0
        
        // 24-48 小时之间算即将过期
        return hoursSinceFinish >= 24 && hoursSinceFinish <= 48
    }
    
    /// 创建更新了 readStatus 的新实例
    func withReadStatus(_ readStatus: Int32?) -> TaskListItem {
        return TaskListItem(
            taskId: self.taskId,
            taskType: self.taskType,
            tid: self.tid,
            totalStage: self.totalStage,
            currentStage: self.currentStage,
            status: self.status,
            userParams: self.userParams,
            resultUrl: self.resultUrl,
            createTs: self.createTs,
            execTs: self.execTs,
            finishTs: self.finishTs,
            waitSeconds: self.waitSeconds,
            execSeconds: self.execSeconds,
            readStatus: readStatus,
            consumedGold: self.consumedGold
        )
    }
    
    /// 从 GetTaskResponse 创建 TaskListItem（用于差异更新）
    static func fromGetTaskResponse(_ response: GetTaskResponse, readStatus: Int32? = nil) -> TaskListItem {
        return TaskListItem(
            taskId: response.taskId,
            taskType: response.taskType,
            tid: response.tid,
            totalStage: nil, // GetTaskResponse 没有这些字段
            currentStage: nil,
            status: response.status,
            userParams: response.userParams,
            resultUrl: response.resultUrl,
            createTs: response.createTs,
            execTs: response.execTs,
            finishTs: response.finishTs,
            waitSeconds: response.waitSeconds,
            execSeconds: response.execSeconds,
            readStatus: readStatus, // 保留原有的 readStatus，如果没有提供则使用 nil
            consumedGold: nil // GetTask 当前未返回 consumedGold
        )
    }
    
    /// 使用 GetTaskResponse 更新任务（保留原有的 readStatus 和其他字段）
    func updated(from response: GetTaskResponse) -> TaskListItem {
        return TaskListItem(
            taskId: response.taskId,
            taskType: response.taskType,
            tid: response.tid,
            totalStage: self.totalStage, // 保留原有值
            currentStage: self.currentStage, // 保留原有值
            status: response.status, // 更新状态
            userParams: response.userParams, // 更新参数
            resultUrl: response.resultUrl, // 更新结果URL
            createTs: response.createTs, // 更新时间戳
            execTs: response.execTs, // 更新执行时间
            finishTs: response.finishTs, // 更新完成时间
            waitSeconds: response.waitSeconds, // 更新等待时间
            execSeconds: response.execSeconds, // 更新执行时间
            readStatus: self.readStatus, // 保留原有的 readStatus
            consumedGold: self.consumedGold // GetTask 无该字段，轮询更新时保留已拿到的消耗金币
        )
    }
}

/// 任务列表响应模型
struct TaskListResponse: Decodable {
    let list: [TaskListItem]
    let total: Int32
    
    enum CodingKeys: String, CodingKey {
        case list
        case total
    }
}

/// 任务相关 API
struct TaskAPI {
    static let client = APIClient.shared
    
    /// 创建任务
    /// - Parameter request: 创建任务请求
    /// - Returns: 创建任务响应，包含 taskId
    static func createTask(_ request: CreateTaskRequest) async -> Result<CreateTaskResponse, AppError> {
        let parameters: [String: Any] = [
            "taskType": request.taskType,
            "tid": request.tid,
            "userParams": request.userParams
        ]
        
        return await client.request(
            "/v1/tasks",
            method: .post,
            parameters: parameters
        )
    }
    
    /// 查询任务状态
    /// - Parameter taskId: 任务ID
    /// - Returns: 任务状态响应
    static func getTask(taskId: String) async -> Result<GetTaskResponse, AppError> {
        return await client.request(
            "/v1/tasks/\(taskId)",
            method: .get,
            parameters: nil
        )
    }
    
    /// 获取任务列表
    /// - Parameters:
    ///   - pageNum: 页码（可选）
    ///   - pageSize: 每页数量（可选）
    ///   - status: 状态筛选（可选，0: PENDING, 1: RUNNING, 2: SUCCESS, 3: FAILED）
    ///   - readStatus: 已读状态筛选（可选，0: 未读, 1: 已读）
    ///   - view: 视图类型（可选）
    /// - Returns: 任务列表响应
    static func getTaskList(
        pageNum: Int32? = nil,
        pageSize: Int32? = nil,
        status: Int32? = nil,
        readStatus: Int32? = nil,
        view: String? = nil
    ) async -> Result<TaskListResponse, AppError> {
        var parameters: [String: Any] = [:]
        
        if let pageNum = pageNum {
            parameters["pageNum"] = pageNum
        }
        if let pageSize = pageSize {
            parameters["pageSize"] = pageSize
        }
        if let status = status {
            parameters["status"] = status
        }
        if let readStatus = readStatus {
            parameters["readStatus"] = readStatus
        }
        if let view = view {
            parameters["view"] = view
        }
        
        return await client.request(
            "/v1/tasks",
            method: .get,
            parameters: parameters.isEmpty ? nil : parameters
        )
    }
    
    /// 更新任务已读状态
    /// - Parameters:
    ///   - taskId: 任务ID
    ///   - readStatus: 已读状态（1: 已读）
    /// - Returns: 更新结果
    static func updateTaskReadStatus(taskId: String, readStatus: Int32) async -> Result<UpdateTaskResponse, AppError> {
        // 请求体格式：{"readStatus": 1}
        let bodyParameters: [String: Any] = [
            "readStatus": readStatus
        ]
        
        // URL 需要包含查询参数：?update_mask=read_status
        let endpoint = "/v1/tasks/\(taskId)?update_mask=read_status"
        
        return await client.request(
            endpoint,
            method: .patch,
            parameters: bodyParameters
        )
    }
}

/// 更新任务响应模型
struct UpdateTaskResponse: Codable {
    let ok: Bool
    
    enum CodingKeys: String, CodingKey {
        case ok
    }
}

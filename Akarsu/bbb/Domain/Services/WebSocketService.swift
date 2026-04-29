//
//  WebSocketService.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Foundation
import Combine

// 注意：APIClient 需要支持从非 actor 上下文获取 token
// 由于 APIClient 是 actor，我们需要在 Task 中异步获取

/// WebSocket 服务 - 用于接收任务进度推送
@MainActor
class WebSocketService: NSObject, ObservableObject {
    static let shared = WebSocketService()
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected: Bool = false
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 5
    private var reconnectTimer: Timer?
    
    // 回调闭包
    var onTaskProgress: ((Int64, Int32, Int32) -> Void)? // taskId, status, progress
    
    private override init() {
        super.init()
    }
    
    /// 连接到 WebSocket 服务器
    /// - Parameter token: 访问令牌
    func connect(token: String) {
        guard !isConnected else {
            print("🔌 [WebSocketService] Already connected, skipping connection")
            return
        }
        
        guard let url = APIBaseURL.webSocketURL(path: "/ws", queryItems: [("token", token)]) else {
            print("❌ [WebSocketService] Invalid WebSocket URL (base: \(APIBaseURL.effective))")
            return
        }
        
        print("🔌 [WebSocketService] ========== WebSocket Connection Start ==========")
        let origin = "\(url.scheme ?? "")://\(url.host ?? "")\(url.port.map { ":\($0)" } ?? "")/ws"
        print("🔌 [WebSocketService] URL: \(origin)?token=***")
        print("🔌 [WebSocketService] Token length: \(token.count) characters")
        print("🔌 [WebSocketService] Current connection state: isConnected=\(isConnected)")
        
        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        webSocketTask = urlSession?.webSocketTask(with: url)
        print("🔌 [WebSocketService] WebSocket task created, resuming...")
        webSocketTask?.resume()
        
        print("🔌 [WebSocketService] Starting to receive messages...")
        receiveMessage()
    }
    
    /// 断开连接
    func disconnect() {
        print("🔌 [WebSocketService] ========== WebSocket Disconnection ==========")
        print("🔌 [WebSocketService] Current state: isConnected=\(isConnected), reconnectAttempts=\(reconnectAttempts)")
        isConnected = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempts = 0
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        print("🔌 [WebSocketService] WebSocket disconnected and cleaned up")
    }
    
    /// 接收消息
    private func receiveMessage() {
        print("📨 [WebSocketService] Waiting for message... (isConnected: \(isConnected))")
        webSocketTask?.receive { [weak self] result in
            guard let self = self else {
                print("⚠️ [WebSocketService] Self is nil in receiveMessage callback")
                return
            }
            
            switch result {
            case .success(let message):
                print("✅ [WebSocketService] Message received successfully")
                switch message {
                case .string(let text):
                    print("📨 [WebSocketService] Received STRING message (unexpected): \(text)")
                    print("📨 [WebSocketService] String length: \(text.count) characters")
                    // 这里应该不会收到字符串消息，因为消息是 protobuf
                    
                case .data(let data):
                    print("📨 [WebSocketService] ========== Received Binary Message ==========")
                    print("📨 [WebSocketService] Data size: \(data.count) bytes")
                    print("📨 [WebSocketService] Data hex (first 100 bytes): \(data.prefix(100).map { String(format: "%02x", $0) }.joined(separator: " "))")
                    self.handleProtobufMessage(data: data)
                    
                @unknown default:
                    print("⚠️ [WebSocketService] Unknown message type")
                }
                
                // 继续接收下一条消息
                if self.isConnected {
                    print("📨 [WebSocketService] Continuing to receive next message...")
                    self.receiveMessage()
                } else {
                    print("⚠️ [WebSocketService] Not connected, stopping message reception")
                }
                
            case .failure(let error):
                print("❌ [WebSocketService] ========== Failed to Receive Message ==========")
                print("❌ [WebSocketService] Error: \(error)")
                print("❌ [WebSocketService] Error description: \(error.localizedDescription)")
                print("❌ [WebSocketService] Current connection state: isConnected=\(self.isConnected)")
                if self.isConnected {
                    // 连接断开，尝试重连
                    print("🔄 [WebSocketService] Connection lost, attempting to handle disconnection...")
                    Task { @MainActor in
                        await self.handleDisconnection()
                    }
                } else {
                    print("⚠️ [WebSocketService] Already disconnected, not attempting reconnect")
                }
            }
        }
    }
    
    /// 处理 protobuf 消息
    private func handleProtobufMessage(data: Data) {
        print("🔍 [WebSocketService] ========== Parsing Protobuf Message ==========")
        // 解析 protobuf Notification 消息
        // 根据 message.proto 定义：
        // message Notification {
        //   int64 userid = 1;
        //   int32 type = 2;  //1: TaskProgress
        //   int64 msg_id = 3;
        //   int64 timestamp = 4;
        //   oneof payload {
        //     TaskProgress progress = 5;
        //   }
        // }
        
        // message TaskProgress {
        //   int64 task_id = 1;
        //   int32 status = 2;
        //   int32 progress = 3;
        // }
        
        do {
            print("🔍 [WebSocketService] Starting protobuf parsing...")
            let notification = try parseNotification(data: data)
            print("✅ [WebSocketService] Protobuf parsed successfully")
            print("📊 [WebSocketService] Notification - userid: \(notification.userid), type: \(notification.type), msgId: \(notification.msgId), timestamp: \(notification.timestamp)")
            
            // 检查消息类型是否为 TaskProgress
            if notification.type == 1 {
                print("📊 [WebSocketService] Message type is TaskProgress (type=1)")
                if let progress = notification.progress {
                    print("📊 [WebSocketService] ========== TaskProgress Received ==========")
                    print("📊 [WebSocketService] taskId: \(progress.taskId)")
                    print("📊 [WebSocketService] status: \(progress.status) (0=PENDING, 1=RUNNING, 2=SUCCESS, 3=FAILED)")
                    print("📊 [WebSocketService] progress: \(progress.progress)")
                    
                    // 调用回调
                    if let callback = onTaskProgress {
                        print("📊 [WebSocketService] Calling onTaskProgress callback...")
                        callback(progress.taskId, progress.status, progress.progress)
                        print("📊 [WebSocketService] Callback executed")
                    } else {
                        print("⚠️ [WebSocketService] onTaskProgress callback is nil!")
                    }
                } else {
                    print("⚠️ [WebSocketService] Message type is TaskProgress but progress payload is nil")
                }
            } else {
                print("⚠️ [WebSocketService] Message type is not TaskProgress: type=\(notification.type)")
            }
        } catch {
            print("❌ [WebSocketService] ========== Failed to Parse Protobuf ==========")
            print("❌ [WebSocketService] Error: \(error)")
            print("❌ [WebSocketService] Error type: \(type(of: error))")
            if let parseError = error as? ProtobufParseError {
                print("❌ [WebSocketService] Parse error type: \(parseError)")
            }
        }
    }
    
    /// 解析 protobuf Notification 消息
    private func parseNotification(data: Data) throws -> NotificationMessage {
        print("🔍 [WebSocketService] parseNotification - data size: \(data.count) bytes")
        // 手动解析 protobuf 消息
        // protobuf 使用 varint 编码和 wire type
        var offset = 0
        var fieldCount = 0
        
        var userid: Int64?
        var type: Int32?
        var msgId: Int64?
        var timestamp: Int64?
        var taskId: Int64?
        var status: Int32?
        var progress: Int32?
        
        while offset < data.count {
            fieldCount += 1
            if fieldCount <= 10 { // 只打印前10个字段的详细信息
                print("🔍 [WebSocketService] Parsing field #\(fieldCount) at offset \(offset)")
            }
            let (fieldNumber, wireType, newOffset) = try decodeFieldHeader(data: data, offset: offset)
            offset = newOffset
            
            switch fieldNumber {
            case 1: // userid
                if wireType == 0 { // varint
                    let (value, newOffset) = try decodeVarint(data: data, offset: offset)
                    userid = Int64(value)
                    if fieldCount <= 10 {
                        print("🔍 [WebSocketService] Field 1 (userid): \(userid!)")
                    }
                    offset = newOffset
                }
            case 2: // type
                if wireType == 0 { // varint
                    let (value, newOffset) = try decodeVarint(data: data, offset: offset)
                    type = Int32(value)
                    if fieldCount <= 10 {
                        print("🔍 [WebSocketService] Field 2 (type): \(type!)")
                    }
                    offset = newOffset
                }
            case 3: // msg_id
                if wireType == 0 { // varint
                    let (value, newOffset) = try decodeVarint(data: data, offset: offset)
                    msgId = Int64(value)
                    if fieldCount <= 10 {
                        print("🔍 [WebSocketService] Field 3 (msgId): \(msgId!)")
                    }
                    offset = newOffset
                }
            case 4: // timestamp
                if wireType == 0 { // varint
                    let (value, newOffset) = try decodeVarint(data: data, offset: offset)
                    timestamp = Int64(value)
                    if fieldCount <= 10 {
                        print("🔍 [WebSocketService] Field 4 (timestamp): \(timestamp!)")
                    }
                    offset = newOffset
                }
            case 5: // payload (TaskProgress)
                if wireType == 2 { // length-delimited
                    let (length, newOffset) = try decodeVarint(data: data, offset: offset)
                    offset = newOffset
                    print("🔍 [WebSocketService] Field 5 (payload/TaskProgress) - length: \(length) bytes")
                    
                    // 解析 TaskProgress 消息
                    let progressData = data.subdata(in: offset..<offset+Int(length))
                    let (taskIdValue, statusValue, progressValue, _) = try parseTaskProgress(data: progressData)
                    taskId = taskIdValue
                    status = statusValue
                    progress = progressValue
                    print("🔍 [WebSocketService] TaskProgress parsed - taskId: \(taskIdValue), status: \(statusValue), progress: \(progressValue)")
                    offset += Int(length)
                }
            default:
                // 跳过未知字段
                if wireType == 0 { // varint
                    let (_, newOffset) = try decodeVarint(data: data, offset: offset)
                    offset = newOffset
                } else if wireType == 1 { // fixed64
                    offset += 8
                } else if wireType == 2 { // length-delimited
                    let (length, newOffset) = try decodeVarint(data: data, offset: offset)
                    offset = newOffset + Int(length)
                } else if wireType == 5 { // fixed32
                    offset += 4
                }
            }
        }
        
        return NotificationMessage(
            userid: userid ?? 0,
            type: type ?? 0,
            msgId: msgId ?? 0,
            timestamp: timestamp ?? 0,
            progress: (taskId != nil && status != nil && progress != nil) ? TaskProgressMessage(
                taskId: taskId!,
                status: status!,
                progress: progress!
            ) : nil
        )
    }
    
    /// 解析 TaskProgress 消息
    private func parseTaskProgress(data: Data) throws -> (taskId: Int64, status: Int32, progress: Int32, offset: Int) {
        var offset = 0
        var taskId: Int64?
        var status: Int32?
        var progress: Int32?
        
        while offset < data.count {
            let (fieldNumber, wireType, newOffset) = try decodeFieldHeader(data: data, offset: offset)
            offset = newOffset
            
            switch fieldNumber {
            case 1: // task_id
                if wireType == 0 { // varint
                    let (value, newOffset) = try decodeVarint(data: data, offset: offset)
                    taskId = Int64(value)
                    offset = newOffset
                }
            case 2: // status
                if wireType == 0 { // varint
                    let (value, newOffset) = try decodeVarint(data: data, offset: offset)
                    status = Int32(value)
                    offset = newOffset
                }
            case 3: // progress
                if wireType == 0 { // varint
                    let (value, newOffset) = try decodeVarint(data: data, offset: offset)
                    progress = Int32(value)
                    offset = newOffset
                }
            default:
                // 跳过未知字段
                if wireType == 0 { // varint
                    let (_, newOffset) = try decodeVarint(data: data, offset: offset)
                    offset = newOffset
                } else if wireType == 1 { // fixed64
                    offset += 8
                } else if wireType == 2 { // length-delimited
                    let (length, newOffset) = try decodeVarint(data: data, offset: offset)
                    offset = newOffset + Int(length)
                } else if wireType == 5 { // fixed32
                    offset += 4
                }
            }
        }
        
        guard let taskId = taskId, let status = status, let progress = progress else {
            throw ProtobufParseError.invalidMessage
        }
        
        return (taskId, status, progress, offset)
    }
    
    /// 解码字段头（field number + wire type）
    private func decodeFieldHeader(data: Data, offset: Int) throws -> (fieldNumber: Int, wireType: Int, newOffset: Int) {
        guard offset < data.count else {
            throw ProtobufParseError.invalidData
        }
        
        let (tag, newOffset) = try decodeVarint(data: data, offset: offset)
        let fieldNumber = Int(tag >> 3)
        let wireType = Int(tag & 0x7)
        
        return (fieldNumber, wireType, newOffset)
    }
    
    /// 解码 varint
    private func decodeVarint(data: Data, offset: Int) throws -> (value: UInt64, newOffset: Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var currentOffset = offset
        
        while currentOffset < data.count {
            let byte = data[currentOffset]
            currentOffset += 1
            
            result |= UInt64(byte & 0x7F) << shift
            
            if (byte & 0x80) == 0 {
                return (result, currentOffset)
            }
            
            shift += 7
            if shift >= 64 {
                throw ProtobufParseError.invalidVarint
            }
        }
        
        throw ProtobufParseError.invalidData
    }
    
    /// 处理断开连接
    private func handleDisconnection() async {
        isConnected = false
        
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            let delay = min(Double(reconnectAttempts) * 2.0, 30.0) // 指数退避，最多30秒
            
            print("🔄 [WebSocketService] Attempting to reconnect (attempt \(reconnectAttempts)/\(maxReconnectAttempts)) in \(delay) seconds")
            
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // 重新获取 token 并连接
                    let token = await APIClient.shared.getAccessToken()
                    if let token = token {
                        self.connect(token: token)
                    }
                }
            }
        } else {
            print("❌ [WebSocketService] Max reconnect attempts reached")
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocolName: String?) {
        Task { @MainActor in
            print("✅ [WebSocketService] ========== WebSocket Connected ==========")
            print("✅ [WebSocketService] Protocol: \(protocolName ?? "nil")")
            print("✅ [WebSocketService] Setting isConnected = true")
            isConnected = true
            reconnectAttempts = 0
            print("✅ [WebSocketService] Connection established successfully")
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            print("🔌 [WebSocketService] ========== WebSocket Closed ==========")
            print("🔌 [WebSocketService] Close code: \(closeCode.rawValue)")
            if let reason = reason, let reasonString = String(data: reason, encoding: .utf8) {
                print("🔌 [WebSocketService] Close reason: \(reasonString)")
            } else {
                print("🔌 [WebSocketService] Close reason: nil or not UTF-8")
            }
            print("🔌 [WebSocketService] Setting isConnected = false")
            isConnected = false
            await handleDisconnection()
        }
    }
}

// MARK: - Helper Types

struct NotificationMessage {
    let userid: Int64
    let type: Int32
    let msgId: Int64
    let timestamp: Int64
    let progress: TaskProgressMessage?
}

struct TaskProgressMessage {
    let taskId: Int64
    let status: Int32
    let progress: Int32
}

enum ProtobufParseError: Error {
    case invalidData
    case invalidVarint
    case invalidMessage
}

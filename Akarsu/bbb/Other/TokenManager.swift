//
//  TokenManager.swift
//  bbb
//

import Foundation

actor TokenManager {
    static let shared = TokenManager()

    /// 并发 401 时合并为一次「先 refresh，失败再设备登录」
    private var recoveryTask: Task<Result<AuthInfo, AppError>, Never>?

    private init() {}

    /// 401 后：先 `refreshToken`；失败则 `loginWithDeviceCredentials`（与冷启动无会话一致）
    func refreshTokenIfNeeded() async -> Result<AuthInfo, AppError> {
        if let existing = recoveryTask {
            return await existing.value
        }
        let task = Task<Result<AuthInfo, AppError>, Never> {
            await self.performAuthRecovery()
        }
        recoveryTask = task
        let result = await task.value
        recoveryTask = nil
        return result
    }

    private func performAuthRecovery() async -> Result<AuthInfo, AppError> {
        let repo = AuthRepository.shared
        if let info = await repo.getCurrentAuthInfo() {
            switch await repo.refreshToken(refreshToken: info.refreshToken) {
            case .success(let auth):
                return .success(auth)
            case .failure:
                break
            }
        }
        return await repo.loginWithDeviceCredentials()
    }

    func clearRefreshState() async {
        recoveryTask = nil
    }
}

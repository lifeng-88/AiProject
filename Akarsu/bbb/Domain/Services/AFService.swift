//
//  AFService.swift
//  glam
//
//  T-AF-5 / T-AF-7: AF SDK 初始化与首启归因流程；非首启异步初始化
//  首启：拉取 config → 初始化 AF → start() 等归因（或 10 秒超时）→ 再允许登录
//  非首启：直接允许登录，仅多一步后台异步初始化 AF
//  需在 Xcode 中通过 File > Add Package 添加: https://github.com/AppsFlyerSDK/AppsFlyerFramework-Static，产品选 AppsFlyerLib
//

import Foundation

private let kAFHasObtainedAttribution = "af_has_obtained_attribution"
private let kAFHasCompletedLogin = "af_has_completed_login"
private let kAFAttributionJSON = "af_attribution_json"
private let kAFAfId = "af_af_id"
private let kAFAdId = "af_ad_id"
private let kAFSource = "af_source"
private let attributionTimeoutSeconds: TimeInterval = 10

/// AF 归因结果，用于登录请求
struct AFAttributionResult {
    var afId: String?
    var adId: String?
    var source: String?
    var attributionJson: String?
}

/// AppsFlyer 服务：归因状态与登录就绪
actor AFService {
    static let shared = AFService()

    private let defaults = UserDefaults.standard
    private var attributionResult: AFAttributionResult?
    private var attributionContinuation: CheckedContinuation<AFAttributionResult?, Never>?
    private let configManager = AFConfigManager.shared

    private init() {}

    /// 是否已获取过归因
    var hasObtainedAttributionBefore: Bool {
        defaults.bool(forKey: kAFHasObtainedAttribution)
    }

    /// 是否曾完成过登录（首启判断标准：未完成过登录 = 首启）
    var hasCompletedLoginBefore: Bool {
        defaults.bool(forKey: kAFHasCompletedLogin)
    }

    /// 标记已完成登录（由 AuthRepository 在登录成功时调用）
    func markLoginCompleted() {
        defaults.set(true, forKey: kAFHasCompletedLogin)
        print("📱 [AFService] markLoginCompleted: 已标记曾完成登录")
    }

    /// 当前缓存的归因结果（供登录携带）
    func getAttributionForLogin() -> AFAttributionResult? {
        if let r = attributionResult { return r }
        let afId = defaults.string(forKey: kAFAfId)
        let adId = defaults.string(forKey: kAFAdId)
        let source = defaults.string(forKey: kAFSource)
        let json = defaults.string(forKey: kAFAttributionJSON)
        if afId != nil || adId != nil || source != nil || (json != nil && !json!.isEmpty) {
            return AFAttributionResult(afId: afId, adId: adId, source: source, attributionJson: json)
        }
        return nil
    }

    /// 设置归因结果（由 AF delegate 或测试调用）
    func setAttribution(afId: String?, adId: String?, source: String?, attributionJson: String?) {
        attributionResult = AFAttributionResult(afId: afId, adId: adId, source: source, attributionJson: attributionJson)
        if let afId = afId, !afId.isEmpty { defaults.set(afId, forKey: kAFAfId) }
        if let adId = adId { defaults.set(adId, forKey: kAFAdId) }
        if let source = source { defaults.set(source, forKey: kAFSource) }
        if let json = attributionJson { defaults.set(json, forKey: kAFAttributionJSON) }
        defaults.set(true, forKey: kAFHasObtainedAttribution)
        print("📱 [AFService] setAttribution: afId=\(afId ?? "nil") source=\(source ?? "nil") jsonLen=\(attributionJson?.count ?? 0)")
        if let cont = attributionContinuation {
            attributionContinuation = nil
            cont.resume(returning: attributionResult)
            print("📱 [AFService] setAttribution: 已 resume 等待中的归因")
        }
    }

    /// 首启时等待归因或超时，返回用于登录的归因数据
    func waitForAttributionOrTimeout() async -> AFAttributionResult? {
        if hasObtainedAttributionBefore {
            let cached = getAttributionForLogin()
            print("📱 [AFService] waitForAttributionOrTimeout: 已有归因缓存，直接返回")
            return cached
        }
        print("📱 [AFService] waitForAttributionOrTimeout: 等待归因，超时 \(Int(attributionTimeoutSeconds))s")
        let result = await withCheckedContinuation { continuation in
            attributionContinuation = continuation
            Task {
                try? await Task.sleep(nanoseconds: UInt64(attributionTimeoutSeconds * 1_000_000_000))
                await timeoutAttribution()
            }
        }
        if result != nil {
            print("📱 [AFService] waitForAttributionOrTimeout: 得到归因 afId=\(result?.afId ?? "nil") source=\(result?.source ?? "nil")")
        } else {
            print("📱 [AFService] waitForAttributionOrTimeout: 超时或无归因，返回 nil")
        }
        return result
    }

    private func timeoutAttribution() async {
        if let cont = attributionContinuation {
            attributionContinuation = nil
            defaults.set(true, forKey: kAFHasObtainedAttribution)
            cont.resume(returning: getAttributionForLogin())
            print("📱 [AFService] timeoutAttribution: 超时，已 resume")
        }
    }

    /// 首启：拉取 config、初始化 AF、start()，然后等待归因或超时
    /// 返回 (canLogin, attributionForLogin)。失败不阻塞，返回 (true, nil)
    func prepareForFirstLaunch(channelId: String) async -> (canLogin: Bool, attribution: AFAttributionResult?) {
        let effectiveChannel = channelId.isEmpty ? "IOS10052" : channelId
        print("📱 [AFService] prepareForFirstLaunch: 开始 channel=\(effectiveChannel)")
        #if DEBUG
        if ProcessInfo.processInfo.environment["SIMULATE_AF_TIMEOUT"] == "1" {
            print("🧪 [AFService] prepareForFirstLaunch: 模拟 AF 超时 (SIMULATE_AF_TIMEOUT=1)，跳过等待，返回 nil")
            return (true, nil)
        }
        #endif
        guard let appleAppId = await configManager.getAppleAppID(channelId: effectiveChannel),
              let devKey = await configManager.getAppsFlyerDevKey(channelId: effectiveChannel),
              !appleAppId.isEmpty, !devKey.isEmpty else {
            print("⚠️ [AFService] prepareForFirstLaunch: 无 AF config，跳过 init channel=\(effectiveChannel)")
            return (true, nil)
        }
        print("📱 [AFService] prepareForFirstLaunch: 配置 AF 并 start，等待归因")
        AFSDKBridge.configure(appleAppId: appleAppId, appsFlyerDevKey: devKey)
        AFSDKBridge.start()
        let attribution = await waitForAttributionOrTimeout()
        print("📱 [AFService] prepareForFirstLaunch: 完成 attribution=\(attribution != nil ? "有" : "无")")
        return (true, attribution)
    }

    /// 非首启：后台异步初始化 AF，不等待归因、不阻塞登录
    func initAFAsync(channelId: String) async {
        let effectiveChannel = channelId.isEmpty ? "IOS10052" : channelId
        print("📱 [AFService] initAFAsync: 开始 channel=\(effectiveChannel)")
        guard let appleAppId = await configManager.getAppleAppID(channelId: effectiveChannel),
              let devKey = await configManager.getAppsFlyerDevKey(channelId: effectiveChannel),
              !appleAppId.isEmpty, !devKey.isEmpty else {
            print("📱 [AFService] initAFAsync: 无 AF config，跳过 channel=\(effectiveChannel)")
            return
        }
        AFSDKBridge.configure(appleAppId: appleAppId, appsFlyerDevKey: devKey)
        AFSDKBridge.start()
        print("📱 [AFService] initAFAsync: 完成 channel=\(effectiveChannel)")
    }
}

/// 桥接层：无 SDK 时 no-op；添加 AppsFlyerLib 后在此调用真实 API（Xcode: File > Add Package > https://github.com/AppsFlyerSDK/AppsFlyerFramework-Static）
enum AFSDKBridge {
    static func configure(appleAppId: String, appsFlyerDevKey: String) {
        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().appleAppID = appleAppId
        AppsFlyerLib.shared().appsFlyerDevKey = appsFlyerDevKey
        AppsFlyerLib.shared().delegate = AFDelegateWrapper.shared
        print("📱 [AFSDKBridge] configure: 已配置 appleAppId=\(appleAppId.prefix(12))... devKey=\(appsFlyerDevKey.prefix(8))...")
        #else
        _ = appleAppId; _ = appsFlyerDevKey
        print("ℹ️ [AFSDKBridge] configure: AppsFlyerLib 未链接，no-op")
        #endif
    }

    static func start() {
        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().start()
        print("📱 [AFSDKBridge] start: 已调用 AF start()")
        #else
        print("ℹ️ [AFSDKBridge] start: AppsFlyerLib 未链接，no-op")
        #endif
    }
}

#if canImport(AppsFlyerLib)
import AppsFlyerLib

private final class AFDelegateWrapper: NSObject, AppsFlyerLibDelegate {
    static let shared = AFDelegateWrapper()
    override private init() { super.init() }
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        let afId = AppsFlyerLib.shared().getAppsFlyerUID()
        let json: String? = (try? JSONSerialization.data(withJSONObject: conversionInfo)).flatMap { String(data: $0, encoding: .utf8) }
        let source = conversionInfo["media_source"] as? String
        print("📱 [AFDelegate] onConversionDataSuccess: afId=\(afId ?? "nil") source=\(source ?? "nil")")
        Task { await AFService.shared.setAttribution(afId: afId, adId: nil, source: source, attributionJson: json) }
    }
    func onConversionDataFail(_ error: Error) {
        print("📱 [AFDelegate] onConversionDataFail: \(error.localizedDescription)")
        Task { await AFService.shared.setAttribution(afId: nil, adId: nil, source: nil, attributionJson: nil) }
    }
}
#endif

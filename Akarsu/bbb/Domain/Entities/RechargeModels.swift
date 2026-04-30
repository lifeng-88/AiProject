//
//  RechargeModels.swift
//  glam
//
//  Created by Dev on 2026/1/19.
//

import Foundation

// MARK: - Package (充值套餐)

/// 充值套餐
struct Package: Identifiable, Codable, Equatable {
    let id: Int32
    let name: String
    let regularPrice: Int64  // 原价（单位为分）
    let discountPrice: Int64  // 折扣价（单位为分）
    let gold: Int32          // 金币数量
    let bonus: Int32         // 赠送金币
    /// Apple 内购商品 ID（与 App Store Connect 一致）；由后台多字段解析合并，见 `resolvedAppleProductId`
    let appleProductId: String?
    /// 若后台为 IAP 单独配置渠道，下单/确认时优先于支付渠道列表里的 Apple 项（可选）
    let iapPayChannelId: Int32?

    enum CodingKeys: String, CodingKey {
        case id = "packageId"
        case idSnake = "package_id"
        case idPlain = "id"
        case name
        case regularPrice
        case discountPrice
        case gold
        case bonus
        case appleProductId
        case appleProductIdSnake = "apple_product_id"
        case iapProductId = "iap_product_id"
        case storeProductId = "store_product_id"
        case inAppPurchaseId = "in_app_purchase_id"
        case productId = "product_id"
        case iapPayChannelId = "iap_pay_channel_id"
        case applePayChannelId = "apple_pay_channel_id"
    }

    /// 成员初始化器
    init(
        id: Int32,
        name: String,
        regularPrice: Int64,
        discountPrice: Int64,
        gold: Int32,
        bonus: Int32,
        appleProductId: String?,
        iapPayChannelId: Int32? = nil
    ) {
        self.id = id
        self.name = name
        self.regularPrice = regularPrice
        self.discountPrice = discountPrice
        self.gold = gold
        self.bonus = bonus
        self.appleProductId = appleProductId
        self.iapPayChannelId = iapPayChannelId
    }

    /// 自定义解码，处理字符串类型的价格字段与后台多种 IAP 商品 ID 键名
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try Self.decodeInt32Flex(from: container, keys: [.id, .idSnake, .idPlain])
        name = try container.decode(String.self, forKey: .name)
        gold = try Self.decodeInt32Flex(from: container, keys: [.gold])
        bonus = try Self.decodeInt32Flex(from: container, keys: [.bonus])

        let rawApple = Self.firstTrimmedString(
            from: container,
            keys: [.appleProductId, .appleProductIdSnake, .iapProductId, .storeProductId, .inAppPurchaseId, .productId]
        )
        appleProductId = rawApple

        iapPayChannelId = Self.decodeOptionalInt32Flex(from: container, keys: [.iapPayChannelId, .applePayChannelId])

        /// 与后台 `GET /v1/packages` 一致：如 `"regularPrice":"2000"`、`"discountPrice":"999"`，也可能为数字
        regularPrice = try Self.decodePriceCents(from: container, forKey: .regularPrice)
        discountPrice = try Self.decodePriceCents(from: container, forKey: .discountPrice)
    }

    /// 单价（分）：字符串 / 整型 / 浮点（与示例 JSON 及常见 swagger 变体兼容）
    private static func decodePriceCents(from c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int64 {
        if let s = try? c.decode(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = Int64(t) { return v }
            if let d = Double(t) { return Int64(d.rounded()) }
            return 0
        }
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Int64(v) }
        if let v = try? c.decode(Int32.self, forKey: key) { return Int64(v) }
        if let v = try? c.decode(Double.self, forKey: key) { return Int64(v.rounded()) }
        throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath + [key], debugDescription: "Invalid price field for key \(key)"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(regularPrice, forKey: .regularPrice)
        try container.encode(discountPrice, forKey: .discountPrice)
        try container.encode(gold, forKey: .gold)
        try container.encode(bonus, forKey: .bonus)
        try container.encodeIfPresent(appleProductId, forKey: .appleProductId)
        try container.encodeIfPresent(iapPayChannelId, forKey: .iapPayChannelId)
    }

    private static func decodeInt32Flex(from c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) throws -> Int32 {
        for key in keys {
            if let v = try? c.decode(Int32.self, forKey: key) { return v }
            if let v = try? c.decode(Int.self, forKey: key) { return Int32(v) }
            if let v = try? c.decode(Int64.self, forKey: key) { return Int32(clamping: v) }
            if let s = try? c.decode(String.self, forKey: key), let v = Int32(s) { return v }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Missing or invalid int32 for keys: \(keys)"))
    }

    private static func decodeOptionalInt32Flex(from c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Int32? {
        for key in keys {
            if let v = try? c.decode(Int32.self, forKey: key) { return v }
            if let v = try? c.decode(Int.self, forKey: key) { return Int32(v) }
            if let v = try? c.decode(Int64.self, forKey: key) { return Int32(clamping: v) }
            if let s = try? c.decode(String.self, forKey: key), let v = Int32(s) { return v }
        }
        return nil
    }

    private static func firstTrimmedString(from c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> String? {
        for key in keys {
            guard let raw = try? c.decodeIfPresent(String.self, forKey: key) else { continue }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// StoreKit / IAP 使用的商品 ID（非空且已 trim）；无则无法发起内购
    var resolvedAppleProductId: String? {
        guard let s = appleProductId?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// 计算折扣百分比
    var discountPercentage: Int {
        guard regularPrice > 0 else { return 0 }
        let discount = Double(regularPrice - discountPrice) / Double(regularPrice) * 100
        return Int(discount.rounded())
    }
    
    /// 格式化价格（美元）
    var formattedDiscountPrice: String {
        let dollars = Double(discountPrice) / 100.0
        return String(format: "%.2f$", dollars)
    }
    
    /// 格式化原价（美元）
    var formattedRegularPrice: String {
        let dollars = Double(regularPrice) / 100.0
        return String(format: "%.2f$", dollars)
    }
}

/// 套餐列表响应
struct PackagesResponse: Codable {
    let list: [Package]
}

// MARK: - PayChannel (支付渠道)

/// 支付渠道
struct PayChannel: Identifiable, Codable {
    let id: Int32
    let name: String
    let icon: String?        // 图标URL（可选）
    let type: String?        // 支付渠道类型，如 apple_pay/credit_card/redirect
    let bonusPercentage: Double? // 额外奖励百分比（可选）
    
    enum CodingKeys: String, CodingKey {
        case id = "payChannelId"
        case name
        case icon
        case type
        case bonusPercentage = "extraBonusPercent"
    }
    
    /// 自定义解码，处理 extraBonusPercent
    /// 注意：根据 swagger 文档，extraBonusPercent 是 "百分比*100"
    /// 但为了显示方便，我们直接使用整数值作为百分比（20 表示 20%）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(Int32.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        
        // extraBonusPercent 可能是整数（百分比*100）或已经是百分比
        // 为了兼容，我们直接使用整数值作为百分比
        if let extraBonusPercent = try? container.decode(Int32.self, forKey: .bonusPercentage) {
            bonusPercentage = Double(extraBonusPercent)
        } else {
            bonusPercentage = nil
        }
    }

    /// 手动构造（预览/内购回退）；与 `IAPManager` 默认 `pay_channel_id = 1` 一致
    init(id: Int32, name: String, icon: String? = nil, type: String? = nil, bonusPercentage: Double? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.type = type
        self.bonusPercentage = bonusPercentage
    }

    /// 接口未返回 Apple 渠道时，「直接 Recharge」仍走内购（与 `PayChannel.fallbackApplePayForIAP` / IAP 默认渠道对齐）
    static let fallbackApplePayForIAP = PayChannel(id: 1, name: "Apple Pay", icon: nil, type: "apple_pay", bonusPercentage: nil)
    
    /// 是否为 Apple Pay（根据 type 字段，如 apple_pay）
    var isApplePay: Bool {
        return (type ?? "").lowercased() == "apple_pay"
    }
    
    /// 是否为信用卡支付（根据 type 字段，如 credit_card）
    var isCreditCard: Bool {
        return (type ?? "").lowercased() == "credit_card"
    }

    /// 是否为重定向支付（根据 type 字段，如 redirect）
    var isRedirectPayment: Bool {
        return (type ?? "").lowercased() == "redirect"
    }

    // MARK: - Select Payment UI（与接口字段对齐）

    /// `extraBonusPercent` 可能为「百分比」或「×100」；用于展示百分比数字
    var displayBonusPercentForUI: Double? {
        guard let b = bonusPercentage, b > 0 else { return nil }
        if b >= 100 { return b / 100.0 }
        return b
    }

    /// 副标题：由 `type` 生成简短说明（`name` 已作主标题）
    var paymentTypeSubtitle: String? {
        guard let raw = type?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "apple_pay":
            return nil
        case "credit_card":
            return "Credit card"
        case "redirect":
            return "Web checkout"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// 支付渠道列表响应
struct PayChannelsResponse: Codable {
    let list: [PayChannel]
}

// MARK: - RechargeRecord (充值记录)

/// 充值记录状态
enum RechargeStatus: Int32, Codable {
    case pending = 1      // 待处理
    case recharging = 2    // 充值中
    case success = 3      // 成功
    case failed = 4       // 失败
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int32.self)
        self = RechargeStatus(rawValue: rawValue) ?? .pending
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    var displayText: String {
        switch self {
        case .pending: return AppLanguageStore.localized("recharge.status.pending")
        case .recharging: return AppLanguageStore.localized("recharge.status.recharging")
        case .success: return AppLanguageStore.localized("recharge.status.success")
        case .failed: return AppLanguageStore.localized("recharge.status.failed")
        }
    }
    
    var color: String {
        switch self {
        case .pending: return "#FFD700"      // 黄色
        case .recharging: return "#FFFF00"   // 霓虹黄
        case .success: return "#00FF00"       // 霓虹绿
        case .failed: return "#FF0033"         // 霓虹红
        }
    }
}

/// 充值记录
struct RechargeRecord: Identifiable, Codable {
    let id: String         // orderId
    let channelId: Int32
    /// 金额，单位为分（与接口 ListRechargesReply 一致）
    let amountCents: Int64
    let status: RechargeStatus
    let finishTs: Int64?   // 完成时间戳（可选）
    /// 到账金币（列表接口可选返回；无则 UI 仅展示金额）
    let goldCoins: Int?

    enum CodingKeys: String, CodingKey {
        case id = "orderId"
        case channelId
        case amount
        case status
        case finishTs
        case goldAmountSnake = "gold_amount"
        case goldAmountCamel = "goldAmount"
        case coins
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else {
            id = String(try c.decode(Int64.self, forKey: .id))
        }
        channelId = try c.decode(Int32.self, forKey: .channelId)
        if let n = try? c.decode(Int64.self, forKey: .amount) {
            amountCents = n
        } else {
            amountCents = Int64(try c.decode(Int32.self, forKey: .amount))
        }
        status = try c.decode(RechargeStatus.self, forKey: .status)
        if let ts = try? c.decode(Int64.self, forKey: .finishTs) {
            finishTs = ts > 0 ? ts : nil
        } else if let tsStr = try? c.decode(String.self, forKey: .finishTs), let ts = Int64(tsStr), ts > 0 {
            finishTs = ts
        } else {
            finishTs = nil
        }
        goldCoins = Self.decodeOptionalPositiveInt(from: c)
    }

    private static func decodeOptionalPositiveInt(from c: KeyedDecodingContainer<CodingKeys>) -> Int? {
        if let n = try? c.decodeIfPresent(Int32.self, forKey: .goldAmountSnake) { return Int(max(0, n)) }
        if let n = try? c.decodeIfPresent(Int64.self, forKey: .goldAmountSnake) { return Int(max(0, n)) }
        if let s = try? c.decodeIfPresent(String.self, forKey: .goldAmountSnake), let n = Int(s) { return max(0, n) }
        if let n = try? c.decodeIfPresent(Int32.self, forKey: .goldAmountCamel) { return Int(max(0, n)) }
        if let n = try? c.decodeIfPresent(Int64.self, forKey: .goldAmountCamel) { return Int(max(0, n)) }
        if let s = try? c.decodeIfPresent(String.self, forKey: .goldAmountCamel), let n = Int(s) { return max(0, n) }
        if let n = try? c.decodeIfPresent(Int32.self, forKey: .coins) { return Int(max(0, n)) }
        if let n = try? c.decodeIfPresent(Int64.self, forKey: .coins) { return Int(max(0, n)) }
        if let s = try? c.decodeIfPresent(String.self, forKey: .coins), let n = Int(s) { return max(0, n) }
        return nil
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(channelId, forKey: .channelId)
        try c.encode(Int32(amountCents), forKey: .amount)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(finishTs, forKey: .finishTs)
        try c.encodeIfPresent(goldCoins, forKey: .goldAmountCamel)
    }
    
    /// 格式化完成时间
    var formattedFinishTime: String {
        guard let finishTs = finishTs else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(finishTs))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    /// 格式化金额（分→美元显示，如 $24.99）
    var formattedAmount: String {
        let dollars = Double(amountCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

/// 充值记录列表响应（支持分页）
struct RechargeRecordsResponse: Decodable {
    let list: [RechargeRecord]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case list
        case nextPageToken
        case nextPageTokenSnake = "next_page_token"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        list = try c.decode([RechargeRecord].self, forKey: .list)
        let camel = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
        let snake = try c.decodeIfPresent(String.self, forKey: .nextPageTokenSnake)
        let raw = [camel, snake].compactMap { $0 }.first { !$0.isEmpty }
        nextPageToken = raw
    }
}

// MARK: - Apple Pay

/// Apple Pay 可用性检查响应
struct OfficialApplePayResponse: Codable {
    let enabled: Bool
}

/// Apple Pay Session 请求
struct ApplePaySessionRequest: Codable {
    let validationURL: String
    
    enum CodingKeys: String, CodingKey {
        case validationURL
    }
}

/// Apple Pay Session 响应
struct ApplePaySessionResponse: Codable {
    let sessionPayload: String
}

// MARK: - Recharge Order

/// 创建充值订单请求
struct CreateRechargeOrderRequest: Codable {
    let packageId: Int32
    let payChannelId: Int32
    let transactionId: String?  // 交易号（Apple Pay 等需要）
    /// 三方回调服务端的 Webhook URL（可选，不传时服务端从 pay_channel 配置取）
    let returnUrl: String?
    /// 支付完成后客户端跳转地址（33001/33002/33003），如 {api_base}/payment/return
    let pageUrl: String?
    /// 重定向支付用户填写信息 JSON，由各第三方文档定义
    let payload: String?

    enum CodingKeys: String, CodingKey {
        case packageId
        case payChannelId
        case transactionId
        case returnUrl
        case pageUrl
        case payload
    }
}

/// 创建充值订单响应
struct CreateRechargeOrderResponse: Codable {
    let orderId: String
    /// 重定向支付 URL，仅当 pay_channel_id 为 33001/33002/33003 时返回
    let paymentUrl: String?
    /// payment_url 过期时间（Unix 秒）
    let expiresAt: Int64?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let str = try? container.decode(String.self, forKey: .orderId) {
            orderId = str
        } else if let num = try? container.decode(Int64.self, forKey: .orderId) {
            orderId = String(num)
        } else {
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: [CodingKeys.orderId], debugDescription: "orderId must be String or Int64"))
        }
        paymentUrl = try container.decodeIfPresent(String.self, forKey: .paymentUrl)
        // expiresAt 可能为 number 或 string（服务端有时返回 string）
        if let num = try? container.decodeIfPresent(Int64.self, forKey: .expiresAt) {
            expiresAt = num
        } else if let str = try? container.decodeIfPresent(String.self, forKey: .expiresAt), let parsed = Int64(str) {
            expiresAt = parsed
        } else {
            expiresAt = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case orderId
        case paymentUrl
        case expiresAt
    }
}

/// 订单支付状态（重定向支付 return_url 后查询）
struct OrderPaymentStatusResponse: Codable {
    /// success | pending | failed
    let status: String
    /// 已发金币数
    let goldAmount: Int64?
    /// 可选提示
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case goldAmount = "gold_amount"
        case message
    }
}

// MARK: - 订单已存在类文案判定（重复提交视为成功）

/// 当服务器返回 success: false 但文案表示「该订单/交易已存在」时，视为该笔订单已成功处理，避免用户已扣款却看到失败。
enum RechargeOrderVerification {
    /// 判断 message 是否表示「订单已存在」类重复提交（英文 transaction existed / 中文 订单已经存在）
    static func isDuplicateOrderSuccess(_ message: String?) -> Bool {
        guard let msg = message, !msg.isEmpty else { return false }
        let lower = msg.lowercased()
        if lower.contains("transaction id has existed") { return true }
        if lower.contains("transaction") && lower.contains("existed") { return true }
        if msg.contains("你的订单已经存在") || msg.contains("订单已经存在") { return true }
        if msg.contains("订单已存在") || msg.contains("该订单已处理") { return true }
        return false
    }
}

// MARK: - 确认充值请求

/// 确认充值请求
/// - 信用卡支付（pay_channel_id=2）：传 payload（新卡 JSON 或 {"payment_card_id": id}），transactionId 可不传或传空
/// - Apple Pay 等：传 transactionId，payload 不传
struct ConfirmRechargeRequest: Codable {
    let orderId: String
    /// 支付方交易号（Apple Pay 等必填；信用卡支付可不传或传空）
    let transactionId: String?
    let payChannelId: Int32
    /// 信用卡支付时必填：新卡为与 CreatePaymentCardReq 对齐的 snake_case JSON 字符串，已存卡为 {"payment_card_id": <id>}
    let payload: String?
}

/// 确认充值响应
struct ConfirmRechargeResponse: Codable {
    let success: Bool
    /// 服务器返回的提示信息（失败时可为错误原因）
    let message: String?
    let balance: String?      // 新余额
    let goldAmount: String?   // 充值金币数（服务器返回字符串）
    
    /// 自定义解码，处理 goldAmount 可能是字符串或数字
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        balance = try container.decodeIfPresent(String.self, forKey: .balance)
        
        // goldAmount 可能是字符串或数字，统一处理为字符串
        if let goldAmountString = try? container.decode(String.self, forKey: .goldAmount) {
            goldAmount = goldAmountString
        } else if let goldAmountInt = try? container.decode(Int32.self, forKey: .goldAmount) {
            goldAmount = String(goldAmountInt)
        } else {
            goldAmount = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case balance
        case goldAmount
    }
}

// MARK: - PaymentCard (支付卡)

/// 支付卡（已保存的信用卡）
struct PaymentCard: Identifiable, Codable {
    let id: Int64
    let userId: Int64
    // 信用卡信息（只返回后4位，不返回完整卡号）
    let firstName: String
    let lastName: String
    let expiryMonth: Int32
    let expiryYear: Int32
    let cardType: String
    let last4: String
    // 账单地址信息
    let address1: String
    let address2: String?
    let address3: String?
    let country: String
    let administrativeArea: String?
    let locality: String
    let postalCode: String?
    let email: String
    let phoneNumber: String
    /// 手机区号/国家码（可选，如 +1、+86）
    let phoneCountryCode: String?
    let isDefault: Bool
    
    // 计算属性：组合 firstName 和 lastName 为 cardHolderName
    var cardHolderName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case firstName
        case lastName
        case expiryMonth
        case expiryYear
        case cardType
        case last4
        case address1
        case address2
        case address3
        case country
        case administrativeArea
        case locality
        case postalCode
        case email
        case phoneNumber
        case phoneCountryCode
        case isDefault
    }
    
    /// 自定义解码，处理 id 和 userId 可能是字符串或数字
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 处理 id：可能是字符串或数字
        if let idString = try? container.decode(String.self, forKey: .id),
           let idValue = Int64(idString) {
            id = idValue
        } else {
            id = try container.decode(Int64.self, forKey: .id)
        }
        
        // 处理 userId：可能是字符串或数字
        if let userIdString = try? container.decode(String.self, forKey: .userId),
           let userIdValue = Int64(userIdString) {
            userId = userIdValue
        } else {
            userId = try container.decode(Int64.self, forKey: .userId)
        }
        
        firstName = try container.decode(String.self, forKey: .firstName)
        lastName = try container.decode(String.self, forKey: .lastName)
        expiryMonth = try container.decode(Int32.self, forKey: .expiryMonth)
        expiryYear = try container.decode(Int32.self, forKey: .expiryYear)
        cardType = try container.decode(String.self, forKey: .cardType)
        last4 = try container.decode(String.self, forKey: .last4)
        address1 = try container.decode(String.self, forKey: .address1)
        address2 = try container.decodeIfPresent(String.self, forKey: .address2)
        address3 = try container.decodeIfPresent(String.self, forKey: .address3)
        country = try container.decode(String.self, forKey: .country)
        administrativeArea = try container.decodeIfPresent(String.self, forKey: .administrativeArea)
        locality = try container.decode(String.self, forKey: .locality)
        postalCode = try container.decodeIfPresent(String.self, forKey: .postalCode)
        email = try container.decode(String.self, forKey: .email)
        phoneNumber = try container.decode(String.self, forKey: .phoneNumber)
        phoneCountryCode = try container.decodeIfPresent(String.self, forKey: .phoneCountryCode)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
    
    /// 格式化过期日期（MM/YY）
    var formattedExpiry: String {
        String(format: "%02d/%02d", expiryMonth, expiryYear % 100)
    }
    
    /// 显示卡号（•••• last4）
    var displayCardNumber: String {
        "•••• \(last4)"
    }
}

/// 支付卡列表响应
struct PaymentCardsResponse: Codable {
    let cards: [PaymentCard]
    
    enum CodingKeys: String, CodingKey {
        case cards
    }
}

/// 创建支付卡请求
struct CreatePaymentCardRequest: Codable {
    let userId: Int64
    let cardNumber: String
    let cvv: String
    let firstName: String
    let lastName: String
    let expiryMonth: Int32
    let expiryYear: Int32
    let cardType: String
    let last4: String
    let address1: String
    let address2: String?
    let address3: String?
    let country: String
    let administrativeArea: String?
    let locality: String
    let postalCode: String?
    let email: String
    let phoneNumber: String
    /// 手机区号/国家码（可选，如 +1、+86），与 phone_number 一并上报
    let phoneCountryCode: String?
    let isDefault: Bool
    
    enum CodingKeys: String, CodingKey {
        case userId
        case cardNumber
        case cvv
        case firstName
        case lastName
        case expiryMonth
        case expiryYear
        case cardType
        case last4
        case address1
        case address2
        case address3
        case country
        case administrativeArea
        case locality
        case postalCode
        case email
        case phoneNumber
        case phoneCountryCode
        case isDefault
    }
}

/// 创建支付卡响应
struct CreatePaymentCardResponse: Codable {
    let id: Int64
    
    /// 自定义解码，处理 id 可能是字符串或数字
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 处理 id：可能是字符串或数字
        if let idString = try? container.decode(String.self, forKey: .id),
           let idValue = Int64(idString) {
            id = idValue
        } else {
            id = try container.decode(Int64.self, forKey: .id)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
    }
}

/// 删除支付卡请求
struct DeletePaymentCardRequest: Codable {
    let id: Int64
}

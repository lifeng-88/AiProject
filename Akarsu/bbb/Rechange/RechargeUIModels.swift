//
//  RechargeUIModels.swift
//  bbb
//

import Foundation

struct RechargePackageModel: Identifiable, Equatable {
    /// 服务端套餐 ID（下单 / IAP）
    let packageId: Int32
    let id: String
    let packageName: String
    let totalCoins: Int
    let base: Int
    let bonus: Int
    /// 折扣价展示（与 `Package.discountPrice` 对应）
    let price: String
    /// 原价展示；无折扣时为 nil
    let originalPrice: String?
    let bonusLabel: String
    /// 相对原价的减免比例（用于「+X% FREE」角标，与 `Package.discountPercentage` 一致）
    let discountPercent: Int

    init(
        packageId: Int32 = 0,
        id: String? = nil,
        packageName: String = "",
        totalCoins: Int,
        base: Int,
        bonus: Int,
        price: String,
        originalPrice: String? = nil,
        bonusLabel: String,
        discountPercent: Int = 0
    ) {
        self.packageId = packageId
        self.id = id ?? "local-\(totalCoins)-\(price)"
        self.packageName = packageName
        self.totalCoins = totalCoins
        self.base = base
        self.bonus = bonus
        self.price = price
        self.originalPrice = originalPrice
        self.bonusLabel = bonusLabel
        self.discountPercent = discountPercent
    }
}

extension RechargePackageModel {
    init(package: Package) {
        packageId = package.id
        id = "pkg-\(package.id)"
        packageName = package.name
        let g = Int(package.gold)
        let b = Int(package.bonus)
        base = g
        bonus = b
        totalCoins = g + b
        price = Self.formatUSD(cents: package.discountPrice)
        if package.regularPrice > package.discountPrice {
            originalPrice = Self.formatUSD(cents: package.regularPrice)
        } else {
            originalPrice = nil
        }
        let pct = package.discountPercentage
        discountPercent = max(0, package.discountPercentage)
        if pct > 0 {
            bonusLabel = "-\(pct)%"
        } else if package.bonus > 0 {
            bonusLabel = "+\(package.bonus)"
        } else {
            bonusLabel = ""
        }
    }

    private static func formatUSD(cents: Int64) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

struct RechargeRecordItem: Identifiable, Equatable, Codable {
    let id: UUID
    let createdAt: Date
    let title: String
    let amount: String
    let coins: Int
    let status: RechargeRecordStatus

    init(
        id: UUID = UUID(),
        createdAt: Date,
        title: String,
        amount: String,
        coins: Int,
        status: RechargeRecordStatus
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.amount = amount
        self.coins = coins
        self.status = status
    }
}

enum RechargeRecordStatus: String, Codable {
    case completed
    case pending
    case failed
}

/// 充值记录列表行（`/v1/users/{userId}/recharges` 映射，供 `RechargeRecordListView`）
struct RechargeRecordListRow: Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let title: String
    let amount: String
    let coins: Int?
    let status: RechargeRecordStatus
}

extension RechargeRecord {
    func toListRow() -> RechargeRecordListRow {
        let date: Date
        if let ts = finishTs, ts > 0 {
            date = Date(timeIntervalSince1970: TimeInterval(ts))
        } else {
            date = Date()
        }
        let uiStatus: RechargeRecordStatus
        switch status {
        case .success: uiStatus = .completed
        case .failed: uiStatus = .failed
        case .pending, .recharging: uiStatus = .pending
        }
        return RechargeRecordListRow(
            id: id,
            createdAt: date,
            title: "Coin pack",
            amount: formattedAmount,
            coins: goldCoins,
            status: uiStatus
        )
    }
}

struct SavedPaymentCard: Identifiable, Equatable, Codable {
    let id: UUID
    let brand: String
    let lastFour: String
    var isDefault: Bool

    var display: String { "\(brand) •••• \(lastFour)" }

    /// 默认绑定的 Visa（固定 id，便于与 `UserDefaults` 合并；勿与用户手动添加的卡冲突）
    static let defaultBoundVisa = SavedPaymentCard(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        brand: "Visa",
        lastFour: "4242",
        isDefault: true
    )
}

extension RechargePackageModel {
    static let starterPackages: [RechargePackageModel] = [
        RechargePackageModel(
            packageId: 101,
            packageName: "Starter",
            totalCoins: 55,
            base: 50,
            bonus: 5,
            price: "$9.99",
            originalPrice: "$12.99",
            bonusLabel: "-23%"
        ),
        RechargePackageModel(
            packageId: 102,
            packageName: "Popular",
            totalCoins: 90,
            base: 75,
            bonus: 15,
            price: "$14.99",
            originalPrice: "$18.99",
            bonusLabel: "-21%"
        )
    ]

    static let morePackages: [RechargePackageModel] = [
        RechargePackageModel(
            packageId: 103,
            totalCoins: 120,
            base: 100,
            bonus: 20,
            price: "$19.99",
            originalPrice: "$24.99",
            bonusLabel: "-20%"
        ),
        RechargePackageModel(
            packageId: 104,
            totalCoins: 250,
            base: 200,
            bonus: 50,
            price: "$34.99",
            originalPrice: "$44.99",
            bonusLabel: "-22%"
        ),
        RechargePackageModel(
            packageId: 105,
            totalCoins: 520,
            base: 400,
            bonus: 120,
            price: "$59.99",
            originalPrice: "$79.99",
            bonusLabel: "-25%"
        ),
        RechargePackageModel(
            packageId: 106,
            totalCoins: 1100,
            base: 800,
            bonus: 300,
            price: "$99.99",
            originalPrice: "$129.99",
            bonusLabel: "-23%"
        )
    ]
}

extension RechargeRecordItem {
    static func sampleList() -> [RechargeRecordItem] {
        let cal = Calendar.current
        let now = Date()
        return [
            RechargeRecordItem(
                createdAt: cal.date(byAdding: .day, value: -1, to: now) ?? now,
                title: "Coin pack",
                amount: "$14.99",
                coins: 90,
                status: .completed
            ),
            RechargeRecordItem(
                createdAt: cal.date(byAdding: .day, value: -5, to: now) ?? now,
                title: "Coin pack",
                amount: "$9.99",
                coins: 55,
                status: .completed
            )
        ]
    }
}

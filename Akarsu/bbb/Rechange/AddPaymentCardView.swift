//
//  AddPaymentCardView.swift
//  bbb
//
//  参考: credit_card_details_refined_v4_compact
//

import SwiftUI

struct AddPaymentCardView: View {
    @Binding var cards: [SavedPaymentCard]
    var onComplete: () -> Void

    @State private var cardNumberDigits = ""
    @State private var expiry = ""
    @State private var cvv = ""
    @State private var holderName = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case number, expiry, cvv, name
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(AppLanguageStore.localized("add_card.footer"))
                            .font(.caption)
                            .foregroundStyle(AppTheme.onSurfaceVariant)

                        fieldBlock(title: AppLanguageStore.localized("add_card.field.number")) {
                            TextField("0000 0000 0000 0000", text: $cardNumberDigits)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .number)
                        }
                        .onChange(of: cardNumberDigits) { new in
                            cardNumberDigits = Self.sanitizeDigits(new, max: 19)
                        }

                        HStack(spacing: 12) {
                            fieldBlock(title: AppLanguageStore.localized("add_card.field.expires")) {
                                TextField("MM/YY", text: $expiry)
                                    .keyboardType(.numbersAndPunctuation)
                                    .focused($focusedField, equals: .expiry)
                            }
                            .onChange(of: expiry) { new in
                                expiry = Self.formatExpiry(new)
                            }

                            fieldBlock(title: AppLanguageStore.localized("add_card.field.cvv")) {
                                SecureField("•••", text: $cvv)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .cvv)
                            }
                            .onChange(of: cvv) { new in
                                cvv = String(Self.sanitizeDigits(new, max: 4).prefix(4))
                            }
                        }

                        fieldBlock(title: AppLanguageStore.localized("add_card.field.name")) {
                            TextField(AppLanguageStore.localized("add_card.placeholder.name"), text: $holderName)
                                .textInputAutocapitalization(.characters)
                                .focused($focusedField, equals: .name)
                        }

                        Button(action: saveCard) {
                            BBBTrackedText.text(AppLanguageStore.localized("add_card.save"), size: 14, weight: .heavy, tracking: 1.2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .foregroundStyle(.white)
                                .background(
                                    canSave
                                        ? AppTheme.primaryGradient
                                        : LinearGradient(
                                            colors: [AppTheme.outlineVariant, AppTheme.outlineVariant],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(!canSave)
                        .padding(.top, 8)
                    }
                    .padding(20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(AppLanguageStore.localized("add_card.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguageStore.localized("common.cancel")) { onComplete() }
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .tint(AppTheme.primary)
        .bbbRefreshOnAppLanguage()
    }

    private var canSave: Bool {
        let digits = cardNumberDigits.filter(\.isNumber)
        guard digits.count >= 16, cvv.count >= 3, holderName.trimmingCharacters(in: .whitespaces).count >= 2 else {
            return false
        }
        return expiry.filter(\.isNumber).count == 4
    }

    private func saveCard() {
        let digits = cardNumberDigits.filter(\.isNumber)
        guard digits.count >= 16 else { return }
        let lastFour = String(digits.suffix(4))
        let brand = Self.brand(fromFirstDigit: digits.first)
        let newId = UUID()
        for i in cards.indices {
            cards[i].isDefault = false
        }
        cards.append(SavedPaymentCard(id: newId, brand: brand, lastFour: lastFour, isDefault: true))
        onComplete()
    }

    private func fieldBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BBBTrackedText.text(title, size: 9, weight: .bold, tracking: 2, color: AppTheme.outlineVariant)
            content()
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.onSurface)
                .padding(14)
                .background(AppTheme.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.outlineVariant.opacity(0.35), lineWidth: 1)
                )
        }
    }

    private static func sanitizeDigits(_ s: String, max: Int) -> String {
        String(s.filter(\.isNumber).prefix(max))
    }

    private static func formatExpiry(_ raw: String) -> String {
        let d = String(raw.filter(\.isNumber).prefix(4))
        if d.count <= 2 { return d }
        let mm = String(d.prefix(2))
        let yy = String(d.dropFirst(2))
        return "\(mm)/\(yy)"
    }

    private static func brand(fromFirstDigit: Character?) -> String {
        guard let c = fromFirstDigit else { return "Card" }
        switch c {
        case "4": return "Visa"
        case "5": return "Mastercard"
        case "3": return "Amex"
        case "6": return "UnionPay"
        default: return "Card"
        }
    }
}

#Preview {
    AddPaymentCardView(cards: .constant([]), onComplete: {})
        .environmentObject(AppLanguageStore())
        .preferredColorScheme(.dark)
}

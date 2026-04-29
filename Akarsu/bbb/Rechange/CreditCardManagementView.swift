//
//  CreditCardManagementView.swift
//  bbb
//
//  参考: credit_card_management_panel, credit_card_management_empty_state
//

import SwiftUI

struct CreditCardManagementView: View {
    @Binding var cards: [SavedPaymentCard]
    @State private var showAddCard = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if cards.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(cards) { card in
                        cardRow(card)
                            .listRowBackground(AppTheme.surfaceContainerLow)
                            .modifier(ListRowSeparatorTintIfAvailable(tint: AppTheme.outlineVariant.opacity(0.2)))
                    }
                    .onDelete(perform: deleteCards)
                }
                .bbbListScrollContentHidden()
            }
        }
        .navigationTitle(AppLanguageStore.localized("cards.title"))
        .navigationBarTitleDisplayMode(.inline)
        .bbbNavigationBarBackground(AppTheme.background)
        .bbbLocalizedNavigationBackButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddCard = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
        .sheet(isPresented: $showAddCard) {
            AddPaymentCardView(cards: $cards) {
                showAddCard = false
            }
        }
        .bbbRefreshOnAppLanguage()
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.primary.opacity(0.45))
            Text(AppLanguageStore.localized("cards.empty"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)
            Text(AppLanguageStore.localized("cards.add_hint"))
                .font(.subheadline)
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
            Button {
                showAddCard = true
            } label: {
                Text(AppLanguageStore.localized("cards.add"))
                    .font(.system(size: 14, weight: .heavy))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(AppTheme.primaryGradient)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .padding(32)
    }

    private func cardRow(_ card: SavedPaymentCard) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "creditcard.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 44, height: 44)
                .background(AppTheme.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.display)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                if card.isDefault {
                    Text(AppLanguageStore.localized("cards.default"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.secondary)
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button(AppLanguageStore.localized("cards.set_default")) {
                    setDefault(card.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(AppTheme.onSurfaceVariant)
            }
        }
        .padding(.vertical, 6)
    }

    private func setDefault(_ id: UUID) {
        for i in cards.indices {
            cards[i].isDefault = (cards[i].id == id)
        }
    }

    private func deleteCards(at offsets: IndexSet) {
        var next = cards
        next.remove(atOffsets: offsets)
        if !next.contains(where: \.isDefault), let first = next.first {
            for i in next.indices {
                next[i].isDefault = (next[i].id == first.id)
            }
        }
        cards = next
    }
}

#Preview {
    NavigationView {
        CreditCardManagementView(cards: .constant([SavedPaymentCard.defaultBoundVisa]))
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .preferredColorScheme(.dark)
}

import LanguifyKit
import StoreKit
import SwiftUI

/// Transparent upgrade screen. Prices, trial terms and periods all come from
/// the App Store; limits come from the plan catalogue.
struct PaywallView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Product?

    var body: some View {
        let store = services.subscriptions
        let free = store.catalog.plan(.free)
        let premium = store.catalog.plan(.premium)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "crown.fill").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("Languify Premium").font(.largeTitle.bold())
                    Text("For when you're ready to start replying.").foregroundStyle(.secondary)

                    Card {
                        FeatureRow(title: "Live Rewind questions", free: "\(free.dailyLimits[.rewindQuestion] ?? 0) a day", premium: "\(premium.dailyLimits[.rewindQuestion] ?? 0) a day")
                        FeatureRow(title: "AI conversation practice", free: "Not included", premium: "\(premium.dailyLimits[.tutorTurn] ?? 0) turns a day")
                        FeatureRow(title: "Personalised lessons", free: "Not included", premium: "\(premium.dailyLimits[.lessonGeneration] ?? 0) a day")
                        FeatureRow(title: "Detailed explanations", free: "Not included", premium: "Included")
                        FeatureRow(title: "Session word suggestions", free: "Not included", premium: "Included")
                        FeatureRow(title: "Flashcards, quizzes, journal", free: "Included", premium: "Included")
                    }

                    if store.products.isEmpty {
                        if let error = store.loadError {
                            Text(error).foregroundStyle(.secondary)
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    } else {
                        ForEach(store.products, id: \.id) { product in
                            ProductOption(product: product, isSelected: (selected ?? store.products.first)?.id == product.id) {
                                selected = product
                            }
                        }
                        Button {
                            if let product = selected ?? store.products.first {
                                Task {
                                    await store.purchase(product)
                                    if store.tier == .premium { dismiss() }
                                }
                            }
                        } label: {
                            if store.isPurchasing { ProgressView() } else { Text("Continue") }
                        }
                        .primaryAction()
                        .disabled(store.isPurchasing)
                        .accessibilityIdentifier("paywall.continue")
                    }

                    if let error = store.purchaseError {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }

                    HStack {
                        Button("Restore purchases") { Task { await store.restore() } }
                        Spacer()
                        Link("Terms", destination: AppConfiguration.termsURL)
                        Link("Privacy", destination: AppConfiguration.privacyPolicyURL)
                    }
                    .font(.footnote)

                    Text("Subscriptions renew automatically until cancelled in Settings. Daily limits keep the service fast and affordable for everyone.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { if store.products.isEmpty { await store.load() } }
        }
    }
}

private struct FeatureRow: View {
    let title: String
    let free: String
    let premium: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack {
                Text("Free: \(free)").foregroundStyle(.secondary)
                Spacer()
                Text("Premium: \(premium)")
            }
            .font(.footnote)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProductOption: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(.headline)
                    Text(periodText).font(.subheadline).foregroundStyle(.secondary)
                    if let trial = trialText {
                        Text(trial).font(.caption).foregroundStyle(.tint)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var periodText: String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        let unit: String = switch period.unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
        return period.value == 1 ? "\(product.displayPrice) per \(unit)" : "\(product.displayPrice) every \(period.value) \(unit)s"
    }

    private var trialText: String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let p = offer.period
        let unit: String = switch p.unit {
        case .day: p.value == 1 ? "day" : "days"
        case .week: p.value == 1 ? "week" : "weeks"
        case .month: p.value == 1 ? "month" : "months"
        case .year: p.value == 1 ? "year" : "years"
        @unknown default: "periods"
        }
        return "\(p.value) \(unit) free, then \(product.displayPrice)"
    }
}

import Foundation
import OpenNoTypeCore

/// A conservative typing gate for an opt-in translation review, not a calibrated accuracy score.
enum TranslationProtectionPolicy {
    enum Verdict: Equatable { case accepted, uncertain, meaningChanged, invalid }

    static func requiresReview(mode: InputMode, enabled: Bool, reviewMode: DecisionReviewMode) -> Bool {
        mode == .translation && enabled && reviewMode == .protect
    }

    static func verdict(for review: DecisionResult, detailed: Bool) -> Verdict {
        guard JevRepairPolicy.reviewIsValid(review), review.terms.isEmpty,
              Set(review.detailRisks.keys) == Set(detailed ? DecisionDetailAxis.allCases : []) else { return .invalid }
        // Noul risks have no separate confidence field. Intermediate answers do not authorize typing.
        if review.maximumRiskProbability <= 0.1 { return .accepted }
        return review.maximumRiskProbability >= 0.9 ? .meaningChanged : .uncertain
    }
}

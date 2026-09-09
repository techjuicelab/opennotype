import Foundation

@MainActor final class ProbeClock {
    var elapsed: Double = 0
    var current = ""
    var lateAXPending = false
    var pasteCount = 0
    func advance(_ amount: Double) async {
        elapsed += amount
        if lateAXPending && elapsed >= 1.05 {
            current += "입력"
            lateAXPending = false
        }
    }
}

@main struct Probe {
    @MainActor static func main() async {
        let clock = ProbeClock()
        let verification = InsertionVerification(readValue: { clock.current }, now: { clock.elapsed }, pause: clock.advance)
        let outcome = await InsertionDelivery.perform(accessibility: {
            clock.lateAXPending = true
            return .accepted
        }, verifyAccessibility: {
            await verification.wait(for: "입력", method: .accessibility, isCancelled: { false })
        }, accessibilityWasIgnored: {
            clock.current == ""
        }, paste: {
            clock.pasteCount += 1
            clock.current += "입력"
            return await verification.wait(for: "입력", method: .paste, isCancelled: { false })
        }, isCancelled: { false })
        print("outcome=\(outcome.diagnosticCode) pasteCount=\(clock.pasteCount) resultingCopies=\(clock.current == "입력입력" ? 2 : 1)")
        precondition(clock.pasteCount == 1 && clock.current == "입력입력")
    }
}

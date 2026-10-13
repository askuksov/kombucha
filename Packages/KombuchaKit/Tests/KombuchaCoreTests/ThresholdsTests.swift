import KombuchaCore
import Testing

private func isValid(_ thresholds: Thresholds) -> Bool {
    Thresholds.lowerRange.contains(thresholds.lower)
        && Thresholds.upperRange.contains(thresholds.upper)
        && thresholds.upper - thresholds.lower >= Thresholds.minimumGap
}

private let legalPairs: [Thresholds] = {
    var pairs: [Thresholds] = []
    for lower in Thresholds.lowerRange {
        for upper in Thresholds.upperRange where upper - lower >= Thresholds.minimumGap {
            pairs.append(Thresholds.normalized(lower: lower, upper: upper))
        }
    }
    return pairs
}()

@Test func theStandardRangeIsSeventyFiveToEighty() {
    #expect(Thresholds.standard.lower == 75)
    #expect(Thresholds.standard.upper == 80)
    #expect(isValid(Thresholds.standard))
}

@Test(arguments: [
    ((75, 80), (75, 80)),
    ((90, 10), (50, 55)),
    ((-3, 200), (40, 95)),
    ((85, 85), (80, 85)),
])
func normalizedMatchesTheDocumentedExamples(input: (lower: Int, upper: Int), expected: (lower: Int, upper: Int)) {
    let thresholds = Thresholds.normalized(lower: input.lower, upper: input.upper)
    #expect(thresholds.lower == expected.lower)
    #expect(thresholds.upper == expected.upper)
}

@Test func normalizedIsTotalOverAWideRangeAndKeepsTheInvariants() {
    var violations: [String] = []
    for lower in -10...260 {
        for upper in -10...260 {
            let thresholds = Thresholds.normalized(lower: lower, upper: upper)
            if !isValid(thresholds) {
                violations.append("(\(lower), \(upper)) → (\(thresholds.lower), \(thresholds.upper))")
            }
        }
    }
    #expect(violations.isEmpty)
}

@Test func normalizedNeverTrapsOnTheExtremesOfInt() {
    let extremes = [Int.min, Int.min + 1, -1, 0, Int.max - 1, Int.max]
    var violations: [String] = []
    for lower in extremes {
        for upper in extremes where !isValid(Thresholds.normalized(lower: lower, upper: upper)) {
            violations.append("(\(lower), \(upper))")
        }
    }
    #expect(violations.isEmpty)
}

@Test func everyLegalPairIsItsOwnNormalisation() {
    var violations: [String] = []
    for pair in legalPairs where Thresholds.normalized(lower: pair.lower, upper: pair.upper) != pair {
        violations.append("(\(pair.lower), \(pair.upper))")
    }
    #expect(violations.isEmpty)
    #expect(legalPairs.count == 1256)
}

@Test func movingTheResumeThresholdNeverMovesTheStopThreshold() {
    var violations: [String] = []
    for pair in legalPairs {
        for value in 0...100 {
            let moved = pair.movingLower(to: value)
            if moved.upper != pair.upper || !isValid(moved) {
                violations.append("(\(pair.lower), \(pair.upper)) lower→\(value) gave (\(moved.lower), \(moved.upper))")
            }
        }
    }
    #expect(violations.isEmpty)
}

@Test func movingTheStopThresholdNeverMovesTheResumeThreshold() {
    var violations: [String] = []
    for pair in legalPairs {
        for value in 0...100 {
            let moved = pair.movingUpper(to: value)
            if moved.lower != pair.lower || !isValid(moved) {
                violations.append("(\(pair.lower), \(pair.upper)) upper→\(value) gave (\(moved.lower), \(moved.upper))")
            }
        }
    }
    #expect(violations.isEmpty)
}

@Test func aMoveLandsOnTheValueWhenTheValueIsAllowed() {
    let range = Thresholds.standard
    #expect(range.movingLower(to: 60).lower == 60)
    #expect(range.movingUpper(to: 95).upper == 95)
}

@Test func aMoveStopsAtTheCapTheOtherThresholdImposes() {
    let range = Thresholds.standard
    #expect(range.movingLower(to: 90).lower == 75)
    #expect(range.movingLower(to: 0).lower == 40)
    #expect(range.movingUpper(to: 50).upper == 80)
    #expect(range.movingUpper(to: 200).upper == 95)
}

@Test func theCapsAreIndependentConstants() {
    let wide = Thresholds.normalized(lower: 40, upper: 95)
    #expect(wide.movingLower(to: 100).lower == 85)
    let narrow = Thresholds.normalized(lower: 40, upper: 55)
    #expect(narrow.movingUpper(to: 0).upper == 55)
}

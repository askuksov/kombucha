import CoreGraphics
import Testing
@testable import Kombucha

// Thumb is 22 pt, so a 122 pt track gives the thumb centre exactly 100 pt of travel.
private let bounds = 40...140
private let width: CGFloat = 122

@Test(arguments: [(CGFloat(11), 40), (CGFloat(61), 90), (CGFloat(111), 140)])
func aTouchMapsOntoThePercentUnderTheThumbCentre(x: CGFloat, expected: Int) {
    #expect(ThresholdSlider.value(forX: x, width: width, bounds: bounds) == expected)
}

@Test func aTouchPastEitherEndStopsAtTheBound() {
    #expect(ThresholdSlider.value(forX: -50, width: width, bounds: bounds) == 40)
    #expect(ThresholdSlider.value(forX: 500, width: width, bounds: bounds) == 140)
}

@Test func aTouchBetweenTwoPercentsRoundsToTheNearest() {
    #expect(ThresholdSlider.value(forX: 11.4, width: width, bounds: bounds) == 40)
    #expect(ThresholdSlider.value(forX: 11.6, width: width, bounds: bounds) == 41)
}

@Test func aTrackNarrowerThanTheThumbReadsAsTheLowerBound() {
    #expect(ThresholdSlider.value(forX: 10, width: 20, bounds: bounds) == 40)
}

@Test(arguments: [40, 41, 90, 139, 140])
func theThumbOffsetMapsBackToTheSamePercent(percent: Int) {
    let offset = ThresholdSlider.thumbOffset(of: percent, width: width, bounds: bounds)
    #expect(ThresholdSlider.value(forX: offset + 11, width: width, bounds: bounds) == percent)
}

@Test func theThumbOffsetStaysInsideTheTrack() {
    #expect(ThresholdSlider.thumbOffset(of: 0, width: width, bounds: bounds) == 0)
    #expect(ThresholdSlider.thumbOffset(of: 500, width: width, bounds: bounds) == 100)
}

import KombuchaCore
import Testing

@Test func aGoodReadingKeepsItsValue() {
    let readings = PowerReadings.derive(system: 5.25, adapter: 60)
    #expect(readings == PowerReadings(systemWatts: 5.25, adapterWatts: 60))
}

@Test func aZeroIsARealReading() {
    #expect(PowerReadings.derive(system: 0, adapter: 0) == PowerReadings(systemWatts: 0, adapterWatts: 0))
}

@Test(arguments: [nil, -0.5, Float.nan, Float.infinity, -Float.infinity, 400.5, 5000] as [Float?])
func anUnrealValueBecomesNilNeverAZero(raw: Float?) {
    #expect(PowerReadings.derive(system: raw, adapter: 5) == PowerReadings(systemWatts: nil, adapterWatts: 5))
    #expect(PowerReadings.derive(system: 5, adapter: raw) == PowerReadings(systemWatts: 5, adapterWatts: nil))
}

@Test func theCeilingItselfIsAccepted() {
    #expect(PowerReadings.derive(system: 400, adapter: nil) == PowerReadings(systemWatts: 400, adapterWatts: nil))
}

@Test func aNegativeZeroIsPlainZero() {
    let watts = PowerReadings.derive(system: -0.0, adapter: nil).systemWatts
    #expect(watts == 0)
    #expect(watts?.sign == .plus)
}

@Test func theAverageOfOneReadingIsThatReading() {
    let reading = PowerReadings(systemWatts: 5, adapterWatts: 6)
    #expect(PowerReadings.average([reading]) == reading)
}

@Test func theAverageOfTwoReadingsIsTheMeanPerField() {
    let mean = PowerReadings.average([PowerReadings(systemWatts: 5, adapterWatts: 6),
                                      PowerReadings(systemWatts: 8, adapterWatts: 6)])
    #expect(mean == PowerReadings(systemWatts: 6.5, adapterWatts: 6))
}

@Test func aNilIsIgnoredPerFieldInTheAverage() {
    let mean = PowerReadings.average([PowerReadings(systemWatts: nil, adapterWatts: 6),
                                      PowerReadings(systemWatts: 4, adapterWatts: 8)])
    #expect(mean == PowerReadings(systemWatts: 4, adapterWatts: 7))
}

@Test func aFieldNoReadingHasStaysNil() {
    let mean = PowerReadings.average([PowerReadings(systemWatts: nil, adapterWatts: 6),
                                      PowerReadings(systemWatts: nil, adapterWatts: 6)])
    #expect(mean == PowerReadings(systemWatts: nil, adapterWatts: 6))
}

@Test func theAverageOfNothingIsAllNil() {
    #expect(PowerReadings.average([]) == PowerReadings(systemWatts: nil, adapterWatts: nil))
}

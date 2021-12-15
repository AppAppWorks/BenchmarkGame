//
//  File.swift
//  
//
//  Created by Lau Chun Kai on 15/12/2021.
//

import Foundation
import XCTest
import BinaryTrees_Fast

final class PerformanceTests : XCTestCase {
    func testPerformance() {
        measure {
            benchmark(21)
        }
    }
}

//'-[BinaryTrees_FastTests.PerformanceTests testPerformance]' measured [Time, seconds] average: 0.378, relative standard deviation: 1.933%, values: [0.392240, 0.379023, 0.371601, 0.372994, 0.367238, 0.388590, 0.374748, 0.382012, 0.379893, 0.375131], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
//Test Case '-[BinaryTrees_FastTests.PerformanceTests testPerformance]' passed (9.048 seconds).
//Test Suite 'PerformanceTests' passed at 2021-12-16 00:09:39.767.
//     Executed 1 test, with 0 failures (0 unexpected) in 9.048 (9.048) seconds
//Test Suite 'BinaryTrees_FastTests.xctest' passed at 2021-12-16 00:09:39.767.
//     Executed 1 test, with 0 failures (0 unexpected) in 9.048 (9.049) seconds
//Test Suite 'All tests' passed at 2021-12-16 00:09:39.767.
//     Executed 1 test, with 0 failures (0 unexpected) in 9.048 (9.049) seconds
//Program ended with exit code: 0

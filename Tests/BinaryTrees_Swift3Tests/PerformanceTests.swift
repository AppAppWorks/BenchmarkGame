//
//  File.swift
//
//
//  Created by Lau Chun Kai on 15/12/2021.
//

import Foundation
import XCTest
import BinaryTrees_Swift3

final class PerformanceTests : XCTestCase {
    func testPerformance() {
        measure {
            benchmark(21)
        }
    }
}

//'-[BinaryTrees_Swift3Tests.PerformanceTests testPerformance]' measured [Time, seconds] average: 19.589, relative standard deviation: 3.082%, values: [19.865055, 18.976427, 19.870546, 20.728978, 19.110407, 19.518952, 18.974869, 19.523345, 18.888013, 20.429766], performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.100, maxStandardDeviation: 0.100
//Test Case '-[BinaryTrees_Swift3Tests.PerformanceTests testPerformance]' passed (201.188 seconds).
//Test Suite 'PerformanceTests' passed at 2021-12-16 00:08:00.490.
//     Executed 1 test, with 0 failures (0 unexpected) in 201.188 (201.188) seconds
//Test Suite 'BinaryTrees_Swift3Tests.xctest' passed at 2021-12-16 00:08:00.490.
//     Executed 1 test, with 0 failures (0 unexpected) in 201.188 (201.189) seconds
//Test Suite 'All tests' passed at 2021-12-16 00:08:00.490.
//     Executed 1 test, with 0 failures (0 unexpected) in 201.188 (201.189) seconds

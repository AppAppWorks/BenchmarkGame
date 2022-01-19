//
//  File.swift
//
//
//  Created by Lau Chun Kai on 15/12/2021.
//

import Foundation
import XCTest
import Fasta_Fast

final class PerformanceTests : XCTestCase {
    func testPerformance() {
        let n = 25000000
        measure {
            benchmark(n)
        }
    }
}

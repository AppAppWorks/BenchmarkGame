//
//  File.swift
//
//
//  Created by Lau Chun Kai on 15/12/2021.
//

import Foundation
import XCTest
import Fasta_Swift3

final class PerformanceTests : XCTestCase {
    func testPerformance() {
        measure {
            benchmark(25000000)
        }
    }
}

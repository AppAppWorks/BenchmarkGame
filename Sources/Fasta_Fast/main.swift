/*
 Based on Swift #3 for Fasta
 https://benchmarksgame-team.pages.debian.net/benchmarksgame/program/fasta-swift-3.html
 Adopted SIMD techniques from Rust #7
 Contributed by Richard Lau
*/

import Foundation
import Dispatch

#if arch(arm64)
import _Builtin_intrinsics.arm.neon
public typealias S4x32 = int32x4_t
#else
import _Builtin_intrinsics.intel
public typealias S4x32 = __m128i
#endif

extension S4x32 {
    public mutating func cmplt(_ a: Self, _ b: Self) {
#if arch(arm64)
        self = vsubq_s32(self, withUnsafeBytes(of: vcltq_s32(a, b)) {
            $0.bindMemory(to: Self.self).baseAddress!.pointee
        })
#else
        self = _mm_sub_epi32(self, withUnsafeBytes(of: _mm_cmplt_epi32(a, b)) {
            $0.bindMemory(to: Self.self).baseAddress!.pointee
        })
#endif
    }

    func combine() -> Int32 {
#if arch(arm64)
        vaddvq_s32(self)
#else
        Int32(self[0] >> 32) +
        Int32(truncatingIfNeeded: self[0]) +
        Int32(self[1] >> 32) +
        Int32(truncatingIfNeeded: self[1])
#endif
    }
}

public struct WeightedRandom<T> {
    public var cumprob: [UInt32]
    public var elements: [T]

    public init<F>(mapping: ContiguousArray<(prob: F, sym: T)>) where F : BinaryFloatingPoint {
        assert(!mapping.isEmpty)
        assert(mapping.count <= 16)

        var acc: F = 0

        var elements: [T]?

        cumprob = .init(unsafeUninitializedCapacity: 16) { cumprob, cumprobCount in
            cumprob.initialize(repeating: .init(Int32.max))
            
            elements = .init(unsafeUninitializedCapacity: 16) { elements, elementsCount in
                for (i, map) in mapping.enumerated() {
                    elements[i] = map.sym
                    acc += map.prob
                    cumprob[i] = UInt32(acc * F(IM))
                }
                elementsCount = 16
            }
            cumprobCount = 16
        }

        self.elements = elements!
    }

    func genFromU32(prob: UInt32) -> T {
        #if arch(arm64)
        let needle = S4x32(repeating: .init(prob))
        #else
        let needle = _mm_set1_epi32(.init(prob))
        #endif

        return cumprob.withUnsafeBytes { rawPtr in
            var ptr = rawPtr.baseAddress!
            let vcp1 = ptr.assumingMemoryBound(to: S4x32.self).pointee
            ptr += 16
            let vcp2 = ptr.assumingMemoryBound(to: S4x32.self).pointee
            ptr += 16
            let vcp3 = ptr.assumingMemoryBound(to: S4x32.self).pointee
            ptr += 16
            let vcp4 = ptr.assumingMemoryBound(to: S4x32.self).pointee

            var count = S4x32()
            count.cmplt(vcp1, needle)
            count.cmplt(vcp2, needle)
            count.cmplt(vcp3, needle)
            count.cmplt(vcp4, needle)

            let idx = count.combine()
            return elements.withUnsafeBufferPointer {
                $0[Int(idx)]
            }
        }
    }
}

extension UInt8 : ExpressibleByUnicodeScalarLiteral {
    public typealias UnicodeScalarLiteralType = UnicodeScalar

    public init(unicodeScalarLiteral value: UnicodeScalar) {
        self.init(ascii: value)
    }
}

public struct MyRandom {
    var seed: UInt32
    var count: Int
    var threadCount: UInt16
    var nextThreadId: UInt16
}

public extension MyRandom {
    init(count: Int, threadCount: UInt16) {
        self.init(seed: 42, count: count, threadCount: threadCount, nextThreadId: 0)
    }
    
    mutating func reset(count: Int) {
        nextThreadId = 0
        self.count = count
    }
    
    // performance bottlecheck
    mutating func gen(buf: UnsafeMutableBufferPointer<UInt32>, curThead: UInt16) -> Int? {
        guard nextThreadId == curThead else {
            return nil
        }
        nextThreadId = (nextThreadId + 1) % threadCount
        
        let toGen = min(buf.count, count)
        for i in 0..<toGen {
            seed = (seed * 3877 + 29573) % IM
            buf[i] = seed
        }
        count -= toGen
        return toGen
    }
}

let linewidth = 60
let bufferLines = 10240
let rndBufSize = (bufferLines * linewidth)
let writeBufSize = (bufferLines * (linewidth + 1))

let IM: UInt32 = 139968
let IA: UInt32 = 3877
let IC: UInt32 = 29573
var seed: UInt32 = 42

public typealias AminoAcid = (prob: Double, sym: UInt8)

// Build a block in fasta format
public func buildFastaBlockFromString(s: String) -> [UInt8] {
    // Build block of linewidth characters wide string
    .init(unsafeUninitializedCapacity: s.count * (linewidth + 1)) { ptr, capacity in
        s.utf8.withContiguousStorageIfAvailable { s in
            var blockIn = ptr.baseAddress!
            let beg = s.baseAddress!
            var offset = 0
            for _ in 0..<s.count {
                let firstCount = min(linewidth, s.count - offset)
                blockIn.assign(from: beg + offset, count: firstCount)
                blockIn += firstCount
                offset += firstCount

                let secondCount = linewidth - firstCount
                if secondCount > 0 {
                    blockIn.assign(from: beg, count: secondCount)
                    blockIn += secondCount
                    offset = secondCount
                }

                blockIn.pointee = .init(ascii: "\n")
                blockIn = blockIn.successor()
            }

            blockIn.predecessor().pointee = 0
        }

        capacity = ptr.count
    }
}

// Print alu string in fasta format
public func repeatFasta(n: Int, alu: inout [UInt8]) {
    var aluLen = n + n / linewidth
    let aluSize = alu.count + 1
    if aluLen > aluSize {
        for _ in 0..<aluLen / aluSize {
            print(String(cString: alu))
        }
        aluLen -= (aluLen / aluSize) * aluSize
    }
    // Remove newline at the end because print adds it anyhow
    if n % linewidth == 0 {
        aluLen -= 1
    }
    if aluLen > 0 {
        alu[..<aluLen].withContiguousStorageIfAvailable {
            print(String(cString: $0.baseAddress!))
        }
    }
}

let LINE_LENGTH = 60
let LINES = 1024
let BLKLEN = LINE_LENGTH * LINES

public func fastRandom(
    threadId: UInt16,
    rng: UnsafeMutablePointer<MyRandom>,
    pSemaphore: DispatchSemaphore,
    rSemaphore: DispatchSemaphore,
    wr: WeightedRandom<UInt8>
) {
    let rngBuf = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: BLKLEN)
    let outBuf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: BLKLEN + LINES)
    defer {
        rngBuf.deallocate()
        outBuf.deallocate()
    }

    while true {
        let count: Int = {
            rSemaphore.wait()
            
            while true {
                if let x = rng.pointee.gen(buf: rngBuf, curThead: threadId) {
                    rSemaphore.signal()
                    return x
                }
            }
        }()
        
        guard count > 0 else {
            break
        }
        
        let rngBuf = Slice(base: rngBuf, bounds: 0..<count)
        
        var lineCount = 0
        
        for begin in stride(from: 0, to: rngBuf.count, by: LINE_LENGTH) {
            let end = min(begin + LINE_LENGTH, rngBuf.count)
            
            for j in begin..<end {
                let rn = rngBuf[j]
                outBuf[j + lineCount] = wr.genFromU32(prob: rn)
            }
            
            outBuf[end + lineCount] = .init(ascii: "\n")
            lineCount += 1
        }
        
        pSemaphore.wait()
        
        outBuf[rngBuf.count + lineCount] = 0
        print(String(cString: outBuf.baseAddress!))
        
        pSemaphore.signal()
    }
}

public func fastaRandomPar(
    rng: inout MyRandom,
    wr: WeightedRandom<UInt8>,
    numThreads: UInt16
) {
    let group = DispatchGroup()
    let pSemaphore = DispatchSemaphore(value: 1)
    let rSemaphore = DispatchSemaphore(value: 1)
    
    withUnsafeMutablePointer(to: &rng) { rng in
        for thread in 0..<numThreads {
            DispatchQueue.global().async(group: group) {
                fastRandom(threadId: thread, rng: rng, pSemaphore: pSemaphore, rSemaphore: rSemaphore, wr: wr)
            }
        }
    }

    group.wait()
}

// Read command line parameters
let n: Int
if CommandLine.arguments.count > 1 {
    n = Int(CommandLine.arguments[1]) ?? 1000
} else {
    n = 25000000
}

public func benchmark(_ n: Int) {
    // String to repeat
    let alu = "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTC" +
              "GAGACCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAATACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTG" +
              "TAATCCCAGCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCG" +
              "CCACTGCACTCCAGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA"

    // Amino acids and their probabilities
    let iub = [
        AminoAcid(0.27, "a"),
        AminoAcid(0.12, "c"),
        AminoAcid(0.12, "g"),
        AminoAcid(0.27, "t"),
        AminoAcid(0.02, "B"),
        AminoAcid(0.02, "D"),
        AminoAcid(0.02, "H"),
        AminoAcid(0.02, "K"),
        AminoAcid(0.02, "M"),
        AminoAcid(0.02, "N"),
        AminoAcid(0.02, "R"),
        AminoAcid(0.02, "S"),
        AminoAcid(0.02, "V"),
        AminoAcid(0.02, "W"),
        AminoAcid(0.02, "Y"),
    ] as ContiguousArray

    let homosapiens = [
        AminoAcid(0.3029549426680, "a"),
        AminoAcid(0.1979883004921, "c"),
        AminoAcid(0.1975473066391, "g"),
        AminoAcid(0.3015094502008, "t"),
    ] as ContiguousArray
    
    // Build block of linewidth characters wide string
    var aluBlock = buildFastaBlockFromString(s: alu)

    print(">ONE Homo sapiens alu")
    repeatFasta(n: 2*n, alu: &aluBlock)

    let iub_ = WeightedRandom(mapping: iub)

    let numThreads: UInt16 = .init(ProcessInfo.processInfo.activeProcessorCount)

    var rng = MyRandom(count: n * 3, threadCount: numThreads)

    print(">TWO IUB ambiguity codes")
    fastaRandomPar(rng: &rng, wr: iub_, numThreads: numThreads)

    rng.reset(count: n * 5)

    let homosapiens_ = WeightedRandom(mapping: homosapiens)

    print(">THREE Homo sapiens frequency")
    fastaRandomPar(rng: &rng, wr: homosapiens_, numThreads: numThreads)
}

benchmark(n)

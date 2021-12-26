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
typealias S4x32 = int32x4_t
#else
import _Builtin_intrinsics.intel
typealias S4x32 = __m128i
#endif

extension S4x32 {
    @usableFromInline
    mutating func cmplt(_ a: Self, _ b: Self) {
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

    @usableFromInline
    func combined() -> Int32 {
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

@usableFromInline
func print(_ items: Any..., terminator: String = "") {
    
}

@usableFromInline
struct WeightedRandom<T> {
    @usableFromInline
    var cumprob: [UInt32]
    @usableFromInline
    var elements: [T]

    @usableFromInline
    init<F>(mapping: ContiguousArray<(prob: F, sym: T)>, IM: UInt32) where F : BinaryFloatingPoint {
        assert(!mapping.isEmpty)
        assert(mapping.count <= 16)

        var acc: F = 0

        var elements: [T]?

        cumprob = .init(unsafeUninitializedCapacity: 16) { cumprob, cumprobCount in
            elements = .init(unsafeUninitializedCapacity: 16) { elements, elementsCount in
                for (i, map) in mapping.enumerated() {
                    elements[i] = map.sym
                    acc += map.prob
                    cumprob[i] = UInt32(acc * F(IM))
                }
                cumprob[15] = .init(Int32.max)
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

            let idx = count.combined()
            return elements.withUnsafeBufferPointer {
                $0[Int(idx)]
            }
        }
    }
}

extension WeightedRandom where T == UInt8 {
    // Consumer task
    @usableFromInline
    func consumeRandom(n: Int, block: Int, const: UnsafeMutablePointer<Const>) {
        var bufPtr = const.pointee.cBufs[block]
        var lineCounter = 0
        let buf = const.pointee.bufs[block]

        for i in 0..<Swift.min(n, const.pointee.rndBufSize) {
            let e = buf[i]
            let c = genFromU32(prob: e)

            bufPtr.pointee = c
            lineCounter += 1
            bufPtr = bufPtr.successor()
            if lineCounter == const.pointee.linewidth {
                bufPtr.pointee = 10
                bufPtr = bufPtr.successor()
                lineCounter = 0
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

@usableFromInline
typealias AminoAcid = (prob: Double, sym: UInt8)

// for some reason static variables aren't initialized before the testing block
// we group the static variables under a struct to change the precedence of
// initialization
@usableFromInline
struct Const {
    @usableFromInline
    let linewidth = 60
    @usableFromInline
    let bufferLines = 10240
    @usableFromInline
    let rndBufSize: Int
    @usableFromInline
    let writeBufSize: Int

    @usableFromInline
    let IM: UInt32 = 139968
    @usableFromInline
    let IA: UInt32 = 3877
    @usableFromInline
    let IC: UInt32 = 29573
    @usableFromInline
    var seed: UInt32 = 42

    // String to repeat
    @usableFromInline
    let alu = "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGGGAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTC" +
              "GAGACCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAATACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTG" +
              "TAATCCCAGCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGGAGGCGGAGGTTGCAGTGAGCCGAGATCGCG" +
              "CCACTGCACTCCAGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA"

    // Amino acids and their probabilities
    @usableFromInline
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

    @usableFromInline
    let homosapiens = [
        AminoAcid(0.3029549426680, "a"),
        AminoAcid(0.1979883004921, "c"),
        AminoAcid(0.1975473066391, "g"),
        AminoAcid(0.3015094502008, "t"),
    ] as ContiguousArray

    // Allocate some resources to buffer data and
    // handle ownership by semaphores
    @usableFromInline
    let nBufs = 4   // need to be a power of two
    @usableFromInline
    let bufs: [UnsafeMutablePointer<UInt32>]
    @usableFromInline
    let cBufs: [UnsafeMutablePointer<UInt8>]
    @usableFromInline
    let pSemaphore: [DispatchSemaphore]
    @usableFromInline
    let wSemaphore: [DispatchSemaphore]

    @usableFromInline
    init() {
        let rndBufSize = (bufferLines * linewidth)
        self.rndBufSize = rndBufSize
        let writeBufSize = (bufferLines * (linewidth + 1))
        self.writeBufSize = writeBufSize

        bufs = (0..<nBufs).map { _ in UnsafeMutablePointer<UInt32>.allocate(capacity: rndBufSize) }
        cBufs = (0..<nBufs).map { _ in UnsafeMutablePointer<UInt8>.allocate(capacity: writeBufSize) }
        pSemaphore = (0..<nBufs).map { _ in DispatchSemaphore(value: 1) }
        wSemaphore = (0..<nBufs).map { _ in DispatchSemaphore(value: 1) }
    }

    @usableFromInline
    func `deinit`() {
        for i in 0..<nBufs {
            bufs[i].deallocate()
            cBufs[i].deallocate()
        }
    }
}

// Read command line parameters
let n: Int
if CommandLine.arguments.count > 1 {
    n = Int(CommandLine.arguments[1]) ?? 1000
} else {
    n = 25000000
}

@inlinable
public func benchmark(_ n: Int) {
    var const = Const()
    defer {
        const.deinit()
    }

    // Let's have some queues to produce data, consume it
    // and to syncronize data ownership
    let cQueue = DispatchQueue(label: "Consumer", attributes: .concurrent)
    let pQueue = DispatchQueue(label: "Producer", attributes: [])
    let wQueue = DispatchQueue(label: "Writer", attributes: [])
    let group = DispatchGroup()

    // Build a block in fasta format
    func buildFastaBlockFromString(s: String, const: UnsafeMutablePointer<Const>) -> [UInt8] {
        // Build block of linewidth characters wide string
        s.utf8.withContiguousStorageIfAvailable { s in
                .init(unsafeUninitializedCapacity: s.count * (const.pointee.linewidth + 1)) { ptr, capacity in
                    var blockIn = ptr.baseAddress!
                    let beg = s.baseAddress!
                    var offset = 0
                    for _ in 0..<s.count {
                        let firstCount = min(const.pointee.linewidth, s.count - offset)
                        blockIn.assign(from: beg + offset, count: firstCount)
                        blockIn += firstCount
                        offset += firstCount

                        let secondCount = const.pointee.linewidth - firstCount
                        if secondCount > 0 {
                            blockIn.assign(from: beg, count: secondCount)
                            blockIn += secondCount
                            offset = secondCount
                        }

                        blockIn.pointee = .init(ascii: "\n")
                        blockIn = blockIn.successor()
                    }

                    blockIn.predecessor().pointee = 0

                    capacity = ptr.count
                }
        }!
    }

    // random
    func random(_ const: UnsafeMutablePointer<Const>) -> UInt32 {
        const.pointee.seed = (const.pointee.seed * const.pointee.IA + const.pointee.IC) % const.pointee.IM
        return const.pointee.seed
    }

    // Producer task
    func genRandom(n: Int, block: Int, const: UnsafeMutablePointer<Const>) {
        let ptr = const.pointee.bufs[block]
        for i in 0..<min(n, const.pointee.rndBufSize) {
            ptr[i] = random(const)
        }
    }

    // Print random amino acid sequences
    func randomFasta(n: Int, acids: ContiguousArray<AminoAcid>, const: UnsafeMutablePointer<Const>) {
        // Adjust probability to cumulative
        let cumAcid = WeightedRandom(mapping: acids, IM: const.pointee.IM)

        let junks = (n + const.pointee.rndBufSize - 1) / const.pointee.rndBufSize
        let remainder = n % const.pointee.rndBufSize
        var deferedWrite = [Int]()
        var writeBlock = 0
        group.enter()

        pQueue.async {

            for i in 0..<junks-1 {
                let block = i % const.pointee.bufs.count
                const.pointee.pSemaphore[block].wait()
                genRandom(n: const.pointee.rndBufSize, block: block, const: const)
                cQueue.async(group: group) {

                    const.pointee.wSemaphore[block].wait()
                    cumAcid.consumeRandom(n: const.pointee.rndBufSize, block: block, const: const)
                    const.pointee.pSemaphore[block].signal()
                    wQueue.async(group: group) {

                        if block != writeBlock {
                            deferedWrite.append(block)
                        } else {
                            print(String(cString: const.pointee.cBufs[block]), terminator: "")
                            writeBlock = (writeBlock + 1) & (const.pointee.nBufs - 1)
                            const.pointee.wSemaphore[block].signal()
                            if deferedWrite.count > 0 {
                                while deferedWrite.contains(writeBlock) {
                                    let blk = writeBlock
                                    print(String(cString: const.pointee.cBufs[blk]), terminator: "")
                                    writeBlock = (writeBlock + 1) & (const.pointee.nBufs - 1)
                                    deferedWrite.remove(at: deferedWrite.firstIndex(of: blk)!)
                                    const.pointee.wSemaphore[blk].signal()
                                }
                            }
                        }
                    }
                }
            }
            group.leave()
        }
        group.wait()
        genRandom(n: remainder, block: 0, const: const)
        cumAcid.consumeRandom(n: remainder, block: 0, const: const)

        var stringRemainder = remainder+(remainder/const.pointee.linewidth)
        if stringRemainder % (const.pointee.linewidth+1) == 0 {
            stringRemainder -= 1
        }
        
        print(const.pointee.cBufs[0].withMemoryRebound(to: UInt8.self, capacity: stringRemainder) {
            String(cString: $0)
        })
    }

    // Print alu string in fasta format
    func repeatFasta(n: Int, alu: inout [UInt8], const: inout Const) {
        var aluLen = n + n / const.linewidth
        let aluSize = alu.count + 1
        if aluLen > aluSize {
            for _ in 0..<aluLen / aluSize {
                print(String(cString: alu))
            }
            aluLen -= (aluLen / aluSize) * aluSize
        }
        // Remove newline at the end because print adds it anyhow
        if n % const.linewidth == 0 {
            aluLen -= 1
        }
        if aluLen > 0 {
            alu[..<aluLen].withContiguousStorageIfAvailable {
                print(String(cString: $0.baseAddress!))
            }
        }
    }

    // Build block of linewidth characters wide string
    var aluBlock = buildFastaBlockFromString(s: const.alu, const: &const)

    print(">ONE Homo sapiens alu")
    repeatFasta(n: 2*n, alu: &aluBlock, const: &const)

    print(">TWO IUB ambiguity codes")
    randomFasta(n: 3*n, acids: const.iub, const: &const)

    print(">THREE Homo sapiens frequency")
    randomFasta(n: 5*n, acids: const.homosapiens, const: &const)
}

benchmark(n)

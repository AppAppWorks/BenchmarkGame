/*
 Based on Swift #3 for Fasta
 https://benchmarksgame-team.pages.debian.net/benchmarksgame/program/fasta-swift-3.html
 Adopted SIMD techniques from Rust #7
 Contributed by Richard Lau
*/

import Foundation
import Dispatch

extension SIMD where Scalar : FixedWidthInteger {
    mutating func cmplt(_ a: Self, _ b: Self) {
        withUnsafeBytes(of: a .< b) { ptr in
            self &-= ptr.load(as: Self.self)
        }
    }
}

struct WeightedRandom<T> {
    var cumprob: [UInt32]
    var elements: [T]
    
    init<F>(mapping: ContiguousArray<(prob: F, sym: T)>) where F : BinaryFloatingPoint {
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
        typealias S4x32 = SIMD4<Int32>
        
        let needle = S4x32(repeating: Int32(prob))

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

            let idx = count.wrappedSum()
            return elements.withUnsafeBufferPointer {
                $0[Int(idx)]
            }
        }
    }
}

extension WeightedRandom where T == UInt8 {
    // Consumer task
    func consumeRandom(n: Int, block: Int) {
        var bufPtr = cBufs[block]
        var lineCounter = 0
        let buf = bufs[block]

        for i in 0..<Swift.min(n, rndBufSize) {
            let e = buf[i]
            let c = genFromU32(prob: e)
            
            bufPtr.pointee = c
            lineCounter += 1
            bufPtr = bufPtr.successor()
            if lineCounter == linewidth {
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

let linewidth = 60
let bufferLines = 10240
let rndBufSize = (bufferLines * linewidth)
let writeBufSize = (bufferLines * (linewidth + 1))

let IM: UInt32 = 139968
let IA: UInt32 = 3877
let IC: UInt32 = 29573
var seed: UInt32 = 42

typealias AminoAcid = (prob: Double, sym: UInt8)

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

// Allocate some resources to buffer data and
// handle ownership by semaphores
let nBufs = 4   // need to be a power of two
var bufs = (0..<nBufs).map { _ in UnsafeMutablePointer<UInt32>.allocate(capacity: rndBufSize) }
var cBufs = (0..<nBufs).map { _ in UnsafeMutablePointer<UInt8>.allocate(capacity: writeBufSize) }
var pSemaphore = (0..<nBufs).map { _ in DispatchSemaphore(value: 1) }
var wSemaphore = (0..<nBufs).map { _ in DispatchSemaphore(value: 1) }
defer {
    for i in 0..<nBufs {
        bufs[i].deallocate()
        cBufs[i].deallocate()
    }
}

// Let's have some queues to produce data, consume it
// and to syncronize data ownership
let cQueue = DispatchQueue(label: "Consumer", attributes: .concurrent)
let pQueue = DispatchQueue(label: "Producer", attributes: [])
let wQueue = DispatchQueue(label: "Writer", attributes: [])
let group = DispatchGroup()

// Build a block in fasta format
func buildFastaBlockFromString(s: String) -> [UInt8] {
    // Build block of linewidth characters wide string
    var s = s
    return .init(unsafeUninitializedCapacity: s.count * (linewidth + 1)) { ptr, capacity in
        s.withUTF8 { s in
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

// random
func random() -> UInt32 {
    seed = (seed * IA + IC) % IM
    return seed
}

// Producer task
func genRandom(n: Int, block: Int) {
    let ptr = bufs[block]
    for i in 0..<min(n, rndBufSize) {
        ptr[i] = random()
    }
}

// Print random amino acid sequences
func randomFasta(n: Int, acids: ContiguousArray<AminoAcid>) {
    // Adjust probability to cumulative
    let cumAcid = WeightedRandom(mapping: acids)
    
    let junks = (n + rndBufSize - 1) / rndBufSize
    let remainder = n % rndBufSize
    var deferedWrite = [Int]()
    var writeBlock = 0
    group.enter()
    pQueue.async {

        for i in 0..<junks-1 {
            let block = i % bufs.count
            pSemaphore[block].wait()
            genRandom(n: rndBufSize, block: block)
            cQueue.async(group: group) {

                wSemaphore[block].wait()
                cumAcid.consumeRandom(n: rndBufSize, block: block)
                pSemaphore[block].signal()
                wQueue.async(group: group) {

                    if block != writeBlock {
                        deferedWrite.append(block)
                    } else {
                        print(String(cString: cBufs[block]), terminator: "")
                        writeBlock = (writeBlock + 1) & (nBufs - 1)
                        wSemaphore[block].signal()
                        if deferedWrite.count > 0 {
                            while deferedWrite.contains(writeBlock) {
                                let blk = writeBlock
                                print(String(cString: cBufs[blk]), terminator: "")
                                writeBlock = (writeBlock + 1) & (nBufs - 1)
                                deferedWrite.remove(at: deferedWrite.firstIndex(of: blk)!)
                                wSemaphore[blk].signal()
                            }
                        }
                    }
                }
            }
        }
        group.leave()
    }
    group.wait()
    genRandom(n: remainder, block: 0)
    cumAcid.consumeRandom(n: remainder, block: 0)

    let last = String(cString: cBufs[0])
    var stringRemainder = remainder+(remainder/linewidth)
    if stringRemainder % (linewidth+1) == 0 {
        stringRemainder -= 1
    }
    print(last[last.startIndex..<last.index(last.startIndex, offsetBy: stringRemainder)])
}

// Print alu string in fasta format
func repeatFasta(n: Int, alu: inout [UInt8]) {
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

// Read command line parameters
let n: Int
if CommandLine.arguments.count > 1 {
    n = Int(CommandLine.arguments[1]) ?? 1000
} else {
    n = 25000000
}

// Build block of linewidth characters wide string
var aluBlock = buildFastaBlockFromString(s: alu)

//print(">ONE Homo sapiens alu")
//repeatFasta(n: 2*n, alu: aluBlock)

print(">TWO IUB ambiguity codes")
randomFasta(n: 3*n, acids: iub)

print(">THREE Homo sapiens frequency")
randomFasta(n: 5*n, acids: homosapiens)

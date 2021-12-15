// The Computer Language Benchmarks Game
// http://benchmarksgame.alioth.debian.org/
//
// Swift adaptation of binary-trees Rust #5,
// Used DispatchQueue.concurrentPerform() to launch the
// worker threads, referencing Swift #3
//
// contributed by Richard Lau

import Dispatch
import Foundation

public extension BinaryInteger {
    @inlinable
    func exp(_ power: Self) -> Self {
        var result: Self = 1
        var base = self
        var power = power
        
        while power != 0 {
            if power % 2 == 1 {
                result *= base
            }
            power /= 2
            base *= base
        }
        
        return result
    }
}

// sort of like a custom allocator, derive the instance count from depth and allocate memory for the tree instances needed at once
// boost performance by eliminating almost all malloc and dealloc
// the backing storage is an array of offsets, similar to pointers to Tree in Rust #5
// this structure can hold up to 2^32 - 1 nodes
public struct Tree {
    @usableFromInline
    var storage: [(UInt32, UInt32)]
    @usableFromInline
    let offset: UInt32
    
    @usableFromInline
    static func tree(depth: UInt32, offset: inout Int, storage: UnsafeMutableBufferPointer<(UInt32, UInt32)>) -> UInt32 {
        guard depth > 0 else {
            return 0
        }
        
        let oldOffset = offset
        offset += 1
        
        storage[oldOffset] = (tree(depth: depth - 1, offset: &offset, storage: storage),
                              tree(depth: depth - 1, offset: &offset, storage: storage))
        
        return .init(oldOffset + 1)
    }
    
    @usableFromInline
    init(storage: [(UInt32, UInt32)], offset: UInt32) {
        self.storage = storage
        self.offset = offset
    }
    
    @usableFromInline
    func _itemCheck(_ offset: UInt32) -> UInt32 {
        let (left, right) = storage[Int(offset - 1)]
        return 1 + (left > 0 ? _itemCheck(left) : 1) + (right > 0 ? _itemCheck(right) : 1)
    }
}

public extension Tree {
    @inlinable
    init(_ depth: UInt32) {
        guard depth > 0 else {
            self.init(storage: [], offset: 0)
            return
        }

        var storage = [(UInt32, UInt32)](unsafeUninitializedCapacity: (1 - 2.exp(Int(depth))) / (1 - 2)) { buf, count in
            count = buf.count
        }
        var offset = 1

        storage.withUnsafeMutableBufferPointer {
            $0[0] = (Self.tree(depth: depth - 1, offset: &offset, storage: $0),
                     Self.tree(depth: depth - 1, offset: &offset, storage: $0))
        }

        self.init(storage: storage, offset: 1)
    }
    
    @inlinable
    var isEmpty: Bool {
        offset == 0
    }
    
    @inlinable
    var left: Tree? {
        guard !isEmpty else { return nil }
        let leftOffset = storage[Int(offset - 1)].0
        guard leftOffset > 0 else { return nil }
        return .init(storage: storage,
                     offset: leftOffset)
    }
    
    @inlinable
    var right: Tree? {
        guard !isEmpty else { return nil }
        let rightOffset = storage[Int(offset - 1)].0
        guard rightOffset > 0 else { return nil }
        return .init(storage: storage,
                     offset: rightOffset)
    }
    
    @inlinable
    func itemCheck() -> UInt32 {
        guard !isEmpty else { return 1 }
        return _itemCheck(offset)
    }
}

@inlinable
public func inner(depth: UInt32, iterations: UInt32) -> String {
    var chk: UInt32 = 0
    for _ in 0..<iterations {
        let tree = Tree(depth)
        chk += tree.itemCheck()
    }
    return "\(iterations)\t trees of depth \(depth)\t check: \(chk)"
}

let n: UInt32

if CommandLine.argc > 1 {
    n = UInt32(CommandLine.arguments[1]) ?? 10
} else {
    n = 10
}

@inlinable
public func benchmark(_ n: UInt32) {
    let minDepth: UInt32 = 4
    let maxDepth = (n > minDepth + 2) ? n : minDepth + 2
    var messages: [UInt32: String] = [:]
    let depth = maxDepth + 1

    let group = DispatchGroup()

    let workerQueue = DispatchQueue(label: "workerQueue", qos: .userInteractive, attributes: .concurrent)
    let messageQueue = DispatchQueue(label: "messageQueue", qos: .background)

    group.enter()
    workerQueue.async {
        let tree = Tree(depth)
        
        messageQueue.async {
            messages[0] = "stretch tree of depth \(depth)\t check: \(tree.itemCheck())"
            group.leave()
        }
    }

    group.enter()
    workerQueue.async {
        let longLivedTree = Tree(maxDepth)
        
        messageQueue.async {
            messages[.max] = "long lived tree of depth \(maxDepth)\t check: \(longLivedTree.itemCheck())"
            group.leave()
        }
    }

    let halfDepth = (minDepth / 2)
    let halfMaxDepth = (maxDepth / 2 + 1)
    let itt = Int(halfMaxDepth - halfDepth)

    DispatchQueue.concurrentPerform(iterations: itt, execute: { idx in
        let depth = (halfDepth + UInt32(idx)) * 2
        let iterations = UInt32(1 << (maxDepth - depth + minDepth))
        
        group.enter()
        workerQueue.async {
            let msg = inner(depth: depth, iterations: iterations)
            messageQueue.async {
                messages[depth] = msg
                group.leave()
            }
        }
    })

    // Wait for all the operations to finish
    group.wait()

    for msg in messages.sorted(by: { $0.0 < $1.0 }) {
        print(msg.value)
    }
}

benchmark(n)

//notes, command-line, and program output
//NOTES:
//64-bit Ubuntu quad core
//Swift version 5.5-dev (LLVM f9e846e117057c8, Swift a58e8c181f2e258)
//Target: x86_64-unknown-linux-gnu
//
//
//
//Tue, 15 Jun 2021 21:50:55 GMT
//
//MAKE:
///opt/src/swift-5.5-DEVELOPMENT-SNAPSHOT-2021-06-14/usr/bin/swiftc binarytrees.swift-3.swift -Ounchecked  -o binarytrees.swift-3.swift_run
//
//11.34s to complete and log all make actions
//
//COMMAND LINE:
//./binarytrees.swift-3.swift_run 21
//
//PROGRAM OUTPUT:
//stretch tree of depth 22     check: 8388607
//2097152     trees of depth 4     check: 65011712
//524288     trees of depth 6     check: 66584576
//131072     trees of depth 8     check: 66977792
//32768     trees of depth 10     check: 67076096
//8192     trees of depth 12     check: 67100672
//2048     trees of depth 14     check: 67106816
//512     trees of depth 16     check: 67108352
//128     trees of depth 18     check: 67108736
//32     trees of depth 20     check: 67108832
//long lived tree of depth 21     check: 4194303

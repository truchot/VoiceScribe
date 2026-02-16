import Foundation

/// Zero-allocation frame buffer for real-time audio processing.
///
/// Replaces the pattern:
/// ```swift
/// frameBuffer.append(contentsOf: samples)      // Copy into growing array
/// let frame = Array(frameBuffer.prefix(512))    // ALLOC + COPY
/// frameBuffer.removeFirst(512)                  // O(n) SHIFT
/// ```
///
/// With:
/// ```swift
/// frameBuffer.append(samples)                   // Copy into pre-allocated storage
/// frameBuffer.consumeFrame(512) { ptr in ... }  // Zero-copy pointer access
/// ```
///
/// Used by SileroVAD, SentimentAnalyzer, and AudioCaptureManager on their
/// respective processing queues (~31 frames/sec per stream).
struct AudioFrameBuffer {
    
    private var storage: [Float]
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private let capacity: Int
    
    /// Create a buffer with pre-allocated capacity.
    /// Capacity should be at least 2× the expected max buffered samples.
    init(capacity: Int = 32768) {  // 32K = ~2s at 16kHz
        self.capacity = capacity
        self.storage = [Float](repeating: 0, count: capacity)
    }
    
    /// Number of samples available to read.
    var count: Int { writeIndex - readIndex }
    
    /// True if no readable samples.
    var isEmpty: Bool { readIndex >= writeIndex }
    
    /// Append samples into the buffer. O(n) copy but no allocation
    /// unless the buffer needs to compact or grow.
    mutating func append(_ samples: [Float]) {
        let needed = writeIndex + samples.count
        
        if needed > capacity {
            // Compact: shift readable data to front
            let readable = count
            if readable > 0 {
                storage.withUnsafeMutableBufferPointer { buf in
                    buf.baseAddress!.advanced(by: 0)
                        .update(from: buf.baseAddress!.advanced(by: readIndex), count: readable)
                }
            }
            readIndex = 0
            writeIndex = readable
            
            // If still not enough after compaction, grow
            if writeIndex + samples.count > capacity {
                storage.append(contentsOf: [Float](repeating: 0, count: writeIndex + samples.count - capacity + 4096))
            }
        }
        
        // Copy samples in
        samples.withUnsafeBufferPointer { src in
            storage.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.advanced(by: writeIndex)
                    .update(from: src.baseAddress!, count: samples.count)
            }
        }
        writeIndex += samples.count
    }
    
    /// Append from contiguous collection (for single sample append patterns).
    mutating func append(contentsOf samples: [Float]) {
        append(samples)
    }
    
    /// Read a frame of exactly `count` samples WITHOUT copying.
    /// Returns an UnsafeBufferPointer valid only during the closure.
    /// Advances the read index by `advance` samples (often == count,
    /// but can be less for overlapping reads like SentimentAnalyzer's hopSize).
    @inline(__always)
    mutating func consumeFrame(count frameSize: Int, advance: Int? = nil, body: (UnsafeBufferPointer<Float>) -> Void) {
        precondition(self.count >= frameSize, "Not enough samples: have \(self.count), need \(frameSize)")
        storage.withUnsafeBufferPointer { buf in
            let ptr = UnsafeBufferPointer(start: buf.baseAddress! + readIndex, count: frameSize)
            body(ptr)
        }
        readIndex += advance ?? frameSize
    }
    
    /// Consume a frame and return a copy (for cases where data must outlive the buffer,
    /// e.g. speechBuffer accumulation). Still faster than prefix+removeFirst
    /// because it avoids the O(n) shift.
    @inline(__always)
    mutating func consumeFrameCopy(count frameSize: Int, advance: Int? = nil) -> [Float] {
        precondition(self.count >= frameSize)
        let result = Array(storage[readIndex..<(readIndex + frameSize)])
        readIndex += advance ?? frameSize
        return result
    }
    
    /// Peek at first `count` samples without consuming.
    func peek(count: Int) -> UnsafeBufferPointer<Float>? {
        guard self.count >= count else { return nil }
        return storage.withUnsafeBufferPointer { buf in
            UnsafeBufferPointer(start: buf.baseAddress! + readIndex, count: count)
        }
    }
    
    /// Remove all data without deallocating.
    mutating func removeAll() {
        readIndex = 0
        writeIndex = 0
    }
}

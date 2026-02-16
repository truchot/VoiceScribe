import Foundation

/// Generic ring buffer for fixed-size sliding windows.
/// Used by VAD implementations for audio sample buffering.
struct RingBuffer<T> {
    private var buffer: [T] = []
    private(set) var capacity: Int
    private var writeIndex: Int = 0
    private var isFull: Bool = false
    
    var count: Int { isFull ? capacity : buffer.count }
    
    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.buffer = []
        self.buffer.reserveCapacity(self.capacity)
    }
    
    /// Append an element (alias: `write`).
    mutating func append(_ element: T) {
        if buffer.count < capacity {
            buffer.append(element)
        } else {
            buffer[writeIndex] = element
            isFull = true
        }
        writeIndex = (writeIndex + 1) % capacity
    }
    
    /// Alias for `append` — used by SileroONNXVAD.
    mutating func write(_ element: T) { append(element) }
    
    /// Return elements in insertion order.
    func toArray() -> [T] {
        if !isFull || buffer.count < capacity {
            return buffer
        }
        return Array(buffer[writeIndex...]) + Array(buffer[..<writeIndex])
    }
    
    mutating func clear() {
        buffer.removeAll()
        writeIndex = 0
        isFull = false
    }
}

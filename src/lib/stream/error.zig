const std = @import("std");

/// Stream-specific error conditions
pub const StreamError = error{
    /// Stream has reached end of data
    EndOfStream,

    /// Buffer is full and cannot accept more data
    BufferFull,

    /// Buffer is empty and cannot provide data
    BufferEmpty,

    /// Operation not supported by this stream type
    NotSupported,

    /// Stream is closed and cannot be used
    StreamClosed,

    /// Invalid position or offset
    InvalidPosition,

    /// I/O error occurred
    IoError,

    /// Memory allocation failed
    OutOfMemory,

    /// Data corruption detected
    CorruptedData,

    /// Operation would block (for async streams)
    WouldBlock,

    /// Timeout occurred
    Timeout,

    /// Invalid state for operation
    InvalidState,

    /// Parse error in stream data
    ParseError,

    /// Backpressure limit exceeded
    BackpressureExceeded,
};


Zig Version 0.14.1

Table of Contents

    Introduction
    Zig Standard Library
    Hello World
    Comments
        Doc Comments
        Top-Level Doc Comments
    Values
        Primitive Types
        Primitive Values
        String Literals and Unicode Code Point Literals
            Escape Sequences
            Multiline String Literals
        Assignment
            undefined
            Destructuring
    Zig Test
        Test Declarations
            Doctests
        Test Failure
        Skip Tests
        Report Memory Leaks
        Detecting Test Build
        Test Output and Logging
        The Testing Namespace
        Test Tool Documentation
    Variables
        Identifiers
        Container Level Variables
        Static Local Variables
        Thread Local Variables
        Local Variables
    Integers
        Integer Literals
        Runtime Integer Values
    Floats
        Float Literals
        Floating Point Operations
    Operators
        Table of Operators
        Precedence
    Arrays
        Multidimensional Arrays
        Sentinel-Terminated Arrays
        Destructuring Arrays
    Vectors
        Destructuring Vectors
    Pointers
        volatile
        Alignment
        allowzero
        Sentinel-Terminated Pointers
    Slices
        Sentinel-Terminated Slices
    struct
        Default Field Values
            Faulty Default Field Values
        extern struct
        packed struct
        Struct Naming
        Anonymous Struct Literals
        Tuples
            Destructuring Tuples
    enum
        extern enum
        Enum Literals
        Non-exhaustive enum
    union
        Tagged union
        extern union
        packed union
        Anonymous Union Literals
    opaque
    Blocks
        Shadowing
        Empty Blocks
    switch
        Exhaustive Switching
        Switching with Enum Literals
        Labeled switch
        Inline Switch Prongs
    while
        Labeled while
        while with Optionals
        while with Error Unions
        inline while
    for
        Labeled for
        inline for
    if
        if with Optionals
    defer
    unreachable
        Basics
        At Compile-Time
    noreturn
    Functions
        Pass-by-value Parameters
        Function Parameter Type Inference
        inline fn
        Function Reflection
    Errors
        Error Set Type
            The Global Error Set
        Error Union Type
            catch
            try
            errdefer
            Merging Error Sets
            Inferred Error Sets
        Error Return Traces
            Implementation Details
    Optionals
        Optional Type
        null
        Optional Pointers
    Casting
        Type Coercion
            Type Coercion: Stricter Qualification
            Type Coercion: Integer and Float Widening
            Type Coercion: Float to Int
            Type Coercion: Slices, Arrays and Pointers
            Type Coercion: Optionals
            Type Coercion: Error Unions
            Type Coercion: Compile-Time Known Numbers
            Type Coercion: Unions and Enums
            Type Coercion: undefined
            Type Coercion: Tuples to Arrays
        Explicit Casts
        Peer Type Resolution
    Zero Bit Types
        void
    Result Location Semantics
        Result Types
        Result Locations
    usingnamespace
    comptime
        Introducing the Compile-Time Concept
            Compile-Time Parameters
            Compile-Time Variables
            Compile-Time Expressions
        Generic Data Structures
        Case Study: print in Zig
    Assembly
        Output Constraints
        Input Constraints
        Clobbers
        Global Assembly
    Atomics
    Async Functions
    Builtin Functions
        @addrSpaceCast
        @addWithOverflow
        @alignCast
        @alignOf
        @as
        @atomicLoad
        @atomicRmw
        @atomicStore
        @bitCast
        @bitOffsetOf
        @bitSizeOf
        @branchHint
        @breakpoint
        @mulAdd
        @byteSwap
        @bitReverse
        @offsetOf
        @call
        @cDefine
        @cImport
        @cInclude
        @clz
        @cmpxchgStrong
        @cmpxchgWeak
        @compileError
        @compileLog
        @constCast
        @ctz
        @cUndef
        @cVaArg
        @cVaCopy
        @cVaEnd
        @cVaStart
        @divExact
        @divFloor
        @divTrunc
        @embedFile
        @enumFromInt
        @errorFromInt
        @errorName
        @errorReturnTrace
        @errorCast
        @export
        @extern
        @field
        @fieldParentPtr
        @FieldType
        @floatCast
        @floatFromInt
        @frameAddress
        @hasDecl
        @hasField
        @import
        @inComptime
        @intCast
        @intFromBool
        @intFromEnum
        @intFromError
        @intFromFloat
        @intFromPtr
        @max
        @memcpy
        @memset
        @min
        @wasmMemorySize
        @wasmMemoryGrow
        @mod
        @mulWithOverflow
        @panic
        @popCount
        @prefetch
        @ptrCast
        @ptrFromInt
        @rem
        @returnAddress
        @select
        @setEvalBranchQuota
        @setFloatMode
        @setRuntimeSafety
        @shlExact
        @shlWithOverflow
        @shrExact
        @shuffle
        @sizeOf
        @splat
        @reduce
        @src
        @sqrt
        @sin
        @cos
        @tan
        @exp
        @exp2
        @log
        @log2
        @log10
        @abs
        @floor
        @ceil
        @trunc
        @round
        @subWithOverflow
        @tagName
        @This
        @trap
        @truncate
        @Type
        @typeInfo
        @typeName
        @TypeOf
        @unionInit
        @Vector
        @volatileCast
        @workGroupId
        @workGroupSize
        @workItemId
    Build Mode
        Debug
        ReleaseFast
        ReleaseSafe
        ReleaseSmall
    Single Threaded Builds
    Illegal Behavior
        Reaching Unreachable Code
        Index out of Bounds
        Cast Negative Number to Unsigned Integer
        Cast Truncates Data
        Integer Overflow
            Default Operations
            Standard Library Math Functions
            Builtin Overflow Functions
            Wrapping Operations
        Exact Left Shift Overflow
        Exact Right Shift Overflow
        Division by Zero
        Remainder Division by Zero
        Exact Division Remainder
        Attempt to Unwrap Null
        Attempt to Unwrap Error
        Invalid Error Code
        Invalid Enum Cast
        Invalid Error Set Cast
        Incorrect Pointer Alignment
        Wrong Union Field Access
        Out of Bounds Float to Integer Cast
        Pointer Cast Invalid Null
    Memory
        Choosing an Allocator
        Where are the bytes?
        Implementing an Allocator
        Heap Allocation Failure
        Recursion
        Lifetime and Ownership
    Compile Variables
    Compilation Model
        Source File Structs
        File and Declaration Discovery
        Special Root Declarations
            Entry Point
            Standard Library Options
            Panic Handler
    Zig Build System
    C
        C Type Primitives
        Import from C Header File
        C Translation CLI
            Command line flags
            Using -target and -cflags
            @cImport vs translate-c
        C Translation Caching
        Translation failures
        C Macros
        C Pointers
        C Variadic Functions
        Exporting a C Library
        Mixing Object Files
    WebAssembly
        Freestanding
        WASI
    Targets
    Style Guide
        Avoid Redundancy in Names
        Avoid Redundant Names in Fully-Qualified Namespaces
        Whitespace
        Names
        Examples
        Doc Comment Guidance
    Source Encoding
    Keyword Reference
    Appendix
        Containers
        Grammar
        Zen


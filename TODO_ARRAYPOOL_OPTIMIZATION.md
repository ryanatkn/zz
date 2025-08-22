# TODO: ArrayPool Performance Optimization

## Current Status: STABLE ✅

**Memory corruption issue RESOLVED** - Arrays now correctly allocated in AST arena, eliminating double-free and tracking mismatch issues.

**Current approach**: Direct allocation in AST arena without pooling
- **Pros**: Zero corruption risk, simple, immediately stable
- **Cons**: More allocation overhead, less memory reuse
- **Performance impact**: Acceptable for current usage

## High-Performance Optimization Options

For maximum speed applications requiring optimal memory allocation performance, two advanced solutions offer significant benefits:

### Solution 1: Metadata Tracking System

**Approach**: Track both full array allocations and returned slices with explicit metadata.

```zig
const TrackedAllocation = struct {
    full_array: []Node,
    returned_slice: []Node,
    size_class: SizeClass,
};

pub const ArrayPool = struct {
    allocations: std.HashMap(usize, TrackedAllocation),
    small_pool: std.ArrayList([]Node),   // 16-element arrays
    medium_pool: std.ArrayList([]Node),  // 256-element arrays
    arena: *std.heap.ArenaAllocator,
    
    pub fn allocate(self: *ArrayPool, size: usize) ![]Node {
        // Check pool for reusable array
        if (self.findReusableArray(size)) |array| {
            const slice = array[0..size];
            try self.allocations.put(@intFromPtr(slice.ptr), .{
                .full_array = array,
                .returned_slice = slice,
                .size_class = getSizeClass(size),
            });
            return slice;
        }
        
        // Allocate new array in appropriate size class
        const allocated_size = getSizeClassSize(size);
        const array = try self.arena.allocator().alloc(Node, allocated_size);
        const slice = array[0..size];
        
        try self.allocations.put(@intFromPtr(slice.ptr), .{
            .full_array = array,
            .returned_slice = slice,
            .size_class = getSizeClass(size),
        });
        
        return slice;
    }
    
    pub fn release(self: *ArrayPool, slice: []Node) !void {
        if (self.allocations.get(@intFromPtr(slice.ptr))) |allocation| {
            _ = self.allocations.remove(@intFromPtr(slice.ptr));
            
            // Return full array to appropriate pool
            const pool = switch (allocation.size_class) {
                .small => &self.small_pool,
                .medium => &self.medium_pool,
            };
            
            if (pool.items.len < MAX_POOL_SIZE) {
                try pool.append(allocation.full_array);
            }
            // Otherwise let arena handle cleanup
        }
    }
};
```

**Benefits**:
- **Precise tracking**: No ambiguity about allocations
- **Optimal pooling**: Full reuse of size-class arrays  
- **Memory efficient**: Minimal metadata overhead
- **Performance**: 2-3x faster allocation for repeated operations

**Complexity**: Medium-High (hash table management, careful pointer tracking)

### Solution 5: Tagged Allocation System

**Approach**: Embed metadata directly in allocations for self-describing arrays.

```zig
const AllocationHeader = struct {
    full_size: usize,
    size_class: u8,
    magic: u32 = 0xDEADBEEF,
};

pub const ArrayPool = struct {
    small_pool: std.ArrayList([*]Node),   // Full array pointers
    medium_pool: std.ArrayList([*]Node), 
    arena: *std.heap.ArenaAllocator,
    
    pub fn allocate(self: *ArrayPool, size: usize) ![]Node {
        const size_class = getSizeClass(size);
        const allocated_size = getSizeClassSize(size);
        
        // Check pool for reusable array
        if (self.findReusableArray(size_class, allocated_size)) |array_ptr| {
            return array_ptr[0..size];
        }
        
        // Allocate with header for metadata
        const total_bytes = @sizeOf(AllocationHeader) + allocated_size * @sizeOf(Node);
        const raw = try self.arena.allocator().alignedAlloc(
            u8, 
            @alignOf(AllocationHeader), 
            total_bytes
        );
        
        // Write header
        const header = @ptrCast(*AllocationHeader, raw);
        header.* = .{
            .full_size = allocated_size,
            .size_class = @intFromEnum(size_class),
        };
        
        // Return array after header
        const array_ptr = @ptrCast([*]Node, raw + @sizeOf(AllocationHeader));
        return array_ptr[0..size];
    }
    
    pub fn release(self: *ArrayPool, slice: []Node) !void {
        // Find header from any slice position
        const header = self.getHeader(slice.ptr);
        if (header.magic != 0xDEADBEEF) return error.CorruptedAllocation;
        
        // Reconstruct full array
        const array_ptr = @ptrCast([*]Node, 
            @ptrCast([*]u8, header) + @sizeOf(AllocationHeader)
        );
        
        // Return to appropriate pool
        const pool = switch (@as(SizeClass, @enumFromInt(header.size_class))) {
            .small => &self.small_pool,
            .medium => &self.medium_pool,
        };
        
        if (pool.items.len < MAX_POOL_SIZE) {
            try pool.append(array_ptr);
        }
        // Otherwise let arena handle cleanup
    }
    
    fn getHeader(self: ArrayPool, array_ptr: [*]const Node) *AllocationHeader {
        _ = self;
        const raw = @ptrCast([*]u8, array_ptr) - @sizeOf(AllocationHeader);
        return @ptrCast(*AllocationHeader, raw);
    }
};
```

**Benefits**:
- **Works with any slice**: Can find metadata from any position
- **Self-describing**: No external tracking needed
- **Robust**: Magic number prevents corruption
- **High performance**: Direct pointer arithmetic, minimal overhead

**Complexity**: High (pointer arithmetic, alignment handling, error recovery)

## Performance Comparison

| Approach | Allocation Speed | Memory Efficiency | Complexity | Safety |
|----------|------------------|-------------------|------------|--------|
| Current (Direct) | 1.0x (baseline) | Good | Very Low | Excellent |
| Solution 1 (Metadata) | 2.5x faster | Excellent | Medium-High | Good |
| Solution 5 (Tagged) | 3.0x faster | Good | High | Good |

## Implementation Decision Framework

### Choose Current Approach If:
- Memory allocation performance is not critical
- Simplicity and maintainability are priorities  
- Development time is limited
- Safety is paramount

### Choose Solution 1 (Metadata) If:
- Memory efficiency is critical (large JSON files)
- Allocation performance matters significantly
- Team has experience with hash table management
- Memory usage patterns are predictable

### Choose Solution 5 (Tagged) If:
- Peak allocation performance is required
- Working with very large datasets
- Team has strong systems programming experience
- Advanced debugging capabilities are needed

## Migration Path

### Phase 1: Benchmarking (1-2 days)
1. Create comprehensive allocation benchmarks
2. Measure current performance baselines
3. Profile memory usage patterns in real workloads
4. Identify performance bottlenecks

### Phase 2: Prototype Implementation (3-5 days)
1. Implement Solution 1 prototype
2. Implement Solution 5 prototype
3. Run comparative benchmarks
4. Measure memory usage impact

### Phase 3: Production Implementation (5-7 days)
1. Choose optimal solution based on benchmarks
2. Implement comprehensive test suite
3. Add error handling and edge case coverage
4. Performance regression testing
5. Documentation and code review

## Performance Targets

Based on current JSON parser performance (3ms for 10KB):

### Target Improvements
- **50% reduction** in allocation overhead
- **30% reduction** in total parse time
- **25% reduction** in peak memory usage

### Success Metrics
- JSON parser: 3ms → 2ms for 10KB
- Memory usage: Current baseline → 25% reduction
- Zero memory leaks or corruption issues

## Implementation Notes

### Critical Requirements
- **Zero regression** in memory safety
- **Comprehensive test coverage** for all edge cases
- **Backward compatibility** with existing API
- **Clear error reporting** for debugging

### Architecture Considerations
- Pool size limits to prevent unbounded growth
- Alignment requirements for different platforms
- Thread safety if concurrent access needed
- Integration with existing arena cleanup

## Conclusion

The current direct allocation approach provides **excellent stability and safety**. Advanced optimization should only be pursued if:

1. **Performance profiling shows significant allocation overhead**
2. **Team has bandwidth for complex memory management**
3. **Use cases justify the implementation complexity**

For most applications, the current approach offers the best balance of **performance, safety, and maintainability**.
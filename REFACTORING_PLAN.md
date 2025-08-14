# zz Codebase Refactoring Plan

**Status**: Active Development  
**Start Date**: 2025-08-14  
**Est. Completion**: TBD  
**Goal**: Improve code quality, reduce duplication, enhance maintainability

## Overview

This document outlines a comprehensive refactoring plan for the `zz` CLI utilities codebase, focusing on the `src/lib` shared infrastructure. Through analysis of the current codebase, we've identified key areas for improvement that will result in cleaner code, better performance, and improved developer experience.

**Alignment with Project Roadmap**: This refactoring work directly enables several high-priority items from SUGGESTED_NEXT.md:
- **Real Tree-sitter Integration**: AST infrastructure improvements support semantic analysis
- **Formatter Memory Leak Fix**: Ownership patterns prevent double-free issues  
- **Performance Optimization**: String management and collection helpers target hot paths
- **Incremental Processing Enhancement**: Dependency tracking and file state improvements

## Current Issues Identified

### Code Quality Issues
- **Ownership confusion**: Config ownership patterns unclear (import_resolver example)
- **Verbose APIs**: `collection_helpers.CollectionHelpers.ManagedArrayList` used 54 times
- **Manual memory management**: 187 manual `defer deinit` calls
- **Inconsistent patterns**: Various initialization and cleanup patterns
- **String duplication**: Excessive `allocator.dupe(u8, ...)` calls

### Technical Debt
- **TODO items**: Scattered across codebase without tracking
- **Complex result types**: Many structures requiring manual deinit
- **Duplicate walker patterns**: AST traversal code repeated
- **Test boilerplate**: Duplicate setup/teardown code

## Refactoring Plan

### Phase 1: High Priority (Immediate Impact)

#### 1.1 Create Ownership Helper Module (`src/lib/ownership.zig`)
**Problem**: Config ownership confusion causing double-free bugs  
**Timeline**: 1-2 days  
**Impact**: Critical bug fixes, clearer ownership semantics

**Components**:
```zig
pub const Owned(T) = struct {
    value: T,
    allocator: std.mem.Allocator,
    
    pub fn take(self: *Owned(T)) T {
        // Transfer ownership, invalidate self
    }
};

pub const Borrowed(T) = struct {
    value: *const T,
    // No cleanup responsibility
};

pub fn transfer(comptime T: type, value: T, allocator: std.mem.Allocator) Owned(T);
pub fn borrow(comptime T: type, value: *const T) Borrowed(T);
```

**Benefits**:
- Eliminates ownership confusion
- Prevents double-free errors
- Makes ownership transfer explicit

#### 1.2 Enhance Collection Helpers (`src/lib/collection_helpers.zig`)
**Problem**: Verbose API and missing common patterns  
**Timeline**: 2-3 days  
**Impact**: Code reduction, improved API ergonomics

**Improvements**:
```zig
// Simplified aliases
pub const ManagedList = ManagedArrayList;
pub const StringSet = ManagedHashMap([]const u8, void);

// New managed hash map
pub fn ManagedHashMap(comptime K: type, comptime V: type) type {
    return struct {
        map: std.HashMap(K, V, ...),
        allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator) Self;
        pub fn deinit(self: *Self) void; // Automatic cleanup
    };
}

// Scope-based collections
pub fn withTempList(comptime T: type, allocator: std.mem.Allocator, 
                   comptime func: fn(*ManagedList(T)) anyerror!void) !void;
```

**Benefits**:
- 50% reduction in collection boilerplate
- Automatic memory management
- More intuitive API

#### 1.3 Create String Management Module (`src/lib/string_manager.zig`)
**Problem**: Excessive string duplication, memory inefficiency  
**Timeline**: 2-3 days  
**Impact**: 30-40% reduction in string allocations

**Components**:
```zig
pub const StringManager = struct {
    pool: string_pool.StringPool,
    allocator: std.mem.Allocator,
    
    pub fn intern(self: *StringManager, str: []const u8) !StringRef;
    pub fn tempString(self: *StringManager, str: []const u8) !TempStringRef;
};

pub const StringRef = struct {
    ptr: [*]const u8,
    len: usize,
    // Managed by StringManager, no manual cleanup
};
```

**Benefits**:
- Automatic string deduplication
- Reduced memory usage
- Cleaner string handling APIs

### Phase 2: Medium Priority (Code Quality)

#### 2.1 Create Result Types Module (`src/lib/result_types.zig`)
**Problem**: Complex result structures requiring manual cleanup  
**Timeline**: 3-4 days  
**Impact**: Simplified error handling, automatic cleanup

**Components**:
```zig
pub fn Result(comptime T: type) type {
    return struct {
        value: T,
        allocator: std.mem.Allocator,
        
        pub fn deinit(self: *Result(T)) void {
            // Automatic cleanup based on T's interface
        }
    };
}

pub fn OwnedResult(comptime T: type) type; // For ownership transfer
pub fn MultiResult(comptime T: type) type; // For batch operations
```

#### 2.2 Standardize Init/Deinit Patterns
**Problem**: Inconsistent initialization across modules  
**Timeline**: 2-3 days  
**Impact**: Consistent developer experience, reduced cognitive load

**Patterns**:
```zig
pub fn InitOptions(comptime T: type) type; // Consistent option structs
pub fn withDefault(comptime T: type, allocator: std.mem.Allocator) !T;
pub fn AutoCleanup(comptime T: type) type; // RAII wrapper
```

#### 2.3 Refactor Import/Export Infrastructure
**Problem**: Complex, inconsistent import handling across modules  
**Timeline**: 4-5 days  
**Impact**: Unified import handling, reduced complexity

**Changes**:
- Merge `ImportInfo` types across modules
- Create shared `ImportMetadata` structure
- Use string interning for import paths
- Unified `ImportContext` parameter object

### Phase 3: Low Priority (Nice to Have)

#### 3.1 Create Diagnostics Module (`src/lib/diagnostics.zig`)
**Problem**: Scattered TODOs, no issue tracking  
**Timeline**: 2-3 days  
**Impact**: Better project visibility, technical debt tracking

#### 3.2 Memory Management Improvements
**Problem**: Manual defer patterns throughout codebase  
**Timeline**: 3-4 days  
**Impact**: More robust memory management

#### 3.3 Test Infrastructure Improvements
**Problem**: Duplicate test setup code  
**Timeline**: 2-3 days  
**Impact**: Easier testing, less boilerplate

## Implementation Strategy

### Development Approach
1. **Incremental**: Implement one module at a time
2. **Backward compatible**: Maintain existing APIs during transition
3. **Test-driven**: Comprehensive tests for each new module
4. **Performance focused**: Benchmark before/after changes

### Migration Process
1. **Create new module** with improved API
2. **Update one consumer** to use new API
3. **Run tests** to ensure no regressions
4. **Gradually migrate** remaining consumers
5. **Remove old code** when no longer used

### Success Metrics
- **Code reduction**: Target 500-1000 lines reduction
- **Test coverage**: Maintain >95% coverage
- **Performance**: No performance regressions
- **Memory usage**: 30-40% reduction in allocations
- **Bug prevention**: Zero ownership-related bugs

## Detailed Module Specifications

### Ownership Module Design
```zig
// src/lib/ownership.zig

/// Explicit ownership wrapper for values that need cleanup
pub fn Owned(comptime T: type) type {
    return struct {
        const Self = @This();
        
        value: T,
        allocator: std.mem.Allocator,
        is_valid: bool = true,
        
        pub fn init(allocator: std.mem.Allocator, value: T) Self {
            return Self{
                .value = value,
                .allocator = allocator,
            };
        }
        
        pub fn take(self: *Self) T {
            std.debug.assert(self.is_valid);
            self.is_valid = false;
            return self.value;
        }
        
        pub fn deinit(self: *Self) void {
            if (self.is_valid and @hasDecl(T, "deinit")) {
                self.value.deinit(self.allocator);
            }
            self.is_valid = false;
        }
    };
}

/// Borrowed reference - no ownership, no cleanup responsibility
pub fn Borrowed(comptime T: type) type {
    return struct {
        value: *const T,
        
        pub fn get(self: @This()) *const T {
            return self.value;
        }
    };
}
```

### String Manager Design
```zig
// src/lib/string_manager.zig

pub const StringManager = struct {
    pool: StringPool,
    temp_arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !StringManager {
        return StringManager{
            .pool = StringPool.init(allocator),
            .temp_arena = std.heap.ArenaAllocator.init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *StringManager) void {
        self.pool.deinit();
        self.temp_arena.deinit();
    }
    
    /// Intern string for long-term storage with deduplication
    pub fn intern(self: *StringManager, str: []const u8) !StringRef {
        const interned = try self.pool.intern(str);
        return StringRef{ .ptr = interned.ptr, .len = interned.len };
    }
    
    /// Create temporary string reference, freed on next reset
    pub fn tempString(self: *StringManager, str: []const u8) !TempStringRef {
        const temp = try self.temp_arena.allocator().dupe(u8, str);
        return TempStringRef{ .ptr = temp.ptr, .len = temp.len };
    }
    
    /// Reset temporary string arena
    pub fn resetTemp(self: *StringManager) void {
        self.temp_arena.deinit();
        self.temp_arena = std.heap.ArenaAllocator.init(self.allocator);
    }
};
```

## Current Status

### Completed Work
- ✅ Analysis phase complete
- ✅ Refactoring plan documented
- ✅ Priority levels assigned
- ✅ Module specifications outlined

### In Progress
- 🔄 Creating ownership helper module
- 🔄 Enhancing collection helpers

### Upcoming
- ⏳ String management module
- ⏳ Result types module
- ⏳ Import/export infrastructure refactoring

## Risk Mitigation

### Technical Risks
- **Breaking changes**: Maintain backward compatibility during migration
- **Performance regressions**: Comprehensive benchmarking
- **Memory leaks**: Extensive testing with valgrind/sanitizers

### Process Risks
- **Scope creep**: Stick to defined phases
- **Integration issues**: Incremental testing approach
- **Timeline slippage**: Regular progress reviews

## Roadmap Alignment & Enablement

### How Refactoring Enables Roadmap Priorities

#### 1. **Real Tree-sitter Integration** (Roadmap Priority #1)
- **AST Infrastructure**: Our Result types and AST walker consolidation create foundation
- **Memory Management**: Ownership patterns prevent issues with complex AST node lifecycles
- **Performance**: String interning reduces AST node memory overhead

#### 2. **Formatter Memory Leak Fix** (Roadmap Priority #2)  
- **Direct Solution**: Ownership helper module fixes glob expansion double-free
- **Prevention**: RAII patterns prevent future memory management bugs
- **Testing**: Enhanced test infrastructure catches memory leaks early

#### 3. **Performance Optimization** (Roadmap Targets)
- **String Management**: Target 30-40% allocation reduction (supports 21μs → 15μs extraction target)
- **Collection Helpers**: Reduce overhead in hot paths (supports 11μs → 8μs memory pool target)
- **Result Types**: Eliminate redundant cleanup calls in parser paths

#### 4. **Incremental Processing Enhancement** (Roadmap Priority #11)
- **Dependency Tracking**: Import/export infrastructure improvements enable file watching
- **AST Cache Integration**: Result types support proper cache invalidation
- **File State Management**: Enhanced FileState structure supports change detection

## Success Criteria

### Code Quality Metrics
- [ ] Reduce boilerplate by 500+ lines
- [ ] Eliminate all ownership-related bugs (enables tree-sitter integration)
- [ ] Achieve consistent API patterns across modules
- [ ] Reduce memory allocations by 30-40%

### Performance Alignment (From SUGGESTED_NEXT.md Targets)
- [ ] Memory pools: 11μs → 8μs (via collection helper optimization)
- [ ] Code extraction: 21μs → 15μs (via string management and Result types)
- [ ] JSON formatting: 50μs → 30μs for 1KB files (via ownership pattern efficiency)
- [ ] CSS formatting: 40μs → 25μs for 1KB files (via reduced allocations)
- [ ] Zero performance regressions on existing benchmarks

### Developer Experience
- [ ] Clearer ownership semantics (foundation for tree-sitter work)
- [ ] Simplified collection management
- [ ] Reduced cognitive load for new contributors
- [ ] Better error messages and debugging
- [ ] RAII patterns reduce memory leak opportunities

### Infrastructure Readiness
- [ ] Foundation prepared for async I/O (Roadmap Priority #6)
- [ ] AST infrastructure ready for real tree-sitter integration
- [ ] Memory management patterns support language grammar expansion
- [ ] Collection patterns support incremental processing features

## Future Considerations

### Post-Refactoring Opportunities
1. **Advanced caching**: More sophisticated AST caching
2. **Parallelization**: Better use of worker pools
3. **Memory mapping**: For large file processing
4. **Custom allocators**: Specialized allocators for different workloads

### API Evolution
1. **Fluent interfaces**: Builder patterns for complex operations
2. **Async support**: Preparation for async file I/O
3. **Plugin system**: Extensible parser and formatter system
4. **Configuration**: More sophisticated configuration management

## Immediate Next Steps (Sprint Alignment)

Based on the roadmap's "Next Sprint Focus" recommendations, our refactoring work should proceed in this order:

### Week 1-2: Foundation (High Impact, Quick Wins)
1. **✅ Create ownership helper module** - Fixes formatter memory leak (Roadmap Priority #1)
2. **✅ Enhance collection helpers** - Supports performance targets
3. **✅ String management module** - Enables allocation reduction goals

### Week 3-4: Core Infrastructure  
4. **Create result types module** - Foundation for tree-sitter integration
5. **Refactor import/export infrastructure** - Supports incremental processing
6. **Standardize init/deinit patterns** - Prevents future memory issues

### Week 5-6: Integration & Testing
7. **Enhanced test infrastructure** - Validate current state (Roadmap Priority #4)
8. **Performance profiling integration** - Measure optimization effectiveness
9. **Documentation updates** - Reflect new patterns and APIs

### Post-Refactoring Roadmap Enablement
- **Real tree-sitter integration** now has solid memory management foundation
- **Performance optimization** work can leverage new infrastructure  
- **Incremental processing** can build on improved dependency tracking
- **Language grammar expansion** can use standardized patterns

## Implementation Priority Justification

**Why ownership helpers first?**
- Directly fixes the formatter memory leak (immediate user value)
- Prevents double-free bugs blocking tree-sitter work
- Quick win that builds momentum

**Why collection helpers second?**
- High usage pattern (54 occurrences) means big impact
- Performance hot path optimization
- Foundation for other modules

**Why string management third?**
- Biggest performance gain potential (30-40% allocation reduction)
- Critical for AST node efficiency in tree-sitter work
- Enables advanced caching strategies

---

**Immediate Action**: Begin implementation with ownership helper module, focusing on fixing the import_resolver config ownership issue that's blocking tree-sitter integration work.
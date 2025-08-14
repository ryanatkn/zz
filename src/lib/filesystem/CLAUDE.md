# Filesystem Module - Abstraction Layer

Vtable-based filesystem abstraction enabling zero-cost testing without I/O.

## Architecture

**Vtable Polymorphism:** Uses `*anyopaque` pointers + function pointer tables for static dispatch.

## Core Interfaces

```zig
FilesystemInterface {
    ptr: *anyopaque,
    vtable: *const VTable,
    // Methods: openDir, statFile, cwd, pathJoin, pathBasename, pathExtension
}

DirHandle {
    ptr: *anyopaque,
    vtable: *const DirVTable,
    // Methods: iterate, openDir, close, statFile, readFileAlloc, openFile
}

FileHandle {
    ptr: *anyopaque,
    vtable: *const FileVTable,
    // Methods: close, reader, readAll
}

DirIterator {
    ptr: *anyopaque,
    vtable: *const IteratorVTable,
    // Methods: next
}
```

## Mock Implementation

**Data Structures:**
- `StringHashMap(FileEntry)` - Path-keyed storage
- `FileEntry` - Contains `kind`, `size`, `content`
- Hierarchical simulation via path prefixes

**Path Normalization:**
- Automatically strips leading `./` from paths for consistent lookups
- Handles both `"src"` and `"./src"` as the same directory
- Ensures compatibility with different path styles in tests

**Directory Iteration Logic:**
```zig
// Special handling for "." directory
if (std.mem.eql(u8, parent_path, ".")) {
    // Any entry without "/" is a direct child
    if (std.mem.indexOf(u8, entry_path, "/") == null) {
        // Direct child of current directory
    }
} else {
    // Standard hierarchical check for subdirectories
    if (std.mem.startsWith(u8, entry_path, parent_path) and
        entry_path.len > parent_path.len and
        entry_path[parent_path.len] == '/' and
        std.mem.indexOf(u8, relative_path, "/") == null) {
        // Direct child
    }
}
```

**Error Simulation:**
- `FileNotFound` for missing entries
- `NotDir` for file/directory mismatches
- `IsDir` for directory/file operations

## Real Implementation

**Thin Wrappers:** Delegates to `std.fs` with ownership tracking
- `owns_dir` flag prevents closing `std.fs.cwd()`
- Page allocator for handle allocation
- Direct error passthrough from stdlib

## Memory Management

**Allocation Strategy:**
- Page allocator for long-lived handles
- Caller-provided for temporary operations
- Clear owned vs borrowed semantics

**Mock Memory:**
```zig
// All strings are owned copies
const owned_path = try self.allocator.dupe(u8, path);
const owned_content = try self.allocator.dupe(u8, content);
```

## Test Support

**MockTestContext Helper:**
- Automatic "." directory creation
- Cleanup automation with `deinit()`
- Convenient `addFile`/`addDirectory` methods

**Benefits:**
- Deterministic testing without filesystem state
- Error injection capability
- No test artifacts in working directory
- Zero I/O latency in tests

## Usage Patterns

```zig
// Production
const filesystem = RealFilesystem.init();
const walker = Walker.initWithOptions(allocator, config, .{ .filesystem = filesystem });

// Testing
var mock_fs = MockFilesystem.init(allocator);
defer mock_fs.deinit();
try mock_fs.addFile("test.zig", "content");
const walker = Walker.initWithOptions(allocator, config, .{ .filesystem = mock_fs.interface() });
```

## Performance

- **Zero-cost abstraction:** Single indirect call per operation
- **Compile-time dispatch:** When interface known at compile time
- **No boxing/unboxing:** Direct memory layout
- **Path utilities reuse:** Both implementations share `path_utils`

## Limitations

- Panic on missing "." in mock `cwd()`
- Unreachable on page allocator failure
- No systematic error injection in mock
- Missing: symlinks, permissions, timestamps in mock
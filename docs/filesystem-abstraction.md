# Filesystem Abstraction Layer

> ⚠️ AI slop code and docs, is unstable and full of lies

## Architecture

- **`src/lib/filesystem/`** - Complete filesystem abstraction with parameterized dependencies for testing
  - `interface.zig` - Abstract interfaces: `FilesystemInterface`, `DirHandle`, `FileHandle`, `DirIterator`
  - `real.zig` - Production implementation using actual filesystem operations
  - `mock.zig` - Test implementation with in-memory filesystem simulation
- **Parameterized Dependencies:** All modules accept `FilesystemInterface` parameter for testability
- **Zero Performance Impact:** Interfaces use vtables with static dispatch where possible

## Benefits

- Complete test isolation without real I/O
- Deterministic testing with controlled filesystem state
- Ability to test error conditions (permission denied, disk full, etc.)
- No test artifacts in working directory
- Ready for async Zig

## Usage Example

```zig
// Production code
const real_fs = @import("lib/filesystem/real.zig");
var fs = real_fs.RealFilesystem.init();
try myFunction(allocator, &fs.interface);

// Test code
const mock_fs = @import("lib/filesystem/mock.zig");
var fs = try mock_fs.MockFilesystem.init(allocator);
defer fs.deinit();

// Set up test files
try fs.writeFile("/test.txt", "content");
try fs.createDir("/test_dir");

// Run code under test
try myFunction(allocator, &fs.interface);

// Verify results
const content = try fs.readFile("/output.txt");
try testing.expectEqualStrings("expected", content);
```

## Interface Design

The filesystem abstraction provides a minimal but complete interface:

- **File Operations:** read, write, append, delete, exists
- **Directory Operations:** create, remove, list entries
- **Path Operations:** join, resolve, normalize
- **Metadata:** file size, modification time, permissions
- **Error Simulation:** controllable error injection for testing

## Migration Guide

When converting existing code to use the filesystem abstraction:

1. Replace direct `std.fs` calls with interface methods
2. Accept `FilesystemInterface` as a parameter
3. Use mock filesystem in tests for isolation
4. Remove cleanup code - mock filesystem handles it automatically
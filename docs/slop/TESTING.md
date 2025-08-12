# Testing Guide for zz

Comprehensive guide for testing zz, from unit tests to integration testing.

## Testing Philosophy

- **Test everything that can break** - If it has logic, it needs tests
- **Fast feedback** - Tests should run quickly
- **Deterministic** - Tests must be reproducible
- **Isolated** - Tests should not depend on external state
- **Clear failures** - Failed tests should clearly indicate the problem

## Test Structure

```
src/
├── test.zig                 # Main test runner
├── test_helpers.zig         # Shared test utilities
├── MODULE/
│   ├── main.zig            # Module implementation
│   ├── test.zig            # Module test runner
│   └── test/               # Test files
│       ├── unit_test.zig      # Unit tests
│       ├── integration_test.zig # Integration tests
│       └── performance_test.zig # Performance tests
```

## Running Tests

### All Tests
```bash
# Run all tests
zig build test

# Run with verbose output
zig build test --verbose

# Run with specific allocator
zig build test -- --test-allocator
```

### Module-Specific Tests
```bash
# Test specific modules
zig build test-tree
zig build test-prompt
zig build test-patterns

# Or directly with zig test
zig test src/tree/test.zig
zig test src/prompt/test.zig
```

### Filtered Tests
```bash
# Run tests matching a pattern
zig test src/test.zig --test-filter "path"
zig test src/test.zig --test-filter "tree.*filter"

# Skip certain tests
zig test src/test.zig --test-filter "^((?!slow).)*$"
```

## Writing Tests

### Basic Test Structure
```zig
const std = @import("std");
const testing = std.testing;

test "descriptive test name" {
    // Arrange
    const allocator = testing.allocator;
    const input = "test input";
    
    // Act
    const result = try functionUnderTest(allocator, input);
    defer allocator.free(result);
    
    // Assert
    try testing.expectEqualStrings("expected output", result);
}
```

### Common Testing Patterns

#### Testing with Allocators
```zig
test "function properly cleans up memory" {
    // Use testing allocator to detect leaks
    const allocator = testing.allocator;
    
    const result = try functionWithAllocation(allocator);
    defer allocator.free(result);
    
    try testing.expect(result.len > 0);
}

test "function handles allocation failure" {
    // Use failing allocator to test error paths
    const allocator = testing.failing_allocator;
    
    const result = functionWithAllocation(allocator);
    try testing.expectError(error.OutOfMemory, result);
}
```

#### Testing Error Cases
```zig
test "function returns correct error" {
    const result = functionThatFails();
    try testing.expectError(error.InvalidInput, result);
}

test "function handles multiple error types" {
    // Test each error condition
    try testing.expectError(error.FileNotFound, openFile("nonexistent"));
    try testing.expectError(error.PermissionDenied, openFile("/root/protected"));
    try testing.expectError(error.InvalidPath, openFile(""));
}
```

#### Testing with Mock Filesystem
```zig
test "walker correctly traverses directories" {
    const allocator = testing.allocator;
    
    // Create mock filesystem
    var mock_fs = try MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Setup test structure
    try mock_fs.addDirectory("src");
    try mock_fs.addFile("src/main.zig", "const std = @import(\"std\");");
    try mock_fs.addDirectory("src/lib");
    try mock_fs.addFile("src/lib/test.zig", "test content");
    
    // Test traversal
    const walker = Walker.initWithOptions(allocator, config, .{
        .filesystem = mock_fs.interface(),
    });
    
    const entries = try walker.walk("src");
    defer allocator.free(entries);
    
    try testing.expectEqual(@as(usize, 4), entries.len);
}
```

#### Parameterized Tests
```zig
test "pattern matching various inputs" {
    const test_cases = [_]struct {
        pattern: []const u8,
        input: []const u8,
        expected: bool,
    }{
        .{ .pattern = "*.zig", .input = "main.zig", .expected = true },
        .{ .pattern = "*.zig", .input = "main.c", .expected = false },
        .{ .pattern = "test?.zig", .input = "test1.zig", .expected = true },
        .{ .pattern = "test?.zig", .input = "test12.zig", .expected = false },
    };
    
    for (test_cases) |tc| {
        const result = try matchPattern(tc.pattern, tc.input);
        try testing.expectEqual(tc.expected, result);
    }
}
```

#### Performance Tests
```zig
test "operation completes within time limit" {
    const allocator = testing.allocator;
    const start = std.time.milliTimestamp();
    
    // Run operation
    _ = try performOperation(allocator);
    
    const elapsed = std.time.milliTimestamp() - start;
    try testing.expect(elapsed < 100); // Should complete within 100ms
}
```

#### Fuzz Testing
```zig
test "pattern matcher handles random input" {
    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();
    
    // Generate random patterns and inputs
    for (0..1000) |_| {
        var pattern_buf: [100]u8 = undefined;
        var input_buf: [100]u8 = undefined;
        
        const pattern = randomString(random, &pattern_buf);
        const input = randomString(random, &input_buf);
        
        // Should not crash or hang
        _ = matchPattern(pattern, input) catch |err| {
            // Some errors are expected for invalid patterns
            try testing.expect(err == error.InvalidPattern);
        };
    }
}
```

## Test Helpers

### Common Test Utilities
```zig
// src/test_helpers.zig

pub fn createTempDir(allocator: Allocator) !TempDir {
    // Create temporary directory for testing
}

pub fn expectFile(path: []const u8, content: []const u8) !void {
    // Verify file exists with expected content
}

pub fn expectNoFile(path: []const u8) !void {
    // Verify file does not exist
}

pub fn captureOutput(allocator: Allocator, fn_to_test: anytype) ![]const u8 {
    // Capture stdout/stderr from function
}

pub fn withTimeout(comptime ms: u64, fn_to_test: anytype) !void {
    // Run function with timeout
}
```

### Mock Objects
```zig
pub const MockAllocator = struct {
    // Track allocations for testing
    allocations: std.ArrayList([]u8),
    failures_remaining: u32,
    
    pub fn allocator(self: *MockAllocator) Allocator {
        // Return allocator that can simulate failures
    }
};

pub const MockWriter = struct {
    buffer: std.ArrayList(u8),
    
    pub fn writer(self: *MockWriter) Writer {
        // Return writer that captures output
    }
};
```

## Integration Testing

### End-to-End Tests
```zig
test "tree command produces expected output" {
    const allocator = testing.allocator;
    
    // Setup test directory
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    try tmp_dir.dir.makeDir("src");
    try tmp_dir.dir.writeFile("src/main.zig", "test");
    
    // Run command
    const args = [_][]const u8{ "tree", tmp_dir.path };
    const output = try runCommand(allocator, &args);
    defer allocator.free(output);
    
    // Verify output
    try testing.expect(std.mem.indexOf(u8, output, "src") != null);
    try testing.expect(std.mem.indexOf(u8, output, "main.zig") != null);
}
```

### Cross-Module Tests
```zig
test "tree and prompt modules work together" {
    const allocator = testing.allocator;
    
    // Use tree to get files
    const tree_output = try tree.getFiles(allocator, "src");
    defer allocator.free(tree_output);
    
    // Use prompt to process them
    const prompt_output = try prompt.generate(allocator, tree_output);
    defer allocator.free(prompt_output);
    
    try testing.expect(prompt_output.len > 0);
}
```

## Test Coverage

### Measuring Coverage
```bash
# Build with coverage
zig build test -Dtest-coverage

# Generate coverage report
kcov coverage zig-out/bin/test
open coverage/index.html
```

### Coverage Goals
- **Unit tests**: 90%+ coverage
- **Integration tests**: 80%+ coverage
- **Critical paths**: 100% coverage
- **Error handling**: 100% coverage

## Benchmark Testing

### Writing Benchmarks
```zig
test "benchmark path operations" {
    const allocator = testing.allocator;
    const iterations = 10000;
    
    var timer = try std.time.Timer.start();
    for (0..iterations) |_| {
        const path = try joinPath(allocator, "dir", "file");
        allocator.free(path);
    }
    const elapsed = timer.read();
    
    const ns_per_op = elapsed / iterations;
    std.debug.print("Path join: {} ns/op\n", .{ns_per_op});
    
    // Fail if regression
    try testing.expect(ns_per_op < 1000); // Must be under 1μs
}
```

### Regression Testing
```zig
test "no performance regression" {
    const baseline = try loadBaseline();
    const current = try runBenchmarks();
    
    for (current) |result, i| {
        const regression = result.time > baseline[i].time * 1.1; // 10% threshold
        if (regression) {
            std.debug.print("Regression in {s}: {}ns -> {}ns\n", .{
                result.name,
                baseline[i].time,
                result.time,
            });
            try testing.expect(false);
        }
    }
}
```

## Property-Based Testing

### Using Property Tests
```zig
test "path joining is associative" {
    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();
    
    for (0..100) |_| {
        const a = randomPath(random);
        const b = randomPath(random);
        const c = randomPath(random);
        
        // (a + b) + c = a + (b + c)
        const left = try joinPath(allocator, 
            try joinPath(allocator, a, b), c);
        const right = try joinPath(allocator, a, 
            try joinPath(allocator, b, c));
        
        try testing.expectEqualStrings(left, right);
    }
}
```

## Test Organization

### Test Categories
```zig
// Unit tests - test individual functions
test "unit: parsePattern parses simple glob" { }

// Integration tests - test module interactions  
test "integration: tree and config work together" { }

// Performance tests - verify performance
test "perf: pattern matching under 100ns" { }

// Stress tests - test limits
test "stress: handles 10000 files" { }

// Security tests - test security boundaries
test "security: prevents path traversal" { }
```

### Test Naming Convention
```zig
test "module: component: specific behavior" {
    // Example: "tree: filter: ignores dot directories"
    // Example: "prompt: glob: expands brace patterns"
    // Example: "path: join: handles empty components"
}
```

## Continuous Integration

### GitHub Actions
```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        zig: [0.14.1, master]
    
    steps:
      - uses: actions/checkout@v2
      - uses: goto-bus-stop/setup-zig@v1
        with:
          version: ${{ matrix.zig }}
      
      - name: Run tests
        run: zig build test
      
      - name: Run benchmarks
        run: zig build benchmark
      
      - name: Check coverage
        run: |
          zig build test -Dtest-coverage
          # Fail if coverage drops below 80%
```

## Debugging Tests

### Debug Output
```zig
test "debug failing test" {
    std.debug.print("\n=== Debug Output ===\n", .{});
    std.debug.print("Value: {}\n", .{value});
    std.debug.print("Expected: {}\n", .{expected});
    std.debug.print("==================\n", .{});
    
    try testing.expectEqual(expected, value);
}
```

### Using Debugger
```bash
# Build tests with debug symbols
zig build test -Drelease-safe=false

# Run with debugger
gdb zig-out/bin/test
(gdb) break src/tree/walker.zig:42
(gdb) run --test-filter "specific test"
```

### Test Isolation
```zig
test "isolated test" {
    // Save and restore global state
    const saved_state = global_state;
    defer global_state = saved_state;
    
    // Test with modified state
    global_state = test_state;
    try runTest();
}
```

## Best Practices

### Do's
- ✅ Write tests before fixing bugs
- ✅ Test edge cases and error conditions
- ✅ Use descriptive test names
- ✅ Keep tests focused and small
- ✅ Use test helpers for common operations
- ✅ Test both success and failure paths
- ✅ Use mock objects for external dependencies

### Don'ts
- ❌ Don't test implementation details
- ❌ Don't use real filesystem when mock will do
- ❌ Don't ignore flaky tests
- ❌ Don't write slow tests without need
- ❌ Don't test standard library functions
- ❌ Don't use global state in tests
- ❌ Don't skip error handling tests

## Test Checklist

Before submitting PR:
- [ ] All tests pass locally
- [ ] New features have tests
- [ ] Bug fixes include regression tests
- [ ] Edge cases are tested
- [ ] Error paths are tested
- [ ] Performance tests pass
- [ ] No test pollution (tests work in isolation)
- [ ] Documentation updated if needed
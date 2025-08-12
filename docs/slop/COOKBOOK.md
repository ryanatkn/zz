# COOKBOOK.md

**Step-by-step recipes for common tasks**

## Adding a New Command

### 1. Add to Command Enum
```zig
// src/cli/command.zig
pub const Command = enum {
    tree,
    prompt,
    benchmark,
    help,
    newcmd,  // Add your command here
};
```

### 2. Update String Parser
```zig
// src/cli/command.zig
pub fn fromString(str: []const u8) ?Command {
    if (std.mem.eql(u8, str, "tree")) return .tree;
    if (std.mem.eql(u8, str, "prompt")) return .prompt;
    if (std.mem.eql(u8, str, "benchmark")) return .benchmark;
    if (std.mem.eql(u8, str, "help")) return .help;
    if (std.mem.eql(u8, str, "newcmd")) return .newcmd;  // Add this
    return null;
}
```

### 3. Add Handler in Runner
```zig
// src/cli/runner.zig
const newcmd = @import("../newcmd/main.zig");

pub fn run(allocator: Allocator, command: Command, args: [][:0]const u8) !void {
    switch (command) {
        .tree => try tree.run(allocator, args),
        .prompt => try prompt.run(allocator, args),
        .benchmark => try benchmark.run(allocator, args),
        .help => try help.show(),
        .newcmd => try newcmd.run(allocator, args),  // Add this
    }
}
```

### 4. Create Module Structure
```bash
mkdir -p src/newcmd/test
touch src/newcmd/main.zig
touch src/newcmd/test.zig
```

### 5. Implement Main Entry Point
```zig
// src/newcmd/main.zig
const std = @import("std");

pub fn run(allocator: std.mem.Allocator, args: [][:0]const u8) !void {
    // Parse arguments
    // Do the work
    // Output results
}
```

### 6. Add Tests
```zig
// src/newcmd/test.zig
const std = @import("std");
const testing = std.testing;

test "newcmd handles basic input" {
    // Test implementation
}
```

### 7. Update Help Text
```zig
// src/cli/help.zig
pub fn showUsage() void {
    std.debug.print(
        \\Commands:
        \\  tree [dir] [depth]        Show directory tree
        \\  prompt [files...]         Generate LLM prompt
        \\  benchmark [options]       Run benchmarks
        \\  newcmd [options]         Your new command description
        \\  help                     Show this help
    , .{});
}
```

### 8. Add to Test Runner
```zig
// src/test.zig
test {
    _ = @import("newcmd/test.zig");
}
```

---

## Adding a New Benchmark

### 1. Add to Benchmark Library
```zig
// src/lib/benchmark.zig
pub fn benchmarkNewThing(self: *Self, target_duration_ns: u64, verbose: bool) !void {
    if (verbose) {
        std.debug.print("\n=== New Thing Benchmark ===\n", .{});
    }
    
    var timer = try std.time.Timer.start();
    var iterations: usize = 0;
    
    while (timer.read() < target_duration_ns) {
        // Do the operation to benchmark
        iterations += 1;
    }
    
    const elapsed = timer.read();
    const ns_per_op = elapsed / iterations;
    
    try self.results.append(.{
        .name = "New Thing",
        .total_operations = iterations,
        .elapsed_ns = elapsed,
        .ns_per_op = ns_per_op,
    });
}
```

### 2. Add to Runner
```zig
// src/benchmark/main.zig

// Add to Options struct
const Options = struct {
    // ...
    run_new_thing: bool = false,
};

// Add to variance multiplier function
fn getVarianceMultiplier(benchmark_name: []const u8) f64 {
    if (std.mem.eql(u8, benchmark_name, "newthing")) return 1.5;
    // ...
}

// Add to argument parsing
if (std.mem.eql(u8, name, "newthing")) options.run_new_thing = true;

// Add to execution
if (options.run_all or options.run_new_thing) {
    const duration = getEffectiveDuration(options.duration_ns, "newthing", options.duration_multiplier);
    try bench.benchmarkNewThing(duration, false);
}
```

---

## Adding a Pattern Matcher

### 1. Define Pattern Type
```zig
// src/patterns/matcher.zig
pub const PatternType = enum {
    literal,
    glob,
    regex,
    custom,  // Add new type
};
```

### 2. Implement Matching Logic
```zig
// src/patterns/matcher.zig
fn matchCustom(pattern: []const u8, path: []const u8) bool {
    // Your custom matching logic
}

pub fn matches(self: *const Self, path: []const u8) bool {
    return switch (self.pattern_type) {
        .literal => matchLiteral(self.pattern, path),
        .glob => matchGlob(self.pattern, path),
        .regex => matchRegex(self.pattern, path),
        .custom => matchCustom(self.pattern, path),
    };
}
```

### 3. Add Tests
```zig
// src/patterns/test/matcher_test.zig
test "custom pattern matching" {
    const pattern = try Matcher.init(allocator, "custom:something");
    try testing.expect(pattern.matches("something"));
    try testing.expect(!pattern.matches("other"));
}
```

---

## Optimizing a Hot Path

### 1. Measure First
```zig
// Add temporary timing
var timer = try std.time.Timer.start();
defer {
    const elapsed = timer.read();
    std.debug.print("Operation took: {} ns\n", .{elapsed});
}
```

### 2. Add to Benchmarks
Follow "Adding a New Benchmark" recipe above

### 3. Common Optimizations

**String Operations:**
```zig
// SLOW: Format strings
const result = try std.fmt.allocPrint(allocator, "{s}/{s}", .{a, b});

// FAST: Direct manipulation
const result = try allocator.alloc(u8, a.len + 1 + b.len);
@memcpy(result[0..a.len], a);
result[a.len] = '/';
@memcpy(result[a.len + 1..], b);
```

**Memory Allocation:**
```zig
// SLOW: Many small allocations
for (items) |item| {
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
}

// FAST: Arena allocator
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const arena_allocator = arena.allocator();
for (items) |item| {
    const buf = try arena_allocator.alloc(u8, size);
    // No individual frees needed
}
```

**Path Checking:**
```zig
// SLOW: Multiple string comparisons
if (std.mem.eql(u8, ext, ".zig") or 
    std.mem.eql(u8, ext, ".c") or 
    std.mem.eql(u8, ext, ".h")) {

// FAST: Switch on length first
switch (ext.len) {
    2 => if (ext[0] == '.' and (ext[1] == 'c' or ext[1] == 'h')) {},
    4 => if (std.mem.eql(u8, ext, ".zig")) {},
    else => {},
}
```

---

## Adding Mock Filesystem Support

### 1. Create Mock Structure
```zig
// In your test file
var mock_fs = MockFilesystem.init(allocator);
defer mock_fs.deinit();

try mock_fs.addDirectory("src");
try mock_fs.addFile("src/main.zig", "const std = @import(\"std\");");
```

### 2. Use in Module
```zig
// Your module
pub fn processFiles(allocator: Allocator, filesystem: FilesystemInterface) !void {
    const dir = try filesystem.openDir("src");
    defer dir.close();
    
    var iter = try dir.iterate();
    while (try iter.next()) |entry| {
        // Process entry
    }
}
```

### 3. Test Both Implementations
```zig
test "process files with mock" {
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    try mock_fs.addFile("src/test.zig", "test content");
    
    try processFiles(allocator, mock_fs.interface());
}

test "process files with real" {
    const real_fs = RealFilesystem.init();
    // Only if you have test fixtures set up
    try processFiles(allocator, real_fs);
}
```

---

## Debugging Performance Issues

### 1. Add Timing Points
```zig
var timer = try std.time.Timer.start();
var last_time: u64 = 0;

// First operation
const time1 = timer.read();
std.debug.print("Step 1: {} ns\n", .{time1 - last_time});
last_time = time1;

// Second operation  
const time2 = timer.read();
std.debug.print("Step 2: {} ns\n", .{time2 - last_time});
```

### 2. Check Allocations
```zig
// Wrap allocator to track
var counting_alloc = CountingAllocator.init(allocator);
const tracked = counting_alloc.allocator();

// Do operations with tracked allocator

std.debug.print("Allocations: {}, Bytes: {}\n", 
    .{counting_alloc.count, counting_alloc.bytes});
```

### 3. Profile with tracy
```zig
// Add tracy zones (if integrated)
const tracy = @import("tracy");
const zone = tracy.zone(@src());
defer zone.end();
```

### 4. Use Benchmark Variance
```bash
# Run specific benchmark longer for stability
zz benchmark --only=memory --duration-multiplier=5.0
```

---

## Common Fixes

### "FileNotFound" in Tests
```zig
// Problem: Using relative paths
const file = try fs.openFile("test.txt", .{});

// Solution: Use mock filesystem
var mock_fs = MockFilesystem.init(allocator);
try mock_fs.addFile("test.txt", "content");
```

### High Memory Usage
```zig
// Problem: Not using arena for temporary data
var list = ArrayList([]u8).init(allocator);
for (items) |item| {
    try list.append(try allocator.dupe(u8, item));
}

// Solution: Arena for batch operations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
// Use arena.allocator() for all temporary allocations
```

### Benchmark Variance
```bash
# Problem: Unstable benchmark results
zz benchmark --only=memory

# Solution: Run longer with duration multiplier
zz benchmark --only=memory --duration-multiplier=3.0
```

---

*Add your own recipes as you discover patterns.*
# Plan: Add `./` Prefix to Relative Paths Throughout Project

## 🔴 TEST-FIRST APPROACH
**CRITICAL: All changes must follow TDD - write failing tests FIRST, then implement the fix**

## Objective
Ensure all relative paths printed throughout the project are consistently prefixed with `./` for improved clarity and POSIX compliance.

## Research Findings
After thorough investigation, I've identified all locations where paths are output:

### Current State Analysis

#### ✅ Already Correct
- **Tree module** (`src/tree/formatter.zig:37`): Already prefixes with `./` for list format
  ```zig
  std.debug.print("./{s}\n", .{path_from_root});
  ```

#### ❌ Needs Update
1. **Prompt module** (`src/prompt/builder.zig:73`): 
   - Current: `<File path="src/file.zig">`
   - Desired: `<File path="./src/file.zig">`

2. **Error messages in prompt module** (`src/prompt/main.zig`):
   - Line 73: `Warning: No files matched pattern: {s}`
   - Line 75: `Error: No files matched pattern: {s}`
   - Line 81: `Warning: File not found: {s}`
   - Line 83: `Error: File not found: {s}`
   - Line 125: `Error: Explicitly requested file was ignored: {s}`

3. **Large file warning** (`src/prompt/builder.zig:58`):
   - Current: `Warning: Skipping large file (>10MB): src/large.zig`
   - Desired: `Warning: Skipping large file (>10MB): ./src/large.zig`

4. **Benchmark baseline error** (`src/benchmark/main.zig:180`):
   - Current: `Baseline file not found: benchmarks/baseline.md`
   - Desired: `Baseline file not found: ./benchmarks/baseline.md`

### Important Behaviors to Preserve
- **Absolute paths** must remain unchanged (e.g., `/etc/passwd` stays `/etc/passwd`)
- **Already prefixed paths** should not get double-prefixed (e.g., `./src` stays `./src`)
- **Single dot** (`.`) should remain as-is
- **Empty paths** should become `./`

## Implementation Plan (TDD Approach)

### Phase 1: Create Utility Function (Tests First)

#### Step 1.1: Write Failing Tests
Add test block to `src/lib/path.zig`:

```zig
test "addRelativePrefix basic cases" {
    const allocator = std.testing.allocator;
    
    // Basic relative path
    const result1 = try addRelativePrefix(allocator, "src/file.zig");
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("./src/file.zig", result1);
    
    // Already prefixed
    const result2 = try addRelativePrefix(allocator, "./src/file.zig");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("./src/file.zig", result2);
    
    // Absolute path (unchanged)
    const result3 = try addRelativePrefix(allocator, "/etc/passwd");
    defer allocator.free(result3);
    try std.testing.expectEqualStrings("/etc/passwd", result3);
    
    // Empty path
    const result4 = try addRelativePrefix(allocator, "");
    defer allocator.free(result4);
    try std.testing.expectEqualStrings("./", result4);
    
    // Single dot
    const result5 = try addRelativePrefix(allocator, ".");
    defer allocator.free(result5);
    try std.testing.expectEqualStrings(".", result5);
    
    // Path starting with ../
    const result6 = try addRelativePrefix(allocator, "../parent/file.zig");
    defer allocator.free(result6);
    try std.testing.expectEqualStrings("../parent/file.zig", result6);
}
```

#### Step 1.2: Implement Function
Add to `src/lib/path.zig`:

```zig
/// Add ./ prefix to relative paths that don't already have it
/// Absolute paths and already-prefixed paths are returned unchanged
pub fn addRelativePrefix(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // Empty path becomes ./
    if (path.len == 0) {
        return try allocator.dupe(u8, "./");
    }
    
    // Single dot remains as-is
    if (std.mem.eql(u8, path, ".")) {
        return try allocator.dupe(u8, ".");
    }
    
    // Absolute paths (starting with /) remain unchanged
    if (path[0] == '/') {
        return try allocator.dupe(u8, path);
    }
    
    // Already prefixed with ./
    if (path.len >= 2 and path[0] == '.' and path[1] == '/') {
        return try allocator.dupe(u8, path);
    }
    
    // Parent directory references remain unchanged
    if (path.len >= 3 and path[0] == '.' and path[1] == '.' and path[2] == '/') {
        return try allocator.dupe(u8, path);
    }
    
    // Add ./ prefix
    return try std.fmt.allocPrint(allocator, "./{s}", .{path});
}
```

### Phase 2: Update Prompt Module (Tests First)

#### Step 2.1: Write Failing Test
Add to `src/prompt/test/builder_test.zig`:

```zig
test "prompt builder outputs relative paths with ./ prefix" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();
    
    try ctx.writeFile("test.zig", "const a = 1;");
    
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem);
    defer builder.deinit();
    
    try builder.addFile("test.zig");
    
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    
    const output = buf.items;
    
    // Should contain ./test.zig in the XML tag
    try testing.expect(std.mem.indexOf(u8, output, "<File path=\"./test.zig\">") != null);
}

test "prompt builder preserves absolute paths" {
    // Test with MockFilesystem to simulate absolute path
    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();
    
    try mock_fs.addFile("/etc/passwd", "root:x:0:0");
    
    var builder = PromptBuilder.init(testing.allocator, mock_fs.interface());
    defer builder.deinit();
    
    try builder.addFile("/etc/passwd");
    
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    
    const output = buf.items;
    
    // Absolute paths should remain unchanged
    try testing.expect(std.mem.indexOf(u8, output, "<File path=\"/etc/passwd\">") != null);
}
```

#### Step 2.2: Update Implementation
Modify `src/prompt/builder.zig` line 73:

```zig
// Add import at top
const path_utils = @import("../lib/path.zig");

// Update line 73
const prefixed_path = try path_utils.addRelativePrefix(self.arena.allocator(), file_path);
const header = try std.fmt.allocPrint(self.arena.allocator(), "<File path=\"{s}\">", .{prefixed_path});
```

### Phase 3: Update Error Messages (Tests First)

#### Step 3.1: Write Failing Tests
Create `src/prompt/test/error_format_test.zig`:

```zig
const std = @import("std");
const testing = std.testing;

test "error messages use ./ prefix for relative paths" {
    // Test that error messages properly format paths
    // This would be an integration test that captures stderr
    // Implementation depends on how error handling is structured
}
```

#### Step 3.2: Update Error Messages

Update `src/prompt/main.zig`:
```zig
// Add import
const path_utils = @import("../lib/path.zig");

// Update error messages (example for line 73):
const prefixed = try path_utils.addRelativePrefix(allocator, result.pattern);
defer allocator.free(prefixed);
try stderr.print("Warning: No files matched pattern: {s}\n", .{prefixed});
```

Similar updates for:
- `src/prompt/builder.zig:58` (large file warning)
- `src/benchmark/main.zig:180` (baseline file error)

### Phase 4: Validation & Documentation

1. **Run full test suite**:
   ```bash
   zig build test
   ```

2. **Manual testing**:
   ```bash
   # Test tree list format (should already work)
   ./zig-out/bin/zz tree --format=list src/lib
   
   # Test prompt with relative path (should now show ./src/main.zig)
   ./zig-out/bin/zz prompt src/main.zig
   
   # Test prompt with absolute path (should remain /etc/passwd)
   ./zig-out/bin/zz prompt /etc/passwd
   
   # Test error messages
   ./zig-out/bin/zz prompt nonexistent.zig
   ```

3. **Update CLAUDE.md** to emphasize test-first approach more prominently

## Success Criteria Checklist

- [ ] All new tests fail before implementation (proving they test correctly)
- [ ] All tests pass after implementation
- [ ] Relative paths show as `./path/to/file` in all outputs
- [ ] Absolute paths remain unchanged (`/absolute/path`)
- [ ] Already-prefixed paths don't get double-prefixed
- [ ] Empty paths handled correctly (become `./`)
- [ ] Parent references (`../`) remain unchanged
- [ ] No regression in existing functionality
- [ ] Performance impact negligible (simple string operations)

## Files Modified Summary

### New/Modified Tests (Write First!)
1. `src/lib/path.zig` - Add test block for `addRelativePrefix`
2. `src/prompt/test/builder_test.zig` - Add XML output format tests
3. Create `src/prompt/test/error_format_test.zig` - Error message tests
4. Create `src/benchmark/test/error_format_test.zig` - Benchmark error tests

### Implementation Files (After Tests Fail)
1. `src/lib/path.zig` - Add `addRelativePrefix()` function
2. `src/prompt/builder.zig` - Update line 73 for XML output
3. `src/prompt/main.zig` - Update error messages (lines 73, 75, 81, 83, 125)
4. `src/prompt/builder.zig` - Update line 58 for large file warning
5. `src/benchmark/main.zig` - Update line 180 for baseline error

### Documentation
1. `CLAUDE.md` - Add stronger emphasis on TDD approach

## Timeline Estimate
- Phase 1 (Utility function): 30 minutes
- Phase 2 (Prompt module): 45 minutes
- Phase 3 (Error messages): 45 minutes
- Phase 4 (Validation): 30 minutes
- **Total**: ~2.5 hours

## Notes
- This change improves POSIX compliance and user experience
- Consistent with Unix convention of using `./` for relative paths
- Makes output clearer when paths are copy-pasted
- Tree module already follows this pattern, bringing consistency across all commands
# Testing Guide

> ⚠️ AI slop code and docs, is unstable and full of lies

## Running Tests
```bash
$ zig build test                                       # Run all tests
$ zig build test -Dtest-filter="pattern"              # Run only tests matching pattern
$ zig build test --verbose                            # Show build commands and execution
$ zig build test 2>&1 | rg "pattern"                  # Alternative: pipe output to filter

# Always use `zig build test` which properly configures modules and links libraries
```

## Understanding Test Output
- **No output after filter = no matches**: If you see only the filter line and nothing else, your pattern didn't match any tests
- **Test sections show matches**: Look for "=== Module Tests ===" sections - these indicate tests ran
- **Success is mostly silent**: Passing tests produce minimal output (Zig convention)
- **Use --verbose**: See which tests are being run and verify filters work
- **Test summary**: Shows at the end when tests actually run (e.g., "328/332 passed")
- **Current behavior**: No matches exit with status 0 (success)
- **Future enhancement**: Will error on no matches to catch typos and improve CI safety

## Test Infrastructure

The test system is organized in `src/lib/test/`:
- **`helpers.zig`** - Test utilities and contexts (consolidated from test_helpers.zig)
- **`fixture_loader.zig`** - Test fixture loading
- **`fixture_runner.zig`** - Test fixture execution
- **`fixtures/`** - Language-specific test fixtures for each supported language

## Writing Tests

Tests should be colocated with the code they test, using Zig's built-in test blocks:

```zig
test "my feature works correctly" {
    // Test implementation
}
```

For integration tests that require filesystem operations, use the mock filesystem from `src/lib/filesystem/mock.zig` to ensure deterministic, isolated testing without real I/O.

## Best Practices
1. Write tests for all new features and edge cases
2. Use descriptive test names that explain what is being tested
3. Keep tests focused on a single behavior or edge case
4. Use the mock filesystem for any file operations
5. Run tests frequently during development with `zig build test`
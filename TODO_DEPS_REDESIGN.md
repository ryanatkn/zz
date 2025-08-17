# TODO: Dependency Management System Redesign

## Current Issues

### 1. Manifest Generation Problems
- **Timestamp Churn**: `manifest.json` regenerates with new timestamp on every build, causing unnecessary git changes
- **Language Name Corruption**: Parser function extraction corrupts language names (e.g., "css" → "ss", "typescript" → "ypescript")
- **Incomplete Manifest**: Sometimes only shows subset of dependencies instead of all 11

### 2. Performance Issues
- **Sequential Operations**: Dependencies checked/updated one at a time
- **Redundant Builds**: Tree-sitter grammars rebuilt even when unchanged
- **No Change Detection**: System doesn't know when deps.zon actually changes

### 3. Complexity Issues
- **Include/Exclude/Preserve**: Complex filtering logic during copy operations
- **Multiple State Files**: `.version` files, `manifest.json`, no unified state

## Proposed Redesign

### Phase 1: Bug Fixes (Immediate)

#### 1.1 Fix Manifest Generation
- [ ] Remove timestamp from `manifest.json` or use deterministic value (deps.zon mtime)
- [ ] Fix language name corruption in `generatePurpose()` and `extractLanguage()`
- [ ] Ensure all dependencies from `deps.zon` appear in manifest

#### 1.2 Fix String Corruption
- [ ] Debug buffer overrun in `build_parser.zig` line 140-141
- [ ] Fix parser function name generation (tree_sitter_css not tree_sitter_ss)

### Phase 2: Performance Improvements

#### 2.1 Simple Change Detection
```zig
// Add to src/lib/deps/hashing.zig
pub fn hashDepsZon(allocator: Allocator, path: []const u8) !u64 {
    const content = try io.readFile(allocator, path);
    defer allocator.free(content);
    return std.hash.XxHash64.hash(0, content);
}

// Store hash in .deps_state
{
    "deps_zon_hash": "xxh64:abc123...",
    "last_check": 1234567890
}
```

#### 2.2 Parallel Git Operations
```zig
// In manager.zig - check multiple repos concurrently
pub fn checkAllUpdates(deps: []Dependency) ![]UpdateStatus {
    var threads = try allocator.alloc(Thread, deps.len);
    var results = try allocator.alloc(UpdateStatus, deps.len);
    
    for (deps, 0..) |dep, i| {
        threads[i] = try Thread.spawn(.{}, checkSingleDep, .{dep, &results[i]});
    }
    
    for (threads) |thread| {
        thread.join();
    }
    return results;
}
```

#### 2.3 Binary Caching
```zig
// Cache compiled .a/.so files
const cache_key = try hashSourceTree(dep_dir);
const cache_path = try std.fmt.allocPrint(allocator, 
    "~/.cache/zz/deps/{s}-{x}.a", .{dep_name, cache_key});

if (fileExists(cache_path)) {
    // Use cached binary
    try copyFile(cache_path, output_path);
} else {
    // Build and cache
    try buildDependency(dep_dir);
    try copyFile(output_path, cache_path);
}
```

### Phase 3: Simplifications

#### 3.1 Preserve Files as Overlays
```zig
// Before update
try operations.copyToPreserve(dep_dir, preserve_patterns);

// Do normal update
try git.checkout(dep_dir, new_version);

// Restore preserved files
try operations.restoreFromPreserve(dep_dir);
```

#### 3.2 Unified State Management
```zig
// Single .deps_state.json file instead of multiple .version files
{
    "config_hash": "xxh64:abc123...",  // Hash of deps.zon
    "manifest_hash": "xxh64:def456...", // Hash of last generated manifest
    "dependencies": {
        "tree-sitter": {
            "version": "v0.25.0",
            "commit": "abc123...",
            "source_hash": "xxh64:ghi789...",
            "binary_cache_key": "xxh64:jkl012..."
        }
    }
}
```

#### 3.3 Lazy Validation
- Only check dependencies when explicitly requested or deps.zon changes
- Use filesystem mtime as fast first-pass check
- Skip validation during normal builds if state is fresh

## Implementation Order

1. **Week 1**: Fix critical bugs (manifest generation, string corruption)
2. **Week 2**: Add simple change detection and state management
3. **Week 3**: Implement parallel operations
4. **Week 4**: Add binary caching
5. **Week 5**: Simplify preserve_files handling
6. **Week 6**: Testing and documentation

## Benefits

### Developer Experience
- **No more git churn** from timestamp changes
- **Faster builds** with binary caching
- **Instant status checks** with hash-based validation
- **Cleaner diffs** showing only real changes

### Performance Gains
- **10x faster** dependency checks with parallelization
- **Skip unnecessary work** with change detection
- **Reuse compiled binaries** across builds
- **Reduce network calls** with smart caching

### Maintenance
- **Simpler codebase** with overlay-based preserve_files
- **Single source of truth** with unified state file
- **Less complexity** in include/exclude handling
- **Better testability** with deterministic operations

## Testing Strategy

### Unit Tests
- Hash calculation and comparison
- Parallel operation coordination
- Cache key generation
- State file management

### Integration Tests
- Full dependency update cycle
- Preserve file handling
- Binary cache hits/misses
- Manifest generation consistency

### Performance Tests
- Measure parallel vs sequential updates
- Cache hit ratio tracking
- Build time improvements
- Memory usage optimization

## Migration Path

1. New code works alongside existing system
2. Gradual rollout with feature flags
3. Automatic migration of existing .version files to new state
4. Backwards compatibility for 2 releases
5. Full cutover after stability proven

## Success Metrics

- [ ] Zero timestamp-related git changes
- [ ] All 11 dependencies in manifest
- [ ] No language name corruption
- [ ] 5x faster `zz deps --check`
- [ ] 3x faster clean builds
- [ ] 90%+ binary cache hit rate

## Notes

- Keep deps.zon as single source of truth
- Manifest is output only, never input
- Performance > backwards compatibility
- Simplicity > features
# GOTCHAS.md

**Non-obvious knowledge that will bite you**

## Performance Gotchas

### Memory Pool Benchmark Variance
**The gotcha:** Memory pool benchmarks show 50-100% variance in Debug mode  
**Why:** Debug allocator has different behavior, system memory pressure varies  
**Solution:** Added 3x duration multiplier for this benchmark  
**Don't:** Panic when you see different results each run

### Path Joining Performance
**The gotcha:** Using `std.fmt.allocPrint` for paths destroys performance  
**Why:** Format string parsing overhead for a simple operation  
**Solution:** Always use `lib/path.zig:joinPath()`  
```zig
// BAD - 65μs per operation
const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{dir, file});

// GOOD - 47μs per operation  
const path = try path_utils.joinPath(allocator, dir, file);
```

### String Pool Ownership
**The gotcha:** PathCache returns pointers to interned strings  
**Why:** Strings are owned by the cache, not the caller  
**Solution:** Never free strings from PathCache, free the cache itself when done
```zig
const interned = try cache.getPath("src");
// DON'T: allocator.free(interned);
// DO: cache.deinit(); // When completely done
```

## Filesystem Gotchas

### Root Path Handling
**The gotcha:** Root can be "/" or empty string depending on context  
**Why:** Different code paths handle this differently  
**Solution:** Always check both cases in path handling code
```zig
if (path.len == 0 or (path.len == 1 and path[0] == '/')) {
    // Handle root
}
```

### Mock vs Real Filesystem Error Codes
**The gotcha:** Mock filesystem must return EXACT same errors as real filesystem  
**Why:** Tests will pass with mock but fail in production otherwise  
**Solution:** Test error conditions with both filesystems when adding new error handling

### Symlink Behavior
**The gotcha:** Symlinks behave differently in mock vs real filesystem  
**Why:** Mock filesystem doesn't fully simulate symlink resolution  
**Solution:** Always test symlink-related code with real filesystem too

## Pattern Matching Gotchas

### Gitignore Patterns Are Stateless
**The gotcha:** Each gitignore pattern match is independent  
**Why:** Performance - avoiding complex state management  
**Solution:** Order matters - test patterns in the order they appear in .gitignore

### Fast Path Patterns Are Hardcoded
**The gotcha:** Only specific patterns get fast-path optimization  
**Why:** Performance optimization for common cases  
**Current fast paths:**
- `*.{zig,c,h}`
- `*.{js,ts}`  
- `*.{md,txt}`
**Solution:** Don't expect same performance for custom patterns

### Directory Patterns Need Trailing Slash
**The gotcha:** `node_modules` matches file, `node_modules/` matches directory  
**Why:** Gitignore compatibility  
**Solution:** Always use trailing slash for directory patterns

## Testing Gotchas

### Arena Allocator in Tests
**The gotcha:** Arena allocator hides memory leaks in tests  
**Why:** Everything gets freed at once, individual leaks not caught  
**Solution:** Use testing.allocator for leak detection, arena only when intentional

### Test Order Dependencies
**The gotcha:** Tests might pass individually but fail when run together  
**Why:** Global state, file system artifacts, or timing issues  
**Solution:** Each test must be completely independent, use mock filesystem

### Performance Tests in Debug Mode
**The gotcha:** Performance tests are ~5x slower in Debug mode  
**Why:** No optimizations, safety checks enabled  
**Solution:** Performance tests are for relative comparison, not absolute numbers

## CLI Gotchas

### Argument Parsing Order
**The gotcha:** Positional arguments must come before flags  
**Why:** Simple parser, no GNU-style permutation  
**Solution:** Always put positional args first
```bash
# GOOD
zz tree src/ 2 --format=json

# BAD  
zz tree --format=json src/ 2
```

### Output Goes to Stdout
**The gotcha:** Everything outputs to stdout, even errors in some cases  
**Why:** Unix philosophy - compose with pipes  
**Solution:** Use stderr for actual errors, stdout for all output including warnings

### No Default Glob Pattern
**The gotcha:** `zz prompt` with no args errors (doesn't default to `*.zig`)  
**Why:** Explicit is better than implicit, avoid surprises  
**Solution:** Always specify patterns explicitly

## Configuration Gotchas

### Config Loading is Lazy
**The gotcha:** Config errors only surface when config is accessed  
**Why:** Performance - don't parse config if not needed  
**Solution:** Config-related errors might appear late in execution

### Pattern Arrays Don't Merge
**The gotcha:** Custom patterns replace ALL defaults unless using "extend"  
**Why:** Explicit control over pattern sets  
**Solution:** Use `.base_patterns = "extend"` to add to defaults

### Hidden Files vs Ignored Patterns
**The gotcha:** These are different systems with different behaviors  
**Why:** Hidden files are completely invisible, ignored shows as `[...]`  
**Solution:** Use hidden_files for secrets, ignored_patterns for build artifacts

## Build Gotchas

### Binary Size in Debug Mode
**The gotcha:** Debug binary is ~2x larger than Release  
**Why:** Debug symbols, no optimizations  
**Solution:** Always measure binary size with ReleaseFast build

### Benchmark Build Mode
**The gotcha:** Benchmarks run in whatever mode you built with  
**Why:** No automatic Release mode switching  
**Solution:** Build with `-Doptimize=ReleaseFast` for meaningful benchmarks

### Test Timeout
**The gotcha:** Some tests might timeout in CI but pass locally  
**Why:** CI machines might be slower, especially for stress tests  
**Solution:** Performance tests should adapt to system capabilities

## Memory Gotchas

### String Literals in Patterns
**The gotcha:** Pattern strings must outlive the pattern matcher  
**Why:** Patterns store pointers, not copies  
**Solution:** Use allocated strings or ensure literals have proper lifetime

### ArrayList Capacity After clear()
**The gotcha:** `list.clear()` keeps capacity, `list.deinit()` frees it  
**Why:** Zig's explicit memory management  
**Solution:** Use `clear()` for reuse, `deinit()` when done

### defer in Loops
**The gotcha:** `defer` runs at end of scope, not end of iteration  
**Why:** Zig scope rules  
**Solution:** Manual cleanup in loops or use block scope
```zig
for (items) |item| {
    const data = try allocator.alloc(u8, 100);
    // DON'T: defer allocator.free(data); // Leaks until loop ends
    
    // DO:
    process(data);
    allocator.free(data);
}
```

---

*If something took you more than 10 minutes to figure out, add it here.*
# TODO: Module Import Architecture Fix

## Problem Statement

The grammar and parser test modules cannot compile due to **module boundary violations** in Zig's import system. This has forced us to temporarily disable critical test coverage:

```zig
// _ = @import("grammar/test.zig"); // Temporarily disabled due to module import issues
// _ = @import("parser/test.zig"); // Temporarily disabled due to grammar import issues
```

**Impact:** ~150+ tests disabled, reduced coverage from 839 to 696 tests.

## Root Cause Analysis

### Grammar Module Issues

**File:** `src/lib/grammar/builder.zig` & `grammar.zig`

**Problem:** Cross-module imports that violate Zig's module boundaries:
```zig
// These imports fail when grammar module is tested in isolation
const TestRules = @import("../ast/rules.zig").TestRules;
const CommonRules = @import("../ast/rules.zig").CommonRules;
```

**Error:** `import of file outside module path: '../ast/rules.zig'`

**Why it fails:**
- When `zig test src/lib/grammar/test.zig` runs, grammar module boundary is `src/lib/grammar/`
- Cannot import from `src/lib/ast/` because it's outside the module path
- Zig enforces module isolation during testing for dependency safety

### Parser Module Dependencies

**File:** `src/lib/parser/detailed/parser.zig` & `test.zig`

**Problem:** Parser depends on grammar module:
```zig
const Grammar = @import("../../grammar/mod.zig").Grammar;
```

**Cascade failure:**
- Grammar module won't compile → Parser module can't import grammar → Parser tests fail
- All structural/lexical parser tests become unavailable

### Misleading Error Messages

The error `unable to load 'src/grammar/mod.zig': FileNotFound` is **misleading**:
- File exists at `src/lib/grammar/mod.zig` 
- Real issue: Grammar module has compilation errors due to import violations
- Zig reports this as "file not found" rather than "compilation failed"

## Solution Options

### Option 1: Relocate Shared Dependencies ⭐ **RECOMMENDED**

**Approach:** Move `ast/rules.zig` to a location accessible by all modules

**Implementation:**
```
src/lib/
├── core/
│   └── rules.zig        # Move here - accessible by all lib modules
├── grammar/             # Can import ../core/rules.zig  
├── ast/                 # Can import ../core/rules.zig
└── parser/              # Can import ../../core/rules.zig
```

**Pros:**
- Clean architecture - shared constants in shared location
- Maintains module boundaries
- Minimal import path changes
- No code duplication

**Cons:**
- Requires file move and update all import paths

### Option 2: Duplicate Constants

**Approach:** Copy needed constants into grammar module

**Implementation:**
```zig
// In src/lib/grammar/rules.zig
pub const CommonRules = enum(u16) {
    root = 0,
    object = 1,
    // ... duplicate from ast/rules.zig
};
```

**Pros:**
- No cross-module dependencies
- Quick fix

**Cons:**
- Code duplication - maintenance nightmare
- Constants can drift out of sync
- Violates DRY principle

### Option 3: Optional Dependencies

**Approach:** Make AST imports conditional for testing

**Implementation:**
```zig
const TestRules = if (@import("builtin").is_test) 
    TestRulesStub 
else 
    @import("../ast/rules.zig").TestRules;
```

**Pros:**
- Preserves existing architecture
- Tests can run with stubs

**Cons:**
- Complex conditional imports
- Tests don't use real implementations
- Potential for bugs in test vs production

### Option 4: Build System Configuration

**Approach:** Configure build.zig to allow cross-module imports for tests

**Implementation:**
```zig
// In build.zig - add module dependencies
const grammar_tests = b.addTest(.{
    .root_source_file = .{ .path = "src/lib/grammar/test.zig" },
});
grammar_tests.addModule("ast", ast_module);
```

**Pros:**
- Preserves existing code structure
- Proper dependency declaration

**Cons:**
- Build system complexity
- May not work with direct `zig test` commands

## Implementation Plan

### Phase 1: Core Rules Module Creation ⭐

1. **Create core module structure:**
   ```bash
   mkdir -p src/lib/core
   mv src/lib/ast/rules.zig src/lib/core/rules.zig
   ```

2. **Update all imports in affected files:**
   - `src/lib/grammar/builder.zig`: `../ast/rules.zig` → `../core/rules.zig`
   - `src/lib/grammar/grammar.zig`: `../ast/rules.zig` → `../core/rules.zig`  
   - `src/lib/ast/` files: `rules.zig` → `../core/rules.zig`
   - Any other files importing `ast/rules.zig`

3. **Update ast/mod.zig re-exports:**
   ```zig
   // Maintain compatibility
   pub const CommonRules = @import("../core/rules.zig").CommonRules;
   pub const TestRules = @import("../core/rules.zig").TestRules;
   ```

### Phase 2: Test Re-enablement

1. **Re-enable grammar tests:**
   ```zig
   _ = @import("grammar/test.zig"); // Re-enabled after core rules move
   ```

2. **Re-enable parser tests:**
   ```zig
   _ = @import("parser/test.zig"); // Re-enabled after grammar fix
   ```

3. **Verify full test suite:**
   ```bash
   zig build test  # Should run all ~839 tests
   ```

### Phase 3: Validation & Cleanup

1. **Confirm no regressions:**
   - All previously passing tests still pass
   - Grammar functionality unchanged
   - Parser functionality unchanged

2. **Remove temporary workarounds:**
   - Clean up any stub implementations
   - Remove temporary comments

3. **Update documentation:**
   - Update module architecture docs
   - Document new core/ module purpose

## Risk Assessment

### Low Risk ✅
- Moving `rules.zig` to `core/` - just constants, no logic
- Import path updates - mechanical changes

### Medium Risk ⚠️
- Build system integration - test carefully
- Dependency ordering during compilation

### High Risk ❌  
- None identified - this is a pure refactoring

## Testing Strategy

### Incremental Testing
1. **Test core module in isolation:**
   ```bash
   zig test src/lib/core/rules.zig
   ```

2. **Test grammar module after import fix:**
   ```bash
   zig test src/lib/grammar/test.zig
   ```

3. **Test parser module after grammar fix:**
   ```bash
   zig test src/lib/parser/test.zig
   ```

4. **Test full suite:**
   ```bash
   zig build test
   ```

### Rollback Plan
If issues arise:
1. Revert file move: `mv src/lib/core/rules.zig src/lib/ast/rules.zig`
2. Revert import changes using git
3. Re-disable problematic tests temporarily
4. Investigate alternative solution

## Success Criteria

- [ ] All 839 tests can run (no more disabled imports)
- [ ] Grammar tests pass: `zig test src/lib/grammar/test.zig`
- [ ] Parser tests pass: `zig test src/lib/parser/test.zig`  
- [ ] Main test suite: `zig build test` shows 839 tests
- [ ] No functional regressions in grammar or parser behavior
- [ ] Clean module boundaries maintained

## Implementation Notes

### File Changes Required

1. **New file:** `src/lib/core/rules.zig` (moved from `ast/rules.zig`)

2. **Import updates in:**
   - `src/lib/grammar/builder.zig`
   - `src/lib/grammar/grammar.zig`
   - `src/lib/ast/mod.zig` (add re-exports)
   - Any other files referencing `ast/rules.zig`

3. **Test re-enablement:**
   - `src/lib/test.zig` (uncomment disabled imports)

### Performance Impact
- **Minimal:** Only import path changes, no logic changes
- **Compilation:** Slightly faster due to cleaner dependencies
- **Runtime:** Zero impact - pure refactoring

## Future Architecture Improvements

### Module Organization
Consider extending `src/lib/core/` for other shared constants:
- Token types
- Error codes  
- Configuration enums

### Dependency Management
- Document module dependency graph
- Establish import conventions
- Add import cycle detection

This fix represents a critical architectural improvement that will restore full test coverage and establish cleaner module boundaries for future development.
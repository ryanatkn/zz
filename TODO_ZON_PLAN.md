# ZON Parsing Cleanup and Refactoring Plan

## Current State
- ✅ ZON parser successfully reads actual versions from deps.zon (no more hardcoded versions)
- ⚠️ Small memory leak in string allocation
- ⚠️ ZON parsing logic embedded in deps/config.zig
- ⚠️ extractFieldValue function hardcoded for specific fields

## Issues to Address

### 1. Memory Leak Fix
- Track allocated strings properly in parseFromZonContent
- Add cleanup function to free allocated strings
- Ensure consistent memory ownership model

### 2. Code Organization
- ZON parsing logic should be extracted from deps-specific code
- Make field extraction generic instead of hardcoded
- Consolidate with existing ZON infrastructure

## Proposed Solution: Extract ZON Language Module

### Create `/src/lib/languages/zon/`
Following the existing language module pattern:

```
src/lib/languages/zon/
├── parser.zig          # Text-based ZON parsing logic
├── extractor.zig       # Generic field extraction utilities  
├── formatter.zig       # ZON formatting (for zz format command)
├── patterns.zig        # ZON syntax patterns
├── test.zig           # Comprehensive ZON parsing tests
└── visitor.zig        # ZON AST traversal patterns
```

### Implementation Steps

#### Phase 1: Fix Memory Leak (Immediate)
1. Fix string allocation tracking in deps/config.zig
2. Add proper cleanup for allocated strings
3. Document memory ownership model

#### Phase 2: Extract ZON Module
1. Create `/src/lib/languages/zon/parser.zig`
   - Move parseFromZonContent logic from config.zig
   - Make field extraction generic
   - Proper memory management
   
2. Create `/src/lib/languages/zon/extractor.zig`
   - Generic extractFieldValue function
   - Support for any field name
   - Reusable across different ZON structures

3. Update deps/config.zig to use new ZON module

#### Phase 3: Integration and Testing
1. Integrate with existing ZonCore from lib/core/zon.zig
2. Add comprehensive tests
3. Consider adding ZON formatting to zz format command

## Benefits
- **Consistency**: Follows existing language module pattern
- **Reusability**: ZON parsing available for other config files
- **Maintainability**: Separation of concerns
- **Testing**: Isolated testing of ZON parsing logic
- **Future Features**: ZON formatting support

## Files to Modify
- `src/lib/deps/config.zig` - Fix memory leak, then refactor to use new module
- Create `src/lib/languages/zon/` directory and files
- Update imports in dependency management code
- Add tests for ZON parsing functionality

## Current Working State
The ZON parser correctly reads versions from deps.zon:
```
→ Would SKIP zig-tree-sitter (already v0.25.0)
→ Would SKIP tree-sitter (already v0.25.0)  
→ Would SKIP tree-sitter-css (already v0.23.0)
```

No longer shows incorrect "Would UPDATE ... to main" messages.
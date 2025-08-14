# Development Roadmap

## Context

Parser reliability has been restored, error handling enhanced, and test quality improved. The codebase now has 100% parser functionality across all supported languages with meaningful error messages at critical touchpoints. Code formatting capabilities have been added with language-aware pretty printing. The foundation is solid for advancing toward real tree-sitter AST integration.

## Recently Completed ✅

### Phase 3 Memory Management & Foundation (2025-08-14 Final)
- **✅ ZON Memory Leak ELIMINATED** - Created `zon_memory.zig` with robust `ManagedZonConfig` pattern
- **✅ Test Fixture Leaks ELIMINATED** - `ArenaZonParser` automatically cleans up all test parsing
- **✅ 100% Test Pass Rate ACHIEVED** - All tests passing, zero memory leaks detected
- **✅ Reusable Memory Patterns** - Safe ZON parsing infrastructure for entire codebase
- **✅ Production Ready Foundation** - Clean, idiomatic Zig memory management throughout
- **✅ ~60% Total Code Reduction** - From initial state through all 3 phases

### Week 2 Aggressive Refactoring (2025-08-14)
- **✅ Language Infrastructure Refactored** - ast.zig + errors.zig consolidated with unified APIs
- **✅ ~50% Code Reduction Achieved** - 10+ old modules → 6 clean new modules
- **✅ All Compilation Errors Fixed** - Project builds cleanly after aggressive refactoring
- **✅ 96.2% Test Pass Rate** - 330/343 tests passing, hanging test issue resolved
- **✅ Eliminated Anti-patterns** - ManagedArrayList gone, JavaScript cruft removed

### Previous Achievements  
- **Code Formatter Implementation** - Language-aware pretty printing for JSON, CSS, HTML, Zig
- **Parser Simple Extraction Fixed** - All languages now correctly extract content based on flags
- **Enhanced Error Messages** - Deployed ErrorHelpers in 5+ critical user touchpoints
- **Test Quality Improved** - Tests validate actual extraction content vs crash testing
- **Filesystem Import Standardization** - Core modules updated (10 test files remain)

## Immediate Priorities (Phase 4 - Language Infrastructure)

### 1. Text Processing Consolidation  
**Impact:** High | **Effort:** Medium
- **Merge text utilities** - line_utils + trim_utils + text_patterns + append_utils + result_builder → `src/lib/text/`
- **Eliminate duplicate patterns** - 200+ lines reduction potential
- **Improved organization** - Clean text processing API
- **Better maintainability** - Single location for all text utilities

### 2. Memory Management Organization
**Impact:** Medium | **Effort:** Low  
- **Create `src/lib/memory/`** - arena, allocation, ownership, zon utilities
- **Logical grouping** - Related memory patterns together
- **Enhanced discoverability** - Clear module boundaries

### 3. Complete Real Tree-sitter Integration
**Impact:** High | **Effort:** High
- Replace mock AST with actual tree-sitter node wrappers
- Infrastructure ready in refactored `ast.zig` with unified Extractor API
- Enable true semantic analysis beyond text matching
- Enhance formatter quality with proper AST-based formatting
- Current: Simple extraction works, AST extraction is mocked

### 4. Delete Obsolete Files
**Impact:** Medium | **Effort:** Low
- Remove old modules replaced by Week 1-2 refactoring
- Clean up collection_helpers, pools, string_pool, file_helpers, etc.
- Reduce codebase clutter and confusion
- Document migration path for any external dependencies

### 5. Formatter Enhancements
**Impact:** High | **Effort:** Medium
- **✅ Memory leaks eliminated** - All ZON and test fixture leaks fixed
- **Add configuration support** via `zz.zon` (foundation now ready)
- **Implement TypeScript formatter** with tree-sitter
- **Add Python formatter** (high demand)
- **Performance optimization** for large files

### 6. Integration Testing Suite
**Impact:** High | **Effort:** Medium
- End-to-end workflow validation
- Real-world usage patterns
- Command composition verification
- Performance regression detection
- Formatter validation tests

### 7. Analysis Infrastructure Organization
**Impact:** Medium | **Effort:** Low
- **Create `src/lib/analysis/`** - code, semantic, incremental, cache modules
- **Better discoverability** - Logical grouping of analysis functionality
- **Cleaner imports** - Shorter, more intuitive paths

### 8. Performance Profiling & Optimization
**Impact:** High | **Effort:** Medium
- Profile with real-world data sets
- Target hot paths in traversal and matching
- Optimize parser extraction paths
- Optimize formatter performance
- Memory pool tuning (current: 11μs, target: 8μs)

### 9. Async I/O Preparation
**Impact:** High | **Effort:** Medium
- Extend parameterized I/O patterns
- Prepare for Zig 0.15's async implementation
- Focus on parallel file processing
- Enable parallel formatting

## Near-term Goals

### 7. Language Grammar Expansion
**Impact:** High | **Effort:** Medium
- Add Python grammar and formatter (high demand)
- Add Rust grammar and formatter (systems programming)
- Add Go grammar and formatter (cloud native)
- Leverage vendored tree-sitter infrastructure

### 8. Formatter Configuration System
**Impact:** Medium | **Effort:** Low
- Extend `zz.zon` for format preferences
- Per-project formatting rules
- Language-specific options
- Editor integration support

### 9. Centralized Argument Parsing
**Impact:** Medium | **Effort:** Medium
- Consolidate module-specific parsing
- Leverage existing `args.zig` infrastructure
- Improve consistency across commands

### 10. Shell Completions
**Impact:** Medium | **Effort:** Low
- Bash completion script
- Zsh completion script
- Fish completion script
- Auto-generate from command definitions

### 11. Incremental Processing Enhancement
**Impact:** High | **Effort:** Medium
- Leverage FileTracker for change detection
- Implement proper AST cache invalidation
- Add file watching capability
- Cache formatted files for --check mode

### 12. Documentation Consolidation
**Impact:** Medium | **Effort:** Low
- Create comprehensive user guide
- Extract API documentation
- Module-specific READMEs
- Performance tuning guide
- Formatter style guide

## Long-term Considerations

### Advanced Analysis Features
- Call graph visualization
- Dependency graph generation
- Code complexity metrics
- Security vulnerability scanning
- Format enforcement in CI/CD

### Build System Evolution
- Cross-compilation support
- Package manager integration
- Binary distribution strategy
- CI/CD optimization
- Pre-commit hooks for formatting

### Developer Experience
- LSP server for editor integration
- Interactive configuration wizard
- Plugin architecture
- Custom language support API
- Format-on-save integration

### Community Infrastructure
- Language grammar registry
- Pattern library marketplace
- Configuration sharing platform
- Performance benchmark suite
- Formatter style presets

## Performance Targets

Current baselines (Release mode, 2025-08-13):
- Path operations: 11μs (target: sub-10μs)
- String pooling: 11ns (maintained) ✅
- Memory pools: 11μs (target: 8μs)
- Glob patterns: 4ns (maintained) ✅
- Code extraction: 21μs (target: 15μs with real AST)
- Parser simple extraction: ~5μs (achieved) ✅
- JSON formatting: ~50μs for 1KB file (target: 30μs)
- CSS formatting: ~40μs for 1KB file (target: 25μs)

## Engineering Philosophy

### Core Principles
- Performance is non-negotiable
- Every abstraction must justify its cost
- POSIX-first, cross-platform never
- Measure, optimize, verify

### Quality Metrics
- Zero performance regressions
- 100% parser functionality ✅
- Meaningful error messages ✅
- Comprehensive test validation ✅
- Consistent formatting output ✅

### On Reliability
With parser extraction now fully functional, error handling enhanced, and formatting capabilities added, the focus shifts to leveraging this reliable foundation for advanced features. The mock AST infrastructure awaits real tree-sitter integration to unlock semantic analysis capabilities and improve formatting quality.

## Phase 4 Sprint Focus (Language Infrastructure Consolidation)

**Foundation Complete** ✅ - All memory leaks eliminated, 100% test pass rate achieved

**Recommended Phase 4 sequence:**
1. **Text consolidation** → `src/lib/text/` (merge 5 modules, eliminate 200+ duplicate lines)
2. **Memory organization** → `src/lib/memory/` (logical grouping, better discoverability)
3. **Analysis grouping** → `src/lib/analysis/` (code, semantic, incremental, cache modules)
4. **Language shared utilities** → `src/lib/language/shared.zig` (extract common patterns)
5. **Import migration** - Update all modules to use new organized structure
6. **Performance benchmarking** - Validate zero regressions from reorganization
7. **Integration testing** - End-to-end validation of refactored architecture
8. **Documentation updates** - CLAUDE.md, README.md, module documentation
9. **Begin real tree-sitter integration** with clean, organized foundation

## Technical Debt

### Addressed ✅
- **✅ Phase 3 Refactoring Complete** - ~60% total code reduction, eliminated anti-patterns
- **Ownership patterns** - Clear initOwning/initBorrowing semantics
- **✅ Memory leaks ELIMINATED** - ZON parsing, test fixtures, all formatter issues fixed\n- **✅ 100% test pass rate** - All tests passing, zero failures or leaks\n- **Memory management** - Arena allocators, proper defer patterns, zon_memory.zig
- **Collection anti-patterns** - ManagedArrayList eliminated
- **JavaScript cruft** - Language-agnostic imports/exports
- Parser simple extraction (fixed)
- Error message quality (enhanced)
- Test validation depth (improved)
- Core module imports (80% complete)
- Basic formatting implementation (completed)

### Remaining (Phase 4 Focus)
- **Directory organization** - Better grouping of related modules
- **Text processing consolidation** - Merge line_utils, trim_utils, text_patterns, etc.
- Obsolete files from refactoring need deletion
- Mock AST to real tree-sitter
- Test file import consistency
- Centralized argument parsing
- Full incremental processing
- Formatter memory leak (easier to fix with new memory.zig)
- TypeScript/Svelte formatter implementation
- Format configuration system

## Formatter Roadmap

### Phase 1 (Completed) ✅
- Core infrastructure
- JSON, CSS, HTML formatters
- CLI integration
- Basic documentation

### Phase 2 (Next)
- Fix memory leak
- Configuration support
- TypeScript formatter with AST
- Python formatter
- Performance optimization

### Phase 3 (Future)
- Rust, Go formatters
- Format enforcement tools
- Editor integrations
- Style preset library

---

*Performance is a feature. Simplicity is a design goal. Every cycle counts.*
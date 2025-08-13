# Development Roadmap

## Context

Parser reliability has been restored, error handling enhanced, and test quality improved. The codebase now has 100% parser functionality across all supported languages with meaningful error messages at critical touchpoints. The foundation is solid for advancing toward real tree-sitter AST integration.

## Recently Completed ✅

- **Parser Simple Extraction Fixed** - All languages now correctly extract content based on flags
- **Enhanced Error Messages** - Deployed ErrorHelpers in 5+ critical user touchpoints
- **Test Quality Improved** - Tests validate actual extraction content vs crash testing
- **Filesystem Import Standardization** - Core modules updated (10 test files remain)

## Immediate Priorities

### 1. Complete Real Tree-sitter Integration
**Impact:** High | **Effort:** High
- Replace mock AST with actual tree-sitter node wrappers
- Infrastructure exists in `ast.zig`, needs real implementation
- Enable true semantic analysis beyond text matching
- Current: Simple extraction works, AST extraction is mocked

### 2. Integration Testing Suite
**Impact:** High | **Effort:** Medium
- End-to-end workflow validation
- Real-world usage patterns
- Command composition verification
- Performance regression detection

### 3. Complete Filesystem Import Migration
**Impact:** Low | **Effort:** Low
- 10 test files still use old `filesystem.zig` imports
- Update to `filesystem/interface.zig` for consistency
- Simple mechanical refactor

### 4. Performance Profiling & Optimization
**Impact:** High | **Effort:** Medium
- Profile with real-world data sets
- Target hot paths in traversal and matching
- Optimize parser extraction paths
- Memory pool tuning (current: 11μs, target: 8μs)

### 5. Async I/O Preparation
**Impact:** High | **Effort:** Medium
- Extend parameterized I/O patterns
- Prepare for Zig 0.15's async implementation
- Focus on parallel file processing

## Near-term Goals

### 6. Language Grammar Expansion
**Impact:** High | **Effort:** Medium
- Add Python grammar (high demand)
- Add Rust grammar (systems programming)
- Add Go grammar (cloud native)
- Leverage vendored tree-sitter infrastructure

### 7. Centralized Argument Parsing
**Impact:** Medium | **Effort:** Medium
- Consolidate module-specific parsing
- Leverage existing `args.zig` infrastructure
- Improve consistency across commands

### 8. Shell Completions
**Impact:** Medium | **Effort:** Low
- Bash completion script
- Zsh completion script
- Fish completion script
- Auto-generate from command definitions

### 9. Incremental Processing Enhancement
**Impact:** High | **Effort:** Medium
- Leverage FileTracker for change detection
- Implement proper AST cache invalidation
- Add file watching capability

### 10. Documentation Consolidation
**Impact:** Medium | **Effort:** Low
- Create comprehensive user guide
- Extract API documentation
- Module-specific READMEs
- Performance tuning guide

## Long-term Considerations

### Advanced Analysis Features
- Call graph visualization
- Dependency graph generation
- Code complexity metrics
- Security vulnerability scanning

### Build System Evolution
- Cross-compilation support
- Package manager integration
- Binary distribution strategy
- CI/CD optimization

### Developer Experience
- LSP server for editor integration
- Interactive configuration wizard
- Plugin architecture
- Custom language support API

### Community Infrastructure
- Language grammar registry
- Pattern library marketplace
- Configuration sharing platform
- Performance benchmark suite

## Performance Targets

Current baselines (Release mode, 2025-01-14):
- Path operations: 11μs (target: sub-10μs)
- String pooling: 11ns (maintained) ✅
- Memory pools: 11μs (target: 8μs)
- Glob patterns: 4ns (maintained) ✅
- Code extraction: 21μs (target: 15μs with real AST)
- Parser simple extraction: ~5μs (achieved) ✅

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

### On Reliability
With parser extraction now fully functional and error handling enhanced, the focus shifts to leveraging this reliable foundation for advanced features. The mock AST infrastructure awaits real tree-sitter integration to unlock semantic analysis capabilities.

## Next Sprint Focus

**Recommended sequence:**
1. Complete filesystem import migration (quick win)
2. Build integration test suite (validate current state)
3. Begin real tree-sitter integration (high value)
4. Profile and optimize hot paths (performance)
5. Add Python language support (user demand)

## Technical Debt

### Addressed ✅
- Parser simple extraction (fixed)
- Error message quality (enhanced)
- Test validation depth (improved)
- Core module imports (80% complete)

### Remaining
- Mock AST to real tree-sitter
- Test file import consistency
- Centralized argument parsing
- Full incremental processing

---

*Performance is a feature. Simplicity is a design goal. Every cycle counts.*
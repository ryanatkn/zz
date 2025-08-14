# TODO: Comprehensive Svelte Formatter Test Suite

## Objective
Create a complete test suite for Svelte code formatting that methodically covers all Svelte 5 language features, syntax patterns, and edge cases. This will ensure our formatter handles the full breadth of modern Svelte development patterns.

## Context Documentation
Reference: `src/docs/llms/svelte-llms-small.txt` - Contains comprehensive Svelte 5 API documentation including:
- All runes: `$state`, `$derived`, `$effect`, `$props`, `$bindable`, `$host`
- Advanced patterns: `$state.raw`, `$state.snapshot`, `$derived.by`, `$effect.pre`, etc.
- Event handling changes (no colons: `onclick` vs `on:click`)
- Async/await experimental features
- Component patterns and best practices

## Test Categories to Implement

### 1. **Rune Formatting**
Test proper formatting of all Svelte 5 runes:

#### $state Runes
- Basic state: `let count = $state(0);`
- Object state: `let user = $state({ name: 'John', age: 30 });`
- Array state: `let items = $state([1, 2, 3]);`
- Class field state: `class Todo { done = $state(false); }`
- Raw state: `let person = $state.raw({ name: 'Test' });`
- Snapshot usage: `$state.snapshot(counter)`

#### $derived Runes
- Simple derived: `const doubled = $derived(count * 2);`
- Complex derived with $derived.by: Multi-line logic blocks
- Overridable derived values for optimistic UI
- Nested derivations and dependencies

#### $effect Runes
- Basic effects: `$effect(() => console.log(size));`
- Effects with cleanup: Return functions, interval management
- Pre-effects: `$effect.pre(() => { /* before DOM */ });`
- Root effects: `$effect.root(() => { /* manual cleanup */ });`
- Tracking detection: `$effect.tracking()`

#### $props Runes
- Basic destructuring: `let { adjective } = $props();`
- Default values: `let { adjective = 'happy' } = $props();`
- Renamed props: `let { super: trouper } = $props();`
- Rest syntax: `let { a, b, ...others } = $props();`
- Unique IDs: `const uid = $props.id();`

#### $bindable Runes
- Bindable props: `let { value = $bindable() } = $props();`
- Two-way data flow patterns
- Complex bindable scenarios

#### $host Runes
- Custom element dispatching
- Host element access patterns

### 2. **Modern Event Handling**
Test formatting of Svelte 5 event syntax:
- `onclick={handler}` vs old `on:click={handler}`
- Inline event handlers: `onclick={() => count++}`
- Complex event expressions
- Event delegation patterns

### 3. **Component Structure Formatting**
Test formatting of complete component patterns:

#### Script Sections
- Import statements organization
- Rune declarations and grouping
- Function definitions
- Class definitions with reactive fields
- Mixed rune patterns in single components

#### Style Sections
- CSS custom properties with runes
- Responsive design patterns
- Style encapsulation formatting

#### Template Sections  
- Control flow blocks: `{#if}`, `{#each}`, `{#await}`
- Slot usage and snippet definitions
- Component composition patterns
- Conditional rendering with runes

### 4. **Advanced Patterns**
Test complex real-world scenarios:

#### Async/Await (Experimental)
- Top-level await in script
- Await in derived expressions
- Inline await in markup
- Boundary components with pending snippets
- Configuration requirements

#### Reactive Patterns
- State synchronization between components
- Complex dependency chains
- Optimistic UI implementations
- Error boundaries and recovery

#### Performance Patterns
- State optimization techniques
- Effect cleanup patterns
- Memory management with runes

### 5. **Integration Scenarios**
Test formatting in complex component interactions:

#### Parent-Child Communication
- Props passing with new syntax
- Bindable prop usage
- Event bubbling patterns
- Context API integration

#### State Management
- Global state patterns with runes
- Store integration (if applicable)
- Cross-component synchronization

### 6. **Edge Cases and Error Scenarios**
Test formatter robustness:

#### Syntax Edge Cases
- Incomplete rune expressions
- Malformed event handlers
- Missing destructuring patterns
- Complex nested expressions

#### Formatting Challenges
- Very long rune expressions
- Deep nesting scenarios
- Mixed spaces and tabs
- Unicode and special characters

#### Error Recovery
- Partial syntax trees
- Interrupted parsing
- Invalid rune usage

## Implementation Strategy

### Phase 1: Core Rune Formatting
1. Create test fixtures for each rune type
2. Implement basic formatting rules
3. Establish indentation and spacing standards
4. Test with simple examples

### Phase 2: Complex Patterns
1. Add multi-line expression handling
2. Implement proper nesting and alignment
3. Handle component composition scenarios
4. Test edge cases and malformed input

### Phase 3: Integration Testing
1. Create full component examples
2. Test formatter on real-world scenarios
3. Performance testing with large files
4. Integration with existing toolchain

### Phase 4: Validation and Refinement
1. Compare output with community standards
2. Test against popular Svelte projects
3. Gather feedback and iterate
4. Document formatting decisions

## File Structure
```
src/lib/test/fixtures/svelte/
├── runes/
│   ├── state.test.zon          # $state variants
│   ├── derived.test.zon        # $derived patterns  
│   ├── effect.test.zon         # $effect scenarios
│   ├── props.test.zon          # $props handling
│   └── bindable.test.zon       # $bindable usage
├── events/
│   ├── handlers.test.zon       # Modern event syntax
│   └── inline.test.zon         # Inline expressions
├── components/
│   ├── basic.test.zon          # Simple components
│   ├── complex.test.zon        # Real-world examples
│   └── async.test.zon          # Experimental async
├── integration/
│   ├── parent_child.test.zon   # Component communication
│   └── state_management.test.zon # Global patterns
└── edge_cases/
    ├── malformed.test.zon      # Error scenarios
    └── performance.test.zon    # Large files
```

## Success Criteria
- [ ] 100% coverage of Svelte 5 rune syntax
- [ ] Proper formatting of all event handling patterns  
- [ ] Consistent indentation and spacing rules
- [ ] Robust error handling for malformed input
- [ ] Performance testing with large component files
- [ ] Integration with existing test infrastructure
- [ ] Documentation of formatting decisions and rationale

## Timeline Estimate
- **Week 1**: Core rune formatting implementation
- **Week 2**: Complex patterns and component structure
- **Week 3**: Integration scenarios and edge cases
- **Week 4**: Validation, refinement, and documentation

## Dependencies
- Existing Svelte extractor in `src/lib/languages/svelte/`
- Test fixture system in `src/lib/test/fixtures/`
- Formatter infrastructure in `src/lib/formatters/svelte.zig`
- Reference documentation in `docs/llms/svelte-llms-small.txt`

## Related Work
This builds on the completed language restructure and Svelte extractor implementation. The formatter will complement the existing extraction capabilities by providing production-ready code formatting for all Svelte 5 patterns.
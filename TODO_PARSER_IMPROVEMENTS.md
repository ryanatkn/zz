# Parser Integration Improvements - Format Module

This document tracks the integration of FormatterOptions with the stratified parser system in the format module.

## Current Issue

The format module currently ignores user-provided formatting options when using the stratified parser. Two locations have TODO comments indicating this:

### Locations Needing Fix:

1. **`/src/format/main.zig:176`** - `processFile()` function
   ```zig
   fn processFile(allocator: std.mem.Allocator, filesystem: FilesystemInterface, file_path: []const u8, write: bool, check: bool, options: FormatterOptions) !bool {
       _ = options; // TODO: Use options in stratified parser formatting
   ```

2. **`/src/format/main.zig:334`** - `formatStdin()` function
   ```zig
   fn formatStdin(allocator: std.mem.Allocator, options: FormatterOptions) !void {
       _ = options; // TODO: Use options in stratified parser formatting
   ```

## Impact

**User Impact:** High - Format options specified by users (indent size, style, line width, etc.) are currently ignored when files are processed through the stratified parser path.

**Affected Options:**
- `indent_size` - Number of spaces/tabs for indentation
- `indent_style` - Space vs tab indentation  
- `line_width` - Maximum line width for formatting
- `preserve_newlines` - Whether to preserve existing newlines
- `trailing_comma` - Whether to add trailing commas
- `sort_keys` - Whether to sort object keys
- `quote_style` - Single, double, or preserve quotes
- `use_ast` - Whether to use AST-based formatting

## Technical Details

### Current Flow:
1. User provides format options via CLI args or config file
2. Options are parsed and validated
3. `processFile()` or `formatStdin()` is called with options
4. **Options are ignored** - stratified parser uses defaults
5. Formatted output doesn't match user expectations

### Required Integration Points:

1. **Stratified Parser Interface:**
   - `formatWithStratifiedParser()` function needs options parameter
   - Individual language formatters need to consume options
   - AST transformation layer needs formatting configuration

2. **Configuration Propagation:**
   - Options must flow from CLI → processFile/formatStdin → stratified parser → language formatters
   - Language-specific option validation and application

3. **Language Support:**
   - JSON formatter needs indent_size, indent_style, line_width, trailing_comma, sort_keys
   - CSS formatter needs indent_size, indent_style, preserve_newlines  
   - HTML formatter needs indent_size, indent_style
   - ZON formatter needs all options

## Implementation Plan

### Phase 1: Core Integration
1. **Update stratified parser interface** to accept FormatterOptions
2. **Modify formatWithStratifiedParser()** function signature
3. **Update language formatter interfaces** to consume options
4. **Remove the TODO comments** after integration

### Phase 2: Language-Specific Features  
1. **JSON formatter** - implement all supported options
2. **CSS formatter** - implement indentation and newline handling
3. **HTML formatter** - implement indentation options
4. **ZON formatter** - full option support matching JSON

### Phase 3: Validation & Testing
1. **Add integration tests** verifying options are applied correctly
2. **Test option combinations** for consistency
3. **Performance testing** to ensure option processing doesn't degrade performance
4. **Documentation updates** reflecting new option support

## Dependencies

- **Stratified Parser Architecture** - Must support configuration injection
- **Language Formatter Interfaces** - Need standardized option consumption
- **AST Infrastructure** - Formatting transformations need option awareness

## Priority: High

This affects core user experience - users expect format options to work. The infrastructure exists, it just needs proper integration.

## Related Files

- `/src/format/main.zig` - Main integration points
- `/src/lib/formatter.zig` - Core formatter infrastructure  
- `/src/lib/formatters/*.zig` - Language-specific formatters
- `/src/format/test/` - Integration tests needed
- Configuration files in `/src/config/` - Option loading

---

**Note:** This is tracked separately from immediate cleanup tasks. Focus on error recovery, Unicode tests, and error handling consistency first, then tackle this integration work in a dedicated session.
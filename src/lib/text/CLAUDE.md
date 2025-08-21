# Text Module - Text Processing and Manipulation

## Overview
Comprehensive text processing utilities for parsing, formatting, and manipulating text content. Complements the char module for higher-level operations. Works alongside stream-first modules for text analysis.

## Module Structure

```
src/lib/text/
├── delimiters.zig      # Delimiter tracking and balanced parsing
├── processing.zig      # Line processing and text utilities  
├── builders.zig        # StringBuilder utilities
├── formatting.zig      # Format utilities (ANSI stripping, etc.)
└── line_processing.zig # Line-based operations
```

## Delimiters (`delimiters.zig`)

**Purpose:** Track and parse balanced delimiters in language-agnostic way

### DelimiterTracker
Maintains state for nested delimiter tracking:
```zig
var tracker = DelimiterTracker{};
for (text) |char| {
    tracker.trackChar(char);
    if (tracker.isTopLevel()) {
        // At top level, not inside any delimiters
    }
}
```

### Key Functions
```zig
// Count character occurrences
countChar(text, '{')                     // Returns usize

// Count balance of delimiters  
countBalance(text, '{', '}')             // Returns i32

// Find matching closing delimiter
findMatchingDelimiter(text, pos, '{', '}')  // Returns ?usize

// Extract content between delimiters
extractBetween(text, "<", ">")           // Simple extraction
extractBetweenDelimiters(text, '{', '}') // Balanced extraction
extractAllBetween(allocator, text, "[", "]") // Find all occurrences

// Split respecting nesting
splitRespectingNesting(allocator, "a,b,(c,d),e", ',')  
// Returns: ["a", "b", "(c,d)", "e"]
```

### IndentationHelper
Format code with proper indentation:
```zig
const formatted = try IndentationHelper.formatIndentedBlock(
    allocator, content, 4
);

const level = IndentationHelper.countIndentLevel(line, 4);
```

## Processing (`processing.zig`)

**Purpose:** High-level text processing and pattern matching

### Pattern Matching
```zig
// Check for multiple patterns
startsWithAny(line, &.{"import", "export", "const"})
containsAny(text, &.{"TODO", "FIXME", "HACK"})

// Comment detection
isComment(line, .c_style)   // Checks for //, /*, *
isComment(line, .hash)      // Checks for #
isComment(line, .html)      // Checks for <!--
```

### Line Processing
```zig
// Process lines with callback
processLines(content, printLine);

// Process with state
processLinesWithState(*MyState, content, state, processLine);

// Split and trim
const parts = try splitAndTrim(allocator, "a, b, c", ',');
// Returns: ["a", "b", "c"]
```

### Text Extraction
```zig
// Extract sections
const sections = try extractSections(allocator, content, "## ");

// Filter lines
const filtered = try filterLines(allocator, content, predicate);
```

## Builders (`builders.zig`)

**Purpose:** Efficient string building with formatting

### StringBuilder
```zig
var builder = StringBuilder.init(allocator);
defer builder.deinit();

try builder.append("Hello");
try builder.appendFmt(" {s}!", .{"World"});
try builder.appendIndented(4, "indented text");
try builder.appendLines(&.{"line1", "line2"});

const result = try builder.toOwnedSlice();
```

### Features
- Automatic capacity management
- Format string support
- Indentation helpers
- Line joining utilities

## Formatting (`formatting.zig`)

**Purpose:** Text formatting and cleaning utilities

### ANSI Code Handling
```zig
// Strip ANSI escape codes
const clean = try stripAnsiCodes(allocator, colored_text);

// Format for README
const markdown = try formatForReadme(allocator, demo_output);
// Wraps in ```console block and strips colors
```

### Format Options
```zig
const options = FormatOptions{
    .strip_colors = true,
    .markdown_code_blocks = true,
    .max_line_width = 80,
    .indent_size = 2,
};
```

## Line Processing (`line_processing.zig`)

**Purpose:** Advanced line-based text operations

### Line Operations
```zig
// Count lines
const count = countLines(text);

// Get line at position
const line = getLineAt(text, pos);

// Get line range
const lines = getLineRange(text, start_line, end_line);

// Join lines
const joined = try joinLines(allocator, lines, ", ");
```

### Line Transformations
```zig
// Map over lines
const mapped = try mapLines(allocator, text, toUpperCase);

// Filter empty lines
const non_empty = try filterEmptyLines(allocator, text);

// Deduplicate lines
const unique = try deduplicateLines(allocator, text);
```

## Performance Characteristics

- **Delimiter tracking:** O(n) single pass
- **Pattern matching:** O(n*m) where m is pattern count
- **Line processing:** O(n) with minimal allocations
- **StringBuilder:** Amortized O(1) append
- **ANSI stripping:** O(n) single pass

## Integration with Stream-First Architecture

### Relationship to Core Modules
- **Span Module**: Text operations produce spans for fact subjects
- **Token Module**: Delimiter tracking assists tokenization
- **Stream Module**: Line processing can be streamed
- **Fact Module**: Text patterns become facts (e.g., has_text predicate)

### Usage in Stream Pipeline
```zig
// Text processing in streaming context
var line_stream = LineStream.init(text);
while (try line_stream.next()) |line| {
    const trimmed = processing.trim(line);
    const span = Span.init(line.start, line.end);
    // Generate facts about the line
}
```

## Usage Examples

### Parse Nested Structure
```zig
const delimiters = @import("text/delimiters.zig");

var tracker = delimiters.DelimiterTracker{};
for (json_text) |char| {
    tracker.trackChar(char);
    if (char == ',' and tracker.totalDepth() == 1) {
        // Found comma at object root level
    }
}
```

### Extract Code Blocks
```zig
const processing = @import("text/processing.zig");
const delimiters = @import("text/delimiters.zig");

// Extract all code blocks from markdown
const blocks = try delimiters.extractAllBetween(
    allocator, markdown, "```", "```"
);

// Check if they're code
for (blocks.items) |block| {
    if (processing.startsWithAny(block, &.{"zig", "typescript", "json"})) {
        // Process language-specific block
    }
}
```

### Build Formatted Output
```zig
const builders = @import("text/builders.zig");

var output = builders.StringBuilder.init(allocator);
defer output.deinit();

try output.appendLine("## Results");
try output.appendLine("");
for (results) |result| {
    try output.appendFmt("- {s}: {d}ms\n", .{result.name, result.time});
}

const report = try output.toOwnedSlice();
```

## Integration with Other Modules

- **char module:** Text module uses char for character classification
- **patterns module:** Works with glob/gitignore for file filtering
- **languages modules:** Provides text utilities for parsers/formatters
- **AST module:** Delimiter tracking helps with AST construction

## Migration from Legacy

**Before (scattered utilities):**
```zig
// In various files
fn stripWhitespace(text: []const u8) []const u8 { ... }
fn countBraces(text: []const u8) i32 { ... }
fn extractBetween(text: []const u8, start: usize, end: usize) []const u8 { ... }
```

**After (text module):**
```zig
const text = @import("lib/text/mod.zig");

const clean = text.processing.trim(input);
const balance = text.delimiters.countBalance(input, '{', '}');
const content = text.delimiters.extractBetween(input, "<", ">");
```

## Best Practices

1. **Use DelimiterTracker** for parsing nested structures
2. **Prefer StringBuilder** over manual concatenation
3. **Process lines lazily** when possible
4. **Cache compiled patterns** for repeated use
5. **Use appropriate module:**
   - char: Single character operations
   - text: Multi-character operations
   - patterns: File path patterns

## Future Enhancements

1. **Rope data structure** for large text editing
2. **Incremental processing** for editor integration
3. **SIMD optimizations** for pattern matching
4. **Streaming API** for large files
5. **Unicode support** beyond ASCII

The text module provides the foundation for all text manipulation in zz, complementing the char module for comprehensive text processing capabilities.
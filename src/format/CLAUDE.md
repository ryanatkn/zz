# Format Module - Code Formatting System

Language-aware code formatting with configurable styles and multiple output modes.

## Design Philosophy

**Simplicity First:**
- Leverage existing tools where available (e.g., `zig fmt`)
- Native implementations for common formats (JSON, CSS, HTML)
- Graceful fallback for unsupported languages
- Consistent interface across all formatters

**Clean Architecture:**
- **Core Infrastructure**: `src/lib/formatter.zig` - Language dispatch and utilities
- **Language Formatters**: `src/lib/formatters/` - Per-language implementations
- **CLI Integration**: `src/format/main.zig` - Command handling and file processing
- **Shared Utilities**: LineBuilder for efficient string construction

## Module Structure

```
└── format
    └── main.zig               # CLI entry point and file processing
    
└── lib
    ├── formatter.zig          # Core infrastructure and language dispatch
    └── formatters/            # Language-specific formatters
        ├── json.zig           # JSON formatter with smart line-breaking
        ├── css.zig            # CSS rule and property formatting
        ├── html.zig           # HTML tag indentation
        ├── zig.zig            # External zig fmt integration
        ├── typescript.zig     # TypeScript placeholder
        └── svelte.zig         # Svelte placeholder
```

## Language Support

### JSON Formatter
**Features:**
- Smart single-line vs multi-line decisions
- Configurable indentation (spaces/tabs)
- Optional trailing commas
- Key sorting capability
- Proper string escaping

**Implementation:**
- Uses `std.json` for parsing
- Custom pretty-printing with LineBuilder
- Heuristics for line-breaking based on content size

### CSS Formatter
**Features:**
- Selector formatting
- Property alignment with consistent spacing
- Media query indentation
- Comment preservation
- Brace style consistency

**Implementation:**
- Simple state machine for parsing
- Handles strings and comments correctly
- Collapses redundant whitespace

### HTML Formatter
**Features:**
- Tag indentation
- Attribute formatting
- Preserves content in `<pre>` tags
- Self-closing tag detection
- Configurable indentation

**Implementation:**
- Line-based processing
- Auto-indent/dedent based on tag types
- Special handling for void elements

### Zig Formatter
**Features:**
- Delegates to external `zig fmt` command
- Handles temporary file creation
- Fallback to original on error

**Implementation:**
- Uses `std.process.Child.run` for external command
- Temporary file handling for stdin-like behavior

## Configuration

**FormatterOptions Structure:**
```zig
pub const FormatterOptions = struct {
    indent_size: u8 = 4,
    indent_style: IndentStyle = .space,
    line_width: u32 = 100,
    preserve_newlines: bool = true,
    trailing_comma: bool = false,
    sort_keys: bool = false,
    quote_style: enum { single, double, preserve } = .preserve,
};
```

**Future Configuration via zz.zon:**
```zon
.format = .{
    .indent_size = 4,
    .indent_style = "space",
    .line_width = 100,
    .trailing_comma = false,
    .sort_keys = false,
}
```

## CLI Integration

**Command Structure:**
```bash
zz format [files...] [options]
```

**Options:**
- `--write, -w`: Format files in-place
- `--check`: Check if files are formatted (exit 1 if not)
- `--stdin`: Read from stdin, write to stdout
- `--indent-size=N`: Number of spaces for indentation
- `--indent-style=space|tab`: Indentation style
- `--line-width=N`: Maximum line width

**File Processing:**
1. Glob pattern expansion via GlobExpander
2. Language detection from file extension
3. Format with appropriate formatter
4. Output to stdout or write in-place

## LineBuilder Utility

**Purpose:** Efficient string building with indentation management

**Features:**
- Automatic indentation tracking
- Line width calculations
- Memory-efficient append operations
- Configurable indent strings

**API:**
```zig
pub const LineBuilder = struct {
    pub fn init(allocator, options) LineBuilder
    pub fn indent(self: *LineBuilder) void
    pub fn dedent(self: *LineBuilder) void
    pub fn appendIndent(self: *LineBuilder) !void
    pub fn append(self: *LineBuilder, text: []const u8) !void
    pub fn newline(self: *LineBuilder) !void
    pub fn shouldBreakLine(self: *LineBuilder, additional_length: u32) bool
    pub fn toOwnedSlice(self: *LineBuilder) ![]const u8
};
```

## Error Handling

**FormatterError Types:**
- `UnsupportedLanguage`: Unknown file type
- `InvalidSource`: Malformed input
- `FormattingFailed`: Generic formatting error
- `ExternalToolNotFound`: Missing external formatter
- `OutOfMemory`: Allocation failure

**Graceful Degradation:**
- Return original source on parse errors
- Fall back to basic formatting on complex structures
- Clear error messages for user feedback

## Usage Examples

```bash
# Format JSON file
zz format config.json

# Format in-place
zz format config.json --write

# Check formatting
zz format "src/**/*.json" --check

# Format from stdin
echo '{"a":1}' | zz format --stdin

# Custom indentation
zz format style.css --indent-size=2

# Format multiple file types
zz format "src/**/*.{json,css,html}"
```

## Performance Characteristics

- **JSON**: ~50μs for 1KB file
- **CSS**: ~40μs for 1KB file
- **HTML**: ~30μs for 1KB file
- **Zig**: External command overhead (~10ms)

## Known Issues

- Minor memory leak in glob expansion (tracked)
- TypeScript/Svelte formatters are placeholders
- No configuration file support yet

## Future Enhancements

### Phase 2 (Next)
- Fix memory leak
- Add configuration file support
- Implement TypeScript formatter with tree-sitter
- Add Python formatter

### Phase 3 (Future)
- Rust, Go formatters
- Editor integration support
- Format-on-save hooks
- Style preset library

## Development Notes

**Adding a New Formatter:**
1. Create `src/lib/formatters/language.zig`
2. Implement `format(allocator, source, options) ![]const u8`
3. Add language to `Language` enum in `parser.zig`
4. Add case in `formatter.zig` dispatch
5. Update help text and documentation

**Testing:**
- Unit tests for each formatter
- Round-trip tests (format twice = same result)
- Edge cases: empty files, malformed input
- Performance benchmarks

**Code Quality:**
- Zero panics - handle all errors gracefully
- Memory safety with proper cleanup
- Consistent style across formatters
- Clear separation of concerns
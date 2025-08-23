const std = @import("std");
const collections = @import("../lib/core/collections.zig");
const path_utils = @import("../lib/core/path.zig");
const reporting = @import("../lib/core/reporting.zig");

// Filesystem
const filesystem = @import("../lib/filesystem/interface.zig");

// Core modules
const language_mod = @import("../lib/core/language.zig");
const args_mod = @import("../lib/args.zig");

// Configuration
const shared_config = @import("../config/shared.zig");
const zon_config = @import("../config/zon.zig");

// Language and transformation
const json_transform = @import("../lib/languages/json/transform.zig");
const zon_transform = @import("../lib/languages/zon/transform.zig");
const language_interface = @import("../lib/languages/interface.zig");

// Stream-first architecture
const stream_format = @import("../lib/stream/format.zig");
const JsonStreamLexer = @import("../lib/languages/json/stream_lexer.zig").JsonStreamLexer;
const ZonStreamLexer = @import("../lib/languages/zon/stream_lexer.zig").ZonStreamLexer;

// Parser modules removed - using direct language modules

// Glob expansion
const glob_mod = @import("../prompt/glob.zig");

// Type aliases
const FilesystemInterface = filesystem.FilesystemInterface;
const Language = language_mod.Language;
const GlobExpander = glob_mod.GlobExpander;
const SharedConfig = shared_config.SharedConfig;
const ZonLoader = zon_config.ZonLoader;
const FormatConfigOptions = zon_config.FormatConfigOptions;
const IndentStyle = zon_config.IndentStyle;
const QuoteStyle = zon_config.QuoteStyle;
const Args = args_mod.Args;
const CommonFlags = args_mod.CommonFlags;
const JsonTransformPipeline = json_transform.JsonTransformPipeline;
const ZonTransformPipeline = zon_transform.ZonTransformPipeline;
const FormatOptions = language_interface.FormatOptions;

// Minimal formatter options for configuration compatibility
const FormatterOptions = struct {
    indent_size: u32 = 4,
    indent_style: IndentStyle = .space,
    line_width: u32 = 100,
    preserve_newlines: bool = true,
    trailing_comma: bool = false,
    sort_keys: bool = false,
    quote_style: QuoteStyle = .double,
    use_ast: bool = false,
};

const FormatArgs = struct {
    files: collections.List([]const u8),
    write: bool = false,
    check: bool = false,
    stdin: bool = false,
    stream: bool = false,
    options: FormatterOptions = .{},

    pub fn deinit(self: *FormatArgs) void {
        self.files.deinit();
    }
};

fn configToFormatterOptions(config: FormatConfigOptions) FormatterOptions {
    return FormatterOptions{
        .indent_size = config.indent_size,
        .indent_style = switch (config.indent_style) {
            IndentStyle.space => .space,
            IndentStyle.tab => .tab,
        },
        .line_width = config.line_width,
        .preserve_newlines = config.preserve_newlines,
        .trailing_comma = config.trailing_comma,
        .sort_keys = config.sort_keys,
        .quote_style = switch (config.quote_style) {
            QuoteStyle.single => .single,
            QuoteStyle.double => .double,
            QuoteStyle.preserve => .preserve,
        },
        .use_ast = config.use_ast,
    };
}

pub fn run(allocator: std.mem.Allocator, fs: FilesystemInterface, args: [][:0]const u8) !void {
    // Load configuration from zz.zon
    var zon_loader = ZonLoader.init(allocator, fs);
    defer zon_loader.deinit();

    const config_options = zon_loader.getFormatConfig() catch FormatConfigOptions{}; // Use defaults on error
    const formatter_options = configToFormatterOptions(config_options);

    var format_args = try parseArgs(allocator, args, formatter_options);
    defer format_args.deinit();

    // Handle stdin mode
    if (format_args.stdin) {
        try formatStdin(allocator, format_args.stream, format_args.options);
        return;
    }

    // If no files specified, show help
    if (format_args.files.items.len == 0) {
        try reporting.reportError("No files specified", .{});
        try reporting.printUsage("Usage: zz format [files...] [options]", .{});
        try reporting.printUsage("Use 'zz format --stdin' to format from stdin", .{});
        std.process.exit(1);
    }

    // Create a basic config for glob expansion
    const config = SharedConfig{
        .ignored_patterns = &[_][]const u8{},
        .hidden_files = &[_][]const u8{},
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    // Expand globs and collect files
    var all_files = collections.List([]const u8).init(allocator);
    defer {
        for (all_files.items) |file| {
            allocator.free(file);
        }
        all_files.deinit();
    }

    const expander = GlobExpander{
        .allocator = allocator,
        .filesystem = fs,
        .config = config,
    };

    // Use the same approach as prompt module - expand patterns with results
    const patterns_array = try allocator.alloc([]const u8, format_args.files.items.len);
    defer allocator.free(patterns_array);
    for (format_args.files.items, 0..) |pattern, i| {
        patterns_array[i] = pattern;
    }

    var results = try expander.expandPatternsWithInfo(patterns_array);
    defer results.deinit();

    for (results.items) |result| {
        defer {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }

        for (result.files.items) |file| {
            const file_copy = try allocator.dupe(u8, file);
            try all_files.append(file_copy);
        }

        // If no files matched and it wasn't a glob, add as-is for error reporting
        if (result.files.items.len == 0 and !result.is_glob) {
            const file_copy = try allocator.dupe(u8, result.pattern);
            try all_files.append(file_copy);
        }
    }

    // Check or format each file
    var any_unformatted = false;
    var any_errors = false;

    for (all_files.items) |file_path| {
        const result = processFile(allocator, fs, file_path, format_args.write, format_args.check, format_args.stream, format_args.options) catch |err| {
            try reporting.reportError("Failed to process file '{s}': {s}", .{ file_path, @errorName(err) });
            any_errors = true;
            continue;
        };

        if (format_args.check and !result) {
            any_unformatted = true;
        }
    }

    if (any_errors) {
        std.process.exit(2);
    }

    if (format_args.check and any_unformatted) {
        std.process.exit(1);
    }
}

fn processFile(allocator: std.mem.Allocator, fs: FilesystemInterface, file_path: []const u8, write: bool, check: bool, stream: bool, options: FormatterOptions) !bool {
    // Detect language from extension
    const ext = path_utils.extension(file_path);
    const language = Language.fromExtension(ext);

    if (language == .unknown) {
        try reporting.reportWarning("Unknown file type for '{s}', skipping", .{file_path});
        return true; // Consider it "formatted" for check mode
    }

    // Read file using filesystem abstraction
    const cwd = fs.cwd();
    const file = try cwd.openFile(allocator, file_path, .{});
    defer file.close();

    const content = try file.readAll(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    // Use stream-first formatting for JSON/ZON if --stream flag is set
    const formatted = if (stream and (language == .json or language == .zon)) blk: {
        break :blk try formatWithStream(allocator, content, language, options);
    } else blk: {
        // Format content using language modules directly
        break :blk try formatWithLanguageModules(allocator, content, language, formatterOptionsToFormatOptions(options));
    };
    defer allocator.free(formatted);

    // Check mode: compare and report
    if (check) {
        const is_formatted = std.mem.eql(u8, content, formatted);
        if (!is_formatted) {
            try reporting.reportInfo("Not formatted: {s}", .{file_path});
        }
        return is_formatted;
    }

    // Write mode: update file
    if (write) {
        if (!std.mem.eql(u8, content, formatted)) {
            // For write mode, we need to use std.fs directly as fs abstraction
            // doesn't support writing yet
            const real_file = try std.fs.cwd().createFile(file_path, .{});
            defer real_file.close();
            try real_file.writeAll(formatted);

            try reporting.reportSuccess("Formatted {s}", .{file_path});
        }
    } else {
        // Output to stdout
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(formatted);
    }

    return true;
}

// Removed formatWithStratifiedParser - using direct language modules

/// Format content using language modules directly (simplified approach)
fn formatWithLanguageModules(allocator: std.mem.Allocator, content: []const u8, language: Language, format_options: FormatOptions) ![]u8 {
    switch (language) {
        .json => {
            // Use JSON module for formatting
            const json_mod = @import("../lib/languages/json/mod.zig");
            // Format JSON with default options
            const formatted = try json_mod.formatJsonString(allocator, content);
            defer allocator.free(formatted);
            // Convert const slice to mutable slice
            return try allocator.dupe(u8, formatted);
        },
        .zon => {
            // Use new ZON module directly
            const zon_mod = @import("../lib/languages/zon/mod.zig");

            // Parse ZON to AST
            var ast = try zon_mod.parseZonString(allocator, content);
            defer ast.deinit();

            // Convert format options to ZON-specific options
            const zon_options = @import("../lib/languages/zon/formatter.zig").ZonFormatter.ZonFormatOptions{
                .indent_size = @intCast(format_options.indent_size),
                .indent_style = if (format_options.indent_style == .space)
                    @import("../lib/languages/zon/formatter.zig").ZonFormatter.ZonFormatOptions.IndentStyle.space
                else
                    @import("../lib/languages/zon/formatter.zig").ZonFormatter.ZonFormatOptions.IndentStyle.tab,
                .line_width = format_options.line_width,
                .preserve_comments = format_options.preserve_newlines,
                .trailing_comma = format_options.trailing_comma,
                .compact_small_objects = true,
                .compact_small_arrays = true,
            };

            // Format using ZON formatter
            const zon_formatter = @import("../lib/languages/zon/formatter.zig").ZonFormatter;
            var formatter = zon_formatter.init(allocator, zon_options);
            defer formatter.deinit();
            const formatted = try formatter.format(ast);
            return allocator.dupe(u8, formatted);
        },
        .css, .html, .typescript, .zig, .svelte => {
            // These languages don't have transform pipelines yet
            return error.UnsupportedLanguage;
        },
        .unknown => return error.UnsupportedLanguage,
    }
}

// Removed mapping functions - using direct language modules

/// Convert FormatterOptions to FormatOptions for language interface compatibility
fn formatterOptionsToFormatOptions(formatter_options: FormatterOptions) FormatOptions {
    return FormatOptions{
        .indent_size = formatter_options.indent_size,
        .indent_style = switch (formatter_options.indent_style) {
            .space => .space,
            .tab => .tab,
        },
        .line_width = formatter_options.line_width,
        .preserve_newlines = formatter_options.preserve_newlines,
        .trailing_comma = formatter_options.trailing_comma,
        .sort_keys = formatter_options.sort_keys,
        .quote_style = switch (formatter_options.quote_style) {
            .single => .single,
            .double => .double,
            .preserve => .preserve,
        },
    };
}

fn formatStdin(allocator: std.mem.Allocator, stream: bool, options: FormatterOptions) !void {
    const stdin = std.io.getStdIn().reader();
    const content = try stdin.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    // Try to detect language from content (simple heuristic)
    const language = detectLanguageFromContent(content);

    // Use stream-first formatting for JSON/ZON if --stream flag is set
    const formatted = if (stream and (language == .json or language == .zon)) blk: {
        break :blk try formatWithStream(allocator, content, language, options);
    } else blk: {
        // Format using language modules directly
        break :blk try formatWithLanguageModules(allocator, content, language, formatterOptionsToFormatOptions(options));
    };
    defer allocator.free(formatted);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(formatted);
}

fn detectLanguageFromContent(content: []const u8) Language {
    // Simple heuristics for language detection
    const trimmed = std.mem.trim(u8, content, " \t\n\r");

    // JSON detection
    if (trimmed.len > 0 and (trimmed[0] == '{' or trimmed[0] == '[')) {
        return .json;
    }

    // HTML detection
    if (std.mem.indexOf(u8, content, "<!DOCTYPE") != null or
        std.mem.indexOf(u8, content, "<html") != null)
    {
        return .html;
    }

    // Svelte detection - look for script or style tags (must come before CSS to avoid false positives)
    if (std.mem.indexOf(u8, content, "<script>") != null or
        std.mem.indexOf(u8, content, "<script ") != null or
        std.mem.indexOf(u8, content, "<style>") != null or
        std.mem.indexOf(u8, content, "<style ") != null)
    {
        return .svelte;
    }

    // CSS detection - improved heuristics
    if (std.mem.indexOf(u8, content, "{") != null and std.mem.indexOf(u8, content, "}") != null) {
        // Look for CSS-specific patterns
        if (std.mem.indexOf(u8, content, ":") != null and
            (std.mem.indexOf(u8, content, "color:") != null or
                std.mem.indexOf(u8, content, "background:") != null or
                std.mem.indexOf(u8, content, "margin:") != null or
                std.mem.indexOf(u8, content, "padding:") != null or
                std.mem.indexOf(u8, content, "display:") != null or
                std.mem.indexOf(u8, content, "width:") != null or
                std.mem.indexOf(u8, content, "height:") != null or
                std.mem.indexOf(u8, content, "font-") != null or
                std.mem.indexOf(u8, content, "border") != null or
                std.mem.indexOf(u8, content, "flex") != null or
                std.mem.indexOf(u8, content, "gap:") != null or
                std.mem.indexOf(u8, content, "position:") != null or
                std.mem.indexOf(u8, content, "z-index:") != null or
                std.mem.indexOf(u8, content, "opacity:") != null))
        {
            return .css;
        }

        // Check for CSS selectors (starts with . or # or element name)
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed_line = std.mem.trim(u8, line, " \t\r");
            if (trimmed_line.len > 0) {
                // CSS selector patterns
                if (trimmed_line[0] == '.' or trimmed_line[0] == '#' or
                    std.mem.indexOf(u8, trimmed_line, " {") != null or
                    std.mem.indexOf(u8, trimmed_line, "}{") != null)
                {
                    return .css;
                }
            }
        }
    }

    // Zig detection (must come before TypeScript to avoid @import being missed)
    if (std.mem.indexOf(u8, content, "@import") != null or
        std.mem.indexOf(u8, content, "pub fn") != null or
        std.mem.indexOf(u8, content, "void{") != null)
    {
        return .zig;
    }

    // TypeScript detection - look for class keyword
    if (std.mem.indexOf(u8, content, "class ") != null or
        std.mem.indexOf(u8, content, "interface ") != null or
        std.mem.indexOf(u8, content, "function ") != null or
        std.mem.indexOf(u8, content, "const ") != null)
    {
        return .typescript;
    }

    return .unknown;
}

fn parseArgs(allocator: std.mem.Allocator, args: [][:0]const u8, base_options: FormatterOptions) !FormatArgs {
    var result = FormatArgs{
        .files = collections.List([]const u8).init(allocator),
        .options = base_options, // Start with config file options
    };

    const start_index = Args.skipToCommand(args, "format");

    var i = start_index;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // Parse using centralized flag functions
        if (CommonFlags.isWriteFlag(arg)) {
            result.write = true;
        } else if (CommonFlags.isCheckFlag(arg)) {
            result.check = true;
        } else if (CommonFlags.isStdinFlag(arg)) {
            result.stdin = true;
        } else if (std.mem.eql(u8, arg, "--stream")) {
            result.stream = true;
        } else if (CommonFlags.parseIndentSizeFlag(arg)) |value| {
            result.options.indent_size = value;
        } else if (CommonFlags.parseIndentStyleFlag(arg)) |value| {
            if (std.mem.eql(u8, value, "tab")) {
                result.options.indent_style = .tab;
            } else if (std.mem.eql(u8, value, "space")) {
                result.options.indent_style = .space;
            } else {
                try reporting.reportError("Invalid indent style '{s}'. Use 'tab' or 'space'", .{value});
                std.process.exit(1);
            }
        } else if (CommonFlags.parseLineWidthFlag(arg)) |value| {
            result.options.line_width = value;
        } else if (Args.isHelpFlag(arg)) {
            try printFormatHelp();
            std.process.exit(0);
        } else if (arg[0] == '-') {
            try reporting.reportError("Unknown option '{s}'", .{arg});
            std.process.exit(1);
        } else {
            // It's a file or pattern
            try result.files.append(arg);
        }
    }

    // Validate args
    if (result.write and result.check) {
        try reporting.reportError("--write and --check are mutually exclusive", .{});
        std.process.exit(1);
    }

    return result;
}

fn printFormatHelp() !void {
    const stderr = std.io.getStdErr().writer();
    const options = [_][]const u8{
        "--write, -w              Format files in-place",
        "--check                  Check if files are formatted (exit 1 if not)",
        "--stdin                  Read from stdin, write to stdout",
        "--stream                 Use stream-first architecture for JSON/ZON (experimental)",
        "--indent-size=N          Number of spaces for indentation (default: 4)",
        "--indent-style=STYLE     Use 'space' or 'tab' (default: space)",
        "--line-width=N           Maximum line width (default: 100)",
        "--help, -h               Show this help message",
    };

    try Args.printUsage(stderr, "format", "Format code files with language-aware pretty printing", &options);
}

/// Format content using stream-first architecture for JSON/ZON
fn formatWithStream(allocator: std.mem.Allocator, content: []const u8, language: Language, options: FormatterOptions) ![]u8 {
    // Convert FormatterOptions to stream FormatOptions
    const stream_options = stream_format.FormatOptions{
        .indent_style = switch (options.indent_style) {
            .space => .spaces,
            .tab => .tabs,
        },
        .indent_width = @intCast(options.indent_size),
        .max_line_width = options.line_width,
        .compact = false, // Always use pretty formatting
        .trailing_commas = options.trailing_comma,
        .sort_keys = options.sort_keys,
    };

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    switch (language) {
        .json => {
            var lexer = JsonStreamLexer.init(content);
            var token_stream = lexer.toDirectStream();
            defer token_stream.close();

            const WriterType = std.ArrayList(u8).Writer;
            var formatter = stream_format.JsonFormatter(WriterType).init(buffer.writer(), stream_options);
            while (try token_stream.next()) |token| {
                try formatter.writeToken(token);
            }
            try formatter.finish();
        },
        .zon => {
            var lexer = ZonStreamLexer.init(content);
            var token_stream = lexer.toDirectStream();
            defer token_stream.close();

            const WriterType = std.ArrayList(u8).Writer;
            var formatter = stream_format.ZonFormatter(WriterType).init(buffer.writer(), stream_options);
            while (try token_stream.next()) |token| {
                try formatter.writeToken(token);
            }
            try formatter.finish();
        },
        else => unreachable, // Should only be called for JSON/ZON
    }

    return buffer.toOwnedSlice();
}

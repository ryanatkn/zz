const std = @import("std");
const FilesystemInterface = @import("../lib/core/filesystem.zig").FilesystemInterface;
const Language = @import("../lib/language/detection.zig").Language;
const Formatter = @import("../lib/parsing/formatter.zig").Formatter;
const FormatterOptions = @import("../lib/parsing/formatter.zig").FormatterOptions;
const FormatterError = @import("../lib/parsing/formatter.zig").FormatterError;
const IndentStyle = @import("../lib/parsing/formatter.zig").IndentStyle;
const path_utils = @import("../lib/core/path.zig");
const GlobExpander = @import("../prompt/glob.zig").GlobExpander;
const SharedConfig = @import("../config/shared.zig").SharedConfig;
const ZonLoader = @import("../config/zon.zig").ZonLoader;
const FormatConfigOptions = @import("../config/zon.zig").FormatConfigOptions;
const Args = @import("../lib/args.zig").Args;
const CommonFlags = @import("../lib/args.zig").CommonFlags;

const FormatArgs = struct {
    files: std.ArrayList([]const u8),
    write: bool = false,
    check: bool = false,
    stdin: bool = false,
    options: FormatterOptions = .{},

    pub fn deinit(self: *FormatArgs) void {
        self.files.deinit();
    }
};

fn configToFormatterOptions(config: FormatConfigOptions) FormatterOptions {
    const config_indent_style = @import("../config/zon.zig").IndentStyle;
    const config_quote_style = @import("../config/zon.zig").QuoteStyle;
    
    return FormatterOptions{
        .indent_size = config.indent_size,
        .indent_style = switch (config.indent_style) {
            config_indent_style.space => .space,
            config_indent_style.tab => .tab,
        },
        .line_width = config.line_width,
        .preserve_newlines = config.preserve_newlines,
        .trailing_comma = config.trailing_comma,
        .sort_keys = config.sort_keys,
        .quote_style = switch (config.quote_style) {
            config_quote_style.single => .single,
            config_quote_style.double => .double,
            config_quote_style.preserve => .preserve,
        },
        .use_ast = config.use_ast,
    };
}

pub fn run(allocator: std.mem.Allocator, filesystem: FilesystemInterface, args: [][:0]const u8) !void {
    // Load configuration from zz.zon
    var zon_loader = ZonLoader.init(allocator, filesystem);
    defer zon_loader.deinit();
    
    const config_options = zon_loader.getFormatConfig() catch FormatConfigOptions{}; // Use defaults on error
    const formatter_options = configToFormatterOptions(config_options);
    
    var format_args = try parseArgs(allocator, args, formatter_options);
    defer format_args.deinit();

    // Handle stdin mode
    if (format_args.stdin) {
        try formatStdin(allocator, format_args.options);
        return;
    }

    // If no files specified, show help
    if (format_args.files.items.len == 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Error: No files specified\n", .{});
        try stderr.print("Usage: zz format [files...] [options]\n", .{});
        try stderr.print("Use 'zz format --stdin' to format from stdin\n", .{});
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
    var all_files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (all_files.items) |file| {
            allocator.free(file);
        }
        all_files.deinit();
    }

    const expander = GlobExpander{
        .allocator = allocator,
        .filesystem = filesystem,
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
        const result = processFile(allocator, filesystem, file_path, format_args.write, format_args.check, format_args.options) catch |err| {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Error processing {s}: {s}\n", .{ file_path, @errorName(err) });
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

fn processFile(allocator: std.mem.Allocator, filesystem: FilesystemInterface, file_path: []const u8, write: bool, check: bool, options: FormatterOptions) !bool {
    // Detect language from extension
    const ext = path_utils.extension(file_path);
    const language = Language.fromExtension(ext);

    if (language == .unknown) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Warning: Unknown file type for {s}, skipping\n", .{file_path});
        return true; // Consider it "formatted" for check mode
    }

    // Read file using filesystem abstraction
    const cwd = filesystem.cwd();
    const file = try cwd.openFile(allocator, file_path, .{});
    defer file.close();

    const content = try file.readAll(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    // Format content
    var formatter = Formatter.init(allocator, language, options);
    const formatted = try formatter.format(content);
    defer allocator.free(formatted);

    // Check mode: compare and report
    if (check) {
        const is_formatted = std.mem.eql(u8, content, formatted);
        if (!is_formatted) {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("{s} is not formatted\n", .{file_path});
        }
        return is_formatted;
    }

    // Write mode: update file
    if (write) {
        if (!std.mem.eql(u8, content, formatted)) {
            // For write mode, we need to use std.fs directly as filesystem abstraction
            // doesn't support writing yet
            const real_file = try std.fs.cwd().createFile(file_path, .{});
            defer real_file.close();
            try real_file.writeAll(formatted);

            const stdout = std.io.getStdOut().writer();
            try stdout.print("Formatted {s}\n", .{file_path});
        }
    } else {
        // Output to stdout
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(formatted);
    }

    return true;
}

fn formatStdin(allocator: std.mem.Allocator, options: FormatterOptions) !void {
    const stdin = std.io.getStdIn().reader();
    const content = try stdin.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    // Try to detect language from content (simple heuristic)
    const language = detectLanguageFromContent(content);

    var formatter = Formatter.init(allocator, language, options);
    const formatted = formatter.format(content) catch |err| {
        if (err == FormatterError.UnsupportedLanguage) {
            // Just output as-is for unknown content
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll(content);
            return;
        }
        return err;
    };
    defer allocator.free(formatted);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(formatted);
}

fn detectLanguageFromContent(content: []const u8) Language {
    // Simple heuristics for language detection
    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    
    // JSON detection
    if ((trimmed.len > 0 and trimmed[0] == '{') or trimmed[0] == '[') {
        // Likely JSON
        return .json;
    }
    
    // HTML detection
    if (std.mem.indexOf(u8, content, "<!DOCTYPE") != null or
        std.mem.indexOf(u8, content, "<html") != null) {
        return .html;
    }
    
    // CSS detection
    if (std.mem.indexOf(u8, content, "{") != null and
        (std.mem.indexOf(u8, content, "color:") != null or
         std.mem.indexOf(u8, content, "background:") != null or
         std.mem.indexOf(u8, content, "margin:") != null)) {
        return .css;
    }
    
    // Zig detection
    if (std.mem.indexOf(u8, content, "const std = @import") != null or
        std.mem.indexOf(u8, content, "pub fn") != null) {
        return .zig;
    }
    
    return .unknown;
}

fn parseArgs(allocator: std.mem.Allocator, args: [][:0]const u8, base_options: FormatterOptions) !FormatArgs {
    var result = FormatArgs{
        .files = std.ArrayList([]const u8).init(allocator),
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
        } else if (CommonFlags.parseIndentSizeFlag(arg)) |value| {
            result.options.indent_size = value;
        } else if (CommonFlags.parseIndentStyleFlag(arg)) |value| {
            if (std.mem.eql(u8, value, "tab")) {
                result.options.indent_style = .tab;
            } else if (std.mem.eql(u8, value, "space")) {
                result.options.indent_style = .space;
            } else {
                const stderr = std.io.getStdErr().writer();
                try stderr.print("Error: Invalid indent style '{s}'. Use 'tab' or 'space'.\n", .{value});
                std.process.exit(1);
            }
        } else if (CommonFlags.parseLineWidthFlag(arg)) |value| {
            result.options.line_width = value;
        } else if (Args.isHelpFlag(arg)) {
            try printFormatHelp();
            std.process.exit(0);
        } else if (arg[0] == '-') {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Unknown option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            // It's a file or pattern
            try result.files.append(arg);
        }
    }

    // Validate args
    if (result.write and result.check) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Error: --write and --check are mutually exclusive\n", .{});
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
        "--indent-size=N          Number of spaces for indentation (default: 4)",
        "--indent-style=STYLE     Use 'space' or 'tab' (default: space)",
        "--line-width=N           Maximum line width (default: 100)",
        "--help, -h               Show this help message",
    };
    
    try Args.printUsage(stderr, "format", "Format code files with language-aware pretty printing", &options);
}
const std = @import("std");
const escape = @import("escape.zig");
const json = @import("json.zig");
const color = @import("color.zig");
const errors = @import("../lib/core/errors.zig");

pub const Options = struct {
    no_newline: bool = false,
    escape_sequences: bool = false,
    json_output: bool = false,
    repeat: u16 = 1,
    separator: []const u8 = " ",
    use_stdin: bool = false,
    color_name: ?[]const u8 = null,
    bold: bool = false,
    no_color: bool = false,
    // Cached color detection result
    should_use_color: bool = false,
};

const EchoError = error{
    InvalidRepeatCount,
    UnknownColor,
    InvalidFlag,
    OutOfMemory,
};

/// Write empty output (just newline)
fn writeEmpty() !void {
    const writer = std.io.getStdOut().writer();
    try writer.writeAll("\n");
}

pub fn run(allocator: std.mem.Allocator, args: [][:0]const u8) !void {
    if (args.len < 2) {
        try writeEmpty();
        return;
    }

    const parse_result = try parseArgsAndText(args);
    var options = parse_result.options;
    // Cache color detection result once per invocation
    options.should_use_color = !options.no_color and color.shouldUseColor();
    const text_args = parse_result.text_args;

    if (options.use_stdin) {
        try processStdin(allocator, options);
    } else {
        try processArgs(allocator, options, text_args);
    }
}

const ParseResult = struct {
    options: Options,
    text_args: [][:0]const u8,
};

pub fn parseArgsAndText(args: [][:0]const u8) EchoError!ParseResult {
    var options = Options{};
    var i: usize = 2; // Skip program name and "echo" command

    while (i < args.len) {
        const arg = args[i];

        // Handle flags that start with '-'
        if (arg.len > 1 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-n")) {
                options.no_newline = true;
            } else if (std.mem.eql(u8, arg, "-e")) {
                options.escape_sequences = true;
            } else if (std.mem.eql(u8, arg, "-E")) {
                options.escape_sequences = false;
            } else if (std.mem.eql(u8, arg, "--json")) {
                options.json_output = true;
            } else if (std.mem.eql(u8, arg, "--stdin")) {
                options.use_stdin = true;
            } else if (std.mem.eql(u8, arg, "--null")) {
                options.separator = "\x00";
            } else if (std.mem.eql(u8, arg, "--bold")) {
                options.bold = true;
            } else if (std.mem.eql(u8, arg, "--no-color")) {
                options.no_color = true;
            } else if (std.mem.startsWith(u8, arg, "--repeat=")) {
                const value = arg[9..];
                const repeat_count = std.fmt.parseInt(u16, value, 10) catch {
                    std.debug.print("Error: Invalid repeat count '{s}'. Must be a number between 1 and 10000.\n", .{value});
                    return EchoError.InvalidRepeatCount;
                };
                if (repeat_count == 0 or repeat_count > 10000) {
                    std.debug.print("Error: Repeat count {} is out of range. Must be between 1 and 10000.\n", .{repeat_count});
                    return EchoError.InvalidRepeatCount;
                }
                options.repeat = repeat_count;
            } else if (std.mem.startsWith(u8, arg, "--sep=")) {
                options.separator = arg[6..];
            } else if (std.mem.startsWith(u8, arg, "--color=")) {
                const color_name = arg[8..];
                if (!color.isValidColor(color_name)) {
                    std.debug.print("Error: Unknown color '{s}'. Valid colors: red, green, blue, yellow, magenta, cyan, black, white.\n", .{color_name});
                    return EchoError.UnknownColor;
                }
                options.color_name = color_name;
            } else if (std.mem.eql(u8, arg, "--repeat") and i + 1 < args.len) {
                i += 1;
                const repeat_count = std.fmt.parseInt(u16, args[i], 10) catch {
                    std.debug.print("Error: Invalid repeat count '{s}'. Must be a number between 1 and 10000.\n", .{args[i]});
                    return EchoError.InvalidRepeatCount;
                };
                if (repeat_count == 0 or repeat_count > 10000) {
                    std.debug.print("Error: Repeat count {} is out of range. Must be between 1 and 10000.\n", .{repeat_count});
                    return EchoError.InvalidRepeatCount;
                }
                options.repeat = repeat_count;
            } else if (std.mem.eql(u8, arg, "--sep") and i + 1 < args.len) {
                i += 1;
                options.separator = args[i];
            } else if (std.mem.eql(u8, arg, "--color") and i + 1 < args.len) {
                i += 1;
                if (!color.isValidColor(args[i])) {
                    std.debug.print("Error: Unknown color '{s}'. Valid colors: red, green, blue, yellow, magenta, cyan, black, white.\n", .{args[i]});
                    return EchoError.UnknownColor;
                }
                options.color_name = args[i];
            } else {
                std.debug.print("Error: Unknown flag '{s}'. Use 'zz help' to see available options.\n", .{arg});
                return EchoError.InvalidFlag;
            }
        } else {
            // Non-flag argument, we're done parsing options
            break;
        }
        i += 1;
    }

    // Return remaining args as text arguments
    const text_args = if (i < args.len) args[i..] else args[args.len..];
    return ParseResult{
        .options = options,
        .text_args = text_args,
    };
}

fn processStdin(allocator: std.mem.Allocator, options: Options) !void {
    const stdin = std.io.getStdIn().reader();
    const content = try stdin.readAllAlloc(allocator, 1024 * 1024); // 1MB limit
    defer allocator.free(content);

    const text_to_output = if (options.json_output)
        try json.escape(allocator, content)
    else
        content;
    defer if (options.json_output) allocator.free(text_to_output);

    try outputText(options, text_to_output);
}

fn processArgs(allocator: std.mem.Allocator, options: Options, text_args: [][:0]const u8) !void {
    if (text_args.len == 0) {
        try outputText(options, "");
        return;
    }

    // Calculate total size needed for joined text
    var total_size: usize = 0;
    for (text_args, 0..) |arg, idx| {
        total_size += arg.len;
        if (idx < text_args.len - 1) {
            total_size += options.separator.len;
        }
    }

    // For simple single argument case, avoid allocation
    if (text_args.len == 1 and !options.json_output and !options.escape_sequences) {
        try outputText(options, text_args[0]);
        return;
    }

    // Join arguments with separator
    const joined = try allocator.alloc(u8, total_size);
    defer allocator.free(joined);

    var pos: usize = 0;
    for (text_args, 0..) |arg, idx| {
        @memcpy(joined[pos .. pos + arg.len], arg);
        pos += arg.len;
        if (idx < text_args.len - 1) {
            @memcpy(joined[pos .. pos + options.separator.len], options.separator);
            pos += options.separator.len;
        }
    }

    const text_to_output = if (options.json_output)
        try json.escape(allocator, joined)
    else if (options.escape_sequences)
        try escape.process(allocator, joined)
    else
        joined;
    defer {
        if (options.json_output or options.escape_sequences) {
            allocator.free(text_to_output);
        }
    }

    try outputText(options, text_to_output);
}

fn outputText(options: Options, text: []const u8) !void {
    const writer = std.io.getStdOut().writer();

    // Handle color output
    if (options.color_name) |color_name| {
        if (options.should_use_color) {
            try color.writeColor(writer, color_name, options.bold);
        }
    } else if (options.bold and options.should_use_color) {
        try color.writeBold(writer);
    }

    // Output text with repetition
    var count: u16 = 0;
    while (count < options.repeat) : (count += 1) {
        try writer.writeAll(text);
        // Add newline after each repetition except the last (unless no_newline is set)
        if (count < options.repeat - 1) {
            try writer.writeAll("\n");
        } else if (!options.no_newline) {
            // Add final newline unless suppressed
            try writer.writeAll("\n");
        }
    }

    // Reset color
    if ((options.color_name != null or options.bold) and options.should_use_color) {
        try color.writeReset(writer);
    }
}

const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../test_helpers.zig");
const PromptBuilder = @import("../builder.zig").PromptBuilder;
const ExtractionFlags = @import("../../lib/parser.zig").ExtractionFlags;
const Config = @import("../config.zig").Config;

test "extraction flags - signatures only" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Create a test Zig file
    const test_content =
        \\const std = @import("std");
        \\
        \\pub fn hello() void {
        \\    std.debug.print("Hello\n", .{});
        \\}
        \\
        \\fn privateFunc() !void {
        \\    return error.NotImplemented;
        \\}
        \\
        \\pub fn main() !void {
        \\    hello();
        \\}
    ;
    
    try ctx.writeFile("test.zig", test_content);

    const extraction_flags = ExtractionFlags{ .signatures = true };
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    try builder.addFile("test.zig");
    
    // Check that signatures were extracted
    var found_hello = false;
    var found_main = false;
    var found_private = false;
    
    for (builder.lines.items) |line| {
        if (std.mem.indexOf(u8, line, "pub fn hello") != null) found_hello = true;
        if (std.mem.indexOf(u8, line, "pub fn main") != null) found_main = true;
        if (std.mem.indexOf(u8, line, "fn privateFunc") != null) found_private = true;
    }
    
    try testing.expect(found_hello);
    try testing.expect(found_main);
    try testing.expect(found_private); // Currently extracts all functions, not just public
}

test "extraction flags - types only" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const test_content =
        \\const std = @import("std");
        \\
        \\pub const Config = struct {
        \\    port: u16,
        \\    host: []const u8,
        \\};
        \\
        \\const Internal = struct {
        \\    data: []u8,
        \\};
        \\
        \\pub var global_setting: bool = false;
    ;
    
    try ctx.writeFile("test.zig", test_content);

    const extraction_flags = ExtractionFlags{ .types = true };
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    try builder.addFile("test.zig");
    
    var found_config = false;
    var found_internal = false;
    var found_global = false;
    
    for (builder.lines.items) |line| {
        if (std.mem.indexOf(u8, line, "pub const Config") != null) found_config = true;
        if (std.mem.indexOf(u8, line, "const Internal") != null) found_internal = true;
        if (std.mem.indexOf(u8, line, "pub var global_setting") != null) found_global = true;
    }
    
    try testing.expect(found_config);
    try testing.expect(found_internal);
    try testing.expect(found_global);
}

test "extraction flags - combined extraction" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const test_content =
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\/// Documentation for MyStruct
        \\pub const MyStruct = struct {
        \\    value: u32,
        \\};
        \\
        \\pub fn process(s: MyStruct) !void {
        \\    if (s.value == 0) return error.InvalidValue;
        \\}
        \\
        \\test "process test" {
        \\    const s = MyStruct{ .value = 42 };
        \\    try process(s);
        \\}
    ;
    
    try ctx.writeFile("test.zig", test_content);

    // Combine multiple extraction flags
    const extraction_flags = ExtractionFlags{ 
        .signatures = true,
        .types = true,
        .docs = true,
        .tests = true,
    };
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    try builder.addFile("test.zig");
    
    var found_struct = false;
    var found_function = false;
    var found_docs = false;
    var found_test = false;
    
    for (builder.lines.items) |line| {
        if (std.mem.indexOf(u8, line, "pub const MyStruct") != null) found_struct = true;
        if (std.mem.indexOf(u8, line, "pub fn process") != null) found_function = true;
        if (std.mem.indexOf(u8, line, "/// Documentation") != null) found_docs = true;
        if (std.mem.indexOf(u8, line, "test \"process test\"") != null) found_test = true;
    }
    
    try testing.expect(found_struct);
    try testing.expect(found_function);
    try testing.expect(found_docs);
    try testing.expect(found_test);
}

test "extraction flags - error handling extraction" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const test_content =
        \\const std = @import("std");
        \\
        \\pub fn readFile(path: []const u8) ![]u8 {
        \\    const file = try std.fs.cwd().openFile(path, .{});
        \\    defer file.close();
        \\    
        \\    const stat = try file.stat();
        \\    const content = try allocator.alloc(u8, stat.size);
        \\    _ = try file.read(content);
        \\    
        \\    return content;
        \\}
        \\
        \\pub fn safeOperation() void {
        \\    // No error handling here
        \\    std.debug.print("Safe\n", .{});
        \\}
        \\
        \\pub fn handleError(err: anyerror) void {
        \\    switch (err) {
        \\        error.OutOfMemory => std.debug.print("OOM\n", .{}),
        \\        else => std.debug.print("Unknown\n", .{}),
        \\    }
        \\}
    ;
    
    try ctx.writeFile("test.zig", test_content);

    const extraction_flags = ExtractionFlags{ .errors = true };
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    try builder.addFile("test.zig");
    
    var found_try = false;
    var found_error_switch = false;
    
    for (builder.lines.items) |line| {
        if (std.mem.indexOf(u8, line, "try") != null) found_try = true;
        if (std.mem.indexOf(u8, line, "error.OutOfMemory") != null) found_error_switch = true;
    }
    
    try testing.expect(found_try);
    try testing.expect(found_error_switch);
}

test "extraction flags - default is full source" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const test_content = "const x = 42;\n";
    try ctx.writeFile("test.zig", test_content);

    // No extraction flags set - should default to full
    const extraction_flags = ExtractionFlags{};
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    try builder.addFile("test.zig");
    
    var found_content = false;
    for (builder.lines.items) |line| {
        if (std.mem.indexOf(u8, line, "const x = 42") != null) found_content = true;
    }
    
    try testing.expect(found_content);
}

test "config parsing extraction flags" {
    const args = [_][:0]const u8{
        "zz",
        "prompt",
        "test.zig",
        "--signatures",
        "--types",
        "--errors",
    };

    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    var config = try Config.fromArgs(testing.allocator, ctx.filesystem, &args);
    defer config.deinit();

    try testing.expect(config.extraction_flags.signatures == true);
    try testing.expect(config.extraction_flags.types == true);
    try testing.expect(config.extraction_flags.errors == true);
    try testing.expect(config.extraction_flags.docs == false);
    try testing.expect(config.extraction_flags.full == false);
}

test "extraction flags - non-Zig files fall back to full" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const test_content = "# Markdown File\n\nSome content here.";
    try ctx.writeFile("test.md", test_content);

    // Request signatures for a markdown file - should fall back to full content
    const extraction_flags = ExtractionFlags{ .signatures = true };
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    try builder.addFile("test.md");
    
    var found_content = false;
    for (builder.lines.items) |line| {
        if (std.mem.indexOf(u8, line, "# Markdown File") != null) found_content = true;
    }
    
    // Should include full content since extraction isn't supported for markdown yet
    try testing.expect(found_content);
}
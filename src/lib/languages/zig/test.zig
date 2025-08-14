const std = @import("std");
const testing = std.testing;
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

// Import the modules to test
const extract = @import("extractor.zig").extract;
const format = @import("formatter.zig").format;

test "Zig function extraction" {
    const allocator = testing.allocator;
    const source =
        \\pub fn main() void {
        \\    std.debug.print("Hello", .{});
        \\}
        \\
        \\fn helper() !void {
        \\    return error.NotImplemented;
        \\}
        \\
        \\const value = 42;
    ;

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    const flags = ExtractionFlags{ .signatures = true };
    try extract(allocator, source, flags, &result);

    // Should contain function signatures
    try testing.expect(std.mem.indexOf(u8, result.items, "pub fn main() void") != null);
    try testing.expect(std.mem.indexOf(u8, result.items, "fn helper() !void") != null);
}

test "Zig import extraction" {
    const allocator = testing.allocator;
    const source =
        \\const std = @import("std");
        \\const c = @cImport(@cInclude("stdio.h"));
        \\
        \\pub fn main() void {}
    ;

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    const flags = ExtractionFlags{ .imports = true };
    try extract(allocator, source, flags, &result);

    // Should contain imports
    try testing.expect(std.mem.indexOf(u8, result.items, "@import(\"std\")") != null);
    try testing.expect(std.mem.indexOf(u8, result.items, "@cImport") != null);
}

test "Zig test extraction" {
    const allocator = testing.allocator;
    const source =
        \\test "addition" {
        \\    try testing.expect(1 + 1 == 2);
        \\}
        \\
        \\fn helper() void {}
    ;

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    const flags = ExtractionFlags{ .tests = true };
    try extract(allocator, source, flags, &result);

    // Should contain test blocks
    try testing.expect(std.mem.indexOf(u8, result.items, "test \"addition\"") != null);
    // Should not contain regular functions
    try testing.expect(std.mem.indexOf(u8, result.items, "fn helper") == null);
}

test "Zig basic formatting" {
    const allocator = testing.allocator;
    const source = "pub fn test() void { return; }";
    const options = FormatterOptions{ .indent_size = 4 };

    const result = try format(allocator, source, options);
    defer allocator.free(result);

    // For now, just check that formatting returns something
    try testing.expect(result.len > 0);
    try testing.expect(std.mem.indexOf(u8, result, "pub fn test()") != null);
}

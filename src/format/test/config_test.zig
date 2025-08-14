const std = @import("std");
const testing = std.testing;
const ZonLoader = @import("../../config/zon.zig").ZonLoader;
const FormatConfigOptions = @import("../../config/zon.zig").FormatConfigOptions;
const IndentStyle = @import("../../config/zon.zig").IndentStyle;
const QuoteStyle = @import("../../config/zon.zig").QuoteStyle;
const MockFilesystem = @import("../../lib/filesystem/mock.zig").MockFilesystem;

test "format config loading from zz.zon" {
    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();
    
    // Add current directory and config file
    try mock_fs.addDirectory(".");
    try mock_fs.addFile("zz.zon", 
        \\.{
        \\    .format = .{
        \\        .indent_size = 2,
        \\        .indent_style = "tab",
        \\        .line_width = 80,
        \\        .preserve_newlines = false,
        \\        .trailing_comma = true,
        \\        .sort_keys = true,
        \\        .quote_style = "single",
        \\        .use_ast = false,
        \\    },
        \\}
    );
    
    var zon_loader = ZonLoader.init(testing.allocator, mock_fs.interface());
    defer zon_loader.deinit();
    
    const options = try zon_loader.getFormatConfig();
    
    // Verify all options were loaded correctly
    try testing.expect(options.indent_size == 2);
    try testing.expect(options.indent_style == .tab);
    try testing.expect(options.line_width == 80);
    try testing.expect(options.preserve_newlines == false);
    try testing.expect(options.trailing_comma == true);
    try testing.expect(options.sort_keys == true);
    try testing.expect(options.quote_style == .single);
    try testing.expect(options.use_ast == false);
}

test "format config defaults when no file" {
    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();
    
    // Add current directory but no config file
    try mock_fs.addDirectory(".");
    
    var zon_loader = ZonLoader.init(testing.allocator, mock_fs.interface());
    defer zon_loader.deinit();
    
    const options = try zon_loader.getFormatConfig();
    
    // Should use default values
    try testing.expect(options.indent_size == 4);
    try testing.expect(options.indent_style == .space);
    try testing.expect(options.line_width == 100);
    try testing.expect(options.preserve_newlines == true);
    try testing.expect(options.trailing_comma == false);
    try testing.expect(options.sort_keys == false);
    try testing.expect(options.quote_style == .preserve);
    try testing.expect(options.use_ast == true);
}

test "format config partial options" {
    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();
    
    // Add current directory and config file with only some options
    try mock_fs.addDirectory(".");
    try mock_fs.addFile("zz.zon", 
        \\.{
        \\    .format = .{
        \\        .indent_size = 8,
        \\        .line_width = 120,
        \\    },
        \\}
    );
    
    var zon_loader = ZonLoader.init(testing.allocator, mock_fs.interface());
    defer zon_loader.deinit();
    
    const options = try zon_loader.getFormatConfig();
    
    // Should use specified options and defaults for others
    try testing.expect(options.indent_size == 8);
    try testing.expect(options.line_width == 120);
    // These should remain defaults
    try testing.expect(options.indent_style == .space);
    try testing.expect(options.preserve_newlines == true);
    try testing.expect(options.quote_style == .preserve);
}

test "format config invalid values" {
    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();
    
    // Add current directory and config file with invalid values
    try mock_fs.addDirectory(".");
    try mock_fs.addFile("zz.zon", 
        \\.{
        \\    .format = .{
        \\        .indent_style = "invalid",
        \\        .quote_style = "unknown",
        \\    },
        \\}
    );
    
    var zon_loader = ZonLoader.init(testing.allocator, mock_fs.interface());
    defer zon_loader.deinit();
    
    const options = try zon_loader.getFormatConfig();
    
    // Invalid values should fall back to defaults
    try testing.expect(options.indent_style == .space);
    try testing.expect(options.quote_style == .preserve);
}

test "format config without format section" {
    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();
    
    // Add current directory and config file without format section
    try mock_fs.addDirectory(".");
    try mock_fs.addFile("zz.zon", 
        \\.{
        \\    .ignored_patterns = .{"test"},
        \\    .tree = .{},
        \\}
    );
    
    var zon_loader = ZonLoader.init(testing.allocator, mock_fs.interface());
    defer zon_loader.deinit();
    
    const options = try zon_loader.getFormatConfig();
    
    // Should use all defaults when format section is missing
    try testing.expect(options.indent_size == 4);
    try testing.expect(options.indent_style == .space);
    try testing.expect(options.line_width == 100);
    try testing.expect(options.preserve_newlines == true);
    try testing.expect(options.trailing_comma == false);
    try testing.expect(options.sort_keys == false);
    try testing.expect(options.quote_style == .preserve);
    try testing.expect(options.use_ast == true);
}

test "format config malformed file" {
    // TODO: ZON parser crashes on malformed input
    // The std.zon parser doesn't gracefully handle malformed ZON files
    // This causes a panic instead of returning an error
    return error.SkipZigTest;
}
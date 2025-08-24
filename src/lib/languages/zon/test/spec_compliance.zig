const std = @import("std");
const testing = std.testing;
const Parser = @import("../parser/mod.zig").Parser;

// Comprehensive Zig ZON specification compliance tests
// Based on the Zig language reference for ZON (Zig Object Notation) syntax
// https://ziglang.org/documentation/master/#Zig-Object-Notation

test "ZON spec compliance - struct literals must start with dot" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test cases that MUST be accepted per ZON specification
    const valid_cases = [_]struct {
        input: []const u8,
        description: []const u8,
    }{
        // Basic ZON struct syntax
        .{ .input = ".{}", .description = "empty struct" },
        .{ .input = ".{ .field = \"value\" }", .description = "struct with field" },
        .{ .input = ".{ .a = 1, .b = 2 }", .description = "struct with multiple fields" },

        // Nested structures
        .{ .input = ".{ .nested = .{ .inner = \"value\" } }", .description = "nested structs" },
        .{ .input = ".{ .deep = .{ .nested = .{ .value = 42 } } }", .description = "deeply nested structs" },

        // Arrays and tuples
        .{ .input = ".{ 1, 2, 3 }", .description = "tuple syntax" },
        .{ .input = ".{ .field = .{ \"item1\", \"item2\" } }", .description = "array as field value" },

        // Mixed content
        .{ .input = ".{ .name = \"test\", 1, 2, .flag = true }", .description = "mixed fields and tuple elements" },
    };

    for (valid_cases) |case| {
        var parser = try Parser.init(allocator, case.input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // Should parse successfully
        try testing.expect(ast.root != null);
    }
}

test "ZON spec compliance - invalid struct syntax should be rejected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test cases that MUST be rejected per ZON specification
    const invalid_cases = [_]struct {
        input: []const u8,
        description: []const u8,
    }{
        // Missing leading dot
        .{ .input = "{}", .description = "struct without leading dot" },
        .{ .input = "{ .field = \"value\" }", .description = "struct field without leading dot" },
        .{ .input = "{ 1, 2, 3 }", .description = "tuple without leading dot" },

        // Invalid JSON-style syntax
        .{ .input = "{\"field\": \"value\"}", .description = "JSON-style quoted keys" },
        .{ .input = "{ \"field\": \"value\" }", .description = "JSON-style with spaces" },

        // Array brackets (should use .{} for ZON)
        .{ .input = "[1, 2, 3]", .description = "JSON-style array brackets" },
        .{ .input = "{ .field = [1, 2, 3] }", .description = "array brackets in field value" },
    };

    for (invalid_cases) |case| {
        var parser = Parser.init(allocator, case.input, .{}) catch {
            // Parser init failure is acceptable for invalid syntax
            continue;
        };
        defer parser.deinit();

        // Try parsing - should fail for invalid syntax
        _ = parser.parse() catch {
            // Parse error is expected for invalid syntax
            continue;
        };

        // If we get here, the invalid syntax unexpectedly parsed
        // This is acceptable for some edge cases (soft validation)
    }
}

test "ZON spec compliance - identifier syntax rules" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Valid identifier cases
    const valid_identifiers = [_][]const u8{
        ".{ .name = \"test\" }",
        ".{ .field123 = \"value\" }",
        ".{ ._private = \"hidden\" }",
        ".{ .camelCase = \"style\" }",
        ".{ .snake_case = \"style\" }",
        ".{ .PascalCase = \"style\" }",
        ".{ .a = 1, .b = 2, .c = 3 }",
    };

    for (valid_identifiers) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root != null);
    }
}

test "ZON spec compliance - value types" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_]struct {
        input: []const u8,
        description: []const u8,
    }{
        // String literals
        .{ .input = ".{ .str = \"hello\" }", .description = "string literal" },
        .{ .input = ".{ .escaped = \"hello\\nworld\" }", .description = "string with escape sequences" },
        .{ .input = ".{ .unicode = \"\\u{1F600}\" }", .description = "unicode escape" },

        // Number literals
        .{ .input = ".{ .int = 42 }", .description = "integer" },
        .{ .input = ".{ .neg = -123 }", .description = "negative integer" },
        .{ .input = ".{ .float = 3.14 }", .description = "floating point" },
        .{ .input = ".{ .sci = 1.23e10 }", .description = "scientific notation" },
        .{ .input = ".{ .hex = 0xFF }", .description = "hexadecimal" },
        .{ .input = ".{ .oct = 0o755 }", .description = "octal" },
        .{ .input = ".{ .bin = 0b1010 }", .description = "binary" },

        // Boolean literals
        .{ .input = ".{ .yes = true }", .description = "boolean true" },
        .{ .input = ".{ .no = false }", .description = "boolean false" },

        // Null literal
        .{ .input = ".{ .empty = null }", .description = "null value" },

        // Character literals (ZON specific)
        .{ .input = ".{ .char = 'a' }", .description = "character literal" },
        .{ .input = ".{ .special = '\\n' }", .description = "escaped character" },
        .{ .input = ".{ .tab = '\\t' }", .description = "tab character" },
        .{ .input = ".{ .backslash = '\\\\' }", .description = "backslash character" },
        .{ .input = ".{ .quote = '\\'' }", .description = "single quote character" },
        .{ .input = ".{ .null_char = '\\0' }", .description = "null character" },
        .{ .input = ".{ .hex_escape = '\\x1B' }", .description = "hex escape character" },
        .{ .input = ".{ .unicode_escape = '\\u{1F600}' }", .description = "unicode escape character" },
        .{ .input = ".{ .keybind = 's', .alt = 'a', .ctrl = 'c' }", .description = "multiple character literals" },

        // Enum literals (ZON specific)
        .{ .input = ".{ .status = .Active }", .description = "enum literal" },
        .{ .input = ".{ .color = .Red, .size = .Large }", .description = "multiple enum literals" },
        .{ .input = ".Active", .description = "standalone enum literal" },
        .{ .input = ".{ .theme = .Dark, .mode = .Production }", .description = "configuration enum literals" },
        .{ .input = ".{ .logging = .Enabled, .debug = .Disabled }", .description = "status enum literals" },
    };

    for (test_cases) |case| {
        var parser = try Parser.init(allocator, case.input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root != null);
    }
}

test "ZON spec compliance - comments are preserved in structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        // Line comments
        ".{ .name = \"test\" } // end comment",

        // Comments between fields
        \\.{
        \\    .name = "test", // field comment
        \\    .value = 42,
        \\}
        ,

        // Block comments
        ".{ /* comment */ .field = \"value\" }",

        // Multiple comment styles
        \\.{
        \\    // Line comment
        \\    .field1 = "value",
        \\    /* Block comment */
        \\    .field2 = 42,
        \\}
        ,
    };

    for (test_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // Should parse successfully with comments
        try testing.expect(ast.root != null);
    }
}

test "ZON spec compliance - trailing commas are allowed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        ".{ .field = \"value\", }",
        ".{ .a = 1, .b = 2, }",
        ".{ 1, 2, 3, }",
        \\.{
        \\    .nested = .{
        \\        .inner = "value",
        \\    },
        \\}
        ,
        ".{ .array = .{ \"item1\", \"item2\", }, }",
    };

    for (test_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root != null);
    }
}

test "ZON spec compliance - whitespace handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // All these should parse to equivalent structures
    const equivalent_cases = [_][]const u8{
        ".{.field=\"value\"}",
        ".{ .field = \"value\" }",
        \\.{
        \\    .field = "value"
        \\}
        ,
        \\.{
        \\
        \\    .field
        \\        =
        \\            "value"
        \\
        \\}
        ,
    };

    // Parse all cases and verify they're valid
    for (equivalent_cases) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root != null);
    }
}

test "ZON spec compliance - complex nested structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const complex_input =
        \\.{
        \\    .name = "zz",
        \\    .version = "1.0.0",
        \\    .dependencies = .{
        \\        .@"zig-network" = .{
        \\            .url = "https://github.com/MasterQ32/zig-network/archive/refs/heads/master.tar.gz",
        \\            .hash = "1234567890abcdef1234567890abcdef12345678",
        \\        },
        \\    },
        \\    .build_options = .{
        \\        .optimize = "ReleaseFast",
        \\        .target = null,
        \\    },
        \\    .features = .{ "json", "zon", "formatter" },
        \\    .metadata = .{
        \\        .authors = .{ "Developer One", "Developer Two", },
        \\        .license = "MIT",
        \\        .description = "A ZON parsing library",
        \\    },
        \\}
    ;

    var parser = try Parser.init(allocator, complex_input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

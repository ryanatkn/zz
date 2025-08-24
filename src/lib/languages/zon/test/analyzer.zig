const std = @import("std");
const testing = std.testing;

// Import ZON modules
const ZonParser = @import("../parser/mod.zig").Parser;
const ZonAnalyzer = @import("../analyzer/mod.zig").Analyzer;

// =============================================================================
// Analyzer Tests
// =============================================================================

test "ZON analyzer - schema extraction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_build_zon =
        \\.{
        \\    .name = "zz",
        \\    .version = "0.0.0",
        \\    .dependencies = .{},
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, test_build_zon, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const analyzer = ZonAnalyzer.init(allocator, .{});

    // Extract schema if implemented
    // const schema = try analyzer.extractSchema(ast);
    // defer schema.deinit(allocator);
    // try testing.expect(schema.fields.len >= 3); // name, version, dependencies

    _ = analyzer; // Placeholder until implementation
}

test "ZON analyzer - symbol extraction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .name = "package",
        \\    .version = "1.0.0",
        \\    .dependencies = .{
        \\        .utils = .{
        \\            .url = "https://example.com/utils",
        \\        },
        \\    },
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = ZonAnalyzer.init(allocator, .{});

    const symbols = try analyzer.extractSymbols(ast);
    defer {
        for (symbols) |symbol| {
            symbol.deinit(allocator);
        }
        allocator.free(symbols);
    }

    try testing.expect(symbols.len > 0);
}

test "ZON analyzer - dependency extraction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .dependencies = .{
        \\        .package1 = .{
        \\            .url = "https://example.com/pkg1",
        \\            .hash = "1234567890abcdef",
        \\        },
        \\        .package2 = .{
        \\            .path = "../local/package",
        \\        },
        \\    },
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const analyzer = ZonAnalyzer.init(allocator, .{});

    // Extract dependencies if implemented
    // const deps = try analyzer.extractDependencies(ast);
    // defer deps.deinit(allocator);
    // try testing.expectEqual(@as(usize, 2), deps.len);

    _ = analyzer; // Placeholder until implementation
}

test "ZON analyzer - type inference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .string_field = "text",
        \\    .number_field = 42,
        \\    .bool_field = true,
        \\    .null_field = null,
        \\    .array_field = .{ 1, 2, 3 },
        \\    .object_field = .{ .nested = "value" },
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const analyzer = ZonAnalyzer.init(allocator, .{});

    // Infer types if implemented
    // const types = try analyzer.inferTypes(ast);
    // defer types.deinit(allocator);
    // try testing.expect(types.fields.len == 6);

    _ = analyzer; // Placeholder until implementation
}

test "ZON analyzer - statistics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\.{
        \\    .name = "test",
        \\    .nested = .{
        \\        .deep = .{
        \\            .value = 123,
        \\        },
        \\    },
        \\    .array = .{ 1, 2, 3, 4, 5 },
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const analyzer = ZonAnalyzer.init(allocator, .{});

    // Generate statistics if implemented
    // const stats = try analyzer.generateStatistics(ast);
    // try testing.expect(stats.max_depth >= 3);
    // try testing.expect(stats.total_fields >= 5);

    _ = analyzer; // Placeholder until implementation
}

test "ZON analyzer - Zig type generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_zz_zon =
        \\.{
        \\    .name = "zz",
        \\    .version = "0.0.0",
        \\    .dependencies = .{},
        \\    .paths = .{ "src", "test" },
        \\}
    ;

    // Updated to streaming parser (3-arg pattern)
    var parser = try ZonParser.init(allocator, test_zz_zon, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const analyzer = ZonAnalyzer.init(allocator, .{});

    // Generate Zig type if implemented
    // const zig_type = try analyzer.generateZigType(allocator, ast, "BuildZon");
    // defer allocator.free(zig_type);
    // try testing.expect(std.mem.indexOf(u8, zig_type, "name: []const u8") != null);

    _ = analyzer; // Placeholder until implementation
}

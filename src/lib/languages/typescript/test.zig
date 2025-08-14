const std = @import("std");
const testing = std.testing;
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

// Import the modules to test
const extract = @import("extractor.zig").extract;
const format = @import("formatter.zig").format;

test "TypeScript function extraction" {
    const allocator = testing.allocator;
    const source = 
        \\function test() {}
        \\interface User { name: string; }
        \\import { foo } from 'bar';
    ;
    
    // Test function extraction
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    const flags = ExtractionFlags{ .signatures = true };
    try extract(allocator, source, flags, &result);
    try testing.expect(std.mem.indexOf(u8, result.items, "function test()") != null);
}

test "TypeScript interface extraction" {
    const allocator = testing.allocator;
    const source = "interface User { name: string; age: number; }";
    const flags = ExtractionFlags{ .types = true };
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try extract(allocator, source, flags, &result);
    try testing.expect(std.mem.indexOf(u8, result.items, "interface User") != null);
}

test "TypeScript import extraction" {
    const allocator = testing.allocator;
    const source = "import { Component } from '@angular/core';";
    const flags = ExtractionFlags{ .imports = true };
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try extract(allocator, source, flags, &result);
    try testing.expect(std.mem.indexOf(u8, result.items, "import { Component }") != null);
}

test "TypeScript basic formatting" {
    const allocator = testing.allocator;
    const source = "function test(){console.log('hello');}";
    const options = FormatterOptions{ .indent_size = 2 };
    
    const result = try format(allocator, source, options);
    defer allocator.free(result);
    
    try testing.expect(result.len > 0);
    try testing.expect(std.mem.indexOf(u8, result, "function test()") != null);
}
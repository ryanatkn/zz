const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const extractor = @import("extractor.zig");
const visitor_mod = @import("visitor.zig");

test "JsonLanguage extract" {
    const allocator = std.testing.allocator;
    const source = "{\"key\": \"value\"}";
    const flags = ExtractionFlags{ .full = true };

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try extractor.extract(allocator, source, flags, &result);
    try std.testing.expect(std.mem.eql(u8, result.items, source));
}

test "JSON node type checking" {
    try std.testing.expect(visitor_mod.isStructuralNode("object"));
    try std.testing.expect(visitor_mod.isStructuralNode("array"));
    try std.testing.expect(!visitor_mod.isStructuralNode("string"));

    try std.testing.expect(visitor_mod.isTypedValue("string"));
    try std.testing.expect(visitor_mod.isTypedValue("number"));
    try std.testing.expect(!visitor_mod.isTypedValue("document"));
}

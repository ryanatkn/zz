const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const extractor = @import("extractor.zig");

test "CssLanguage selector extraction" {
    const allocator = std.testing.allocator;
    const source =
        \\.class { color: red; }
        \\#id { background: blue; }
        \\@media screen { .mobile { font-size: 12px; } }
    ;

    const flags = ExtractionFlags{ .signatures = true };

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try extractor.extract(allocator, source, flags, &result);
    try std.testing.expect(std.mem.indexOf(u8, result.items, ".class") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "#id") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "@media") != null);
}

test "CSS import extraction" {
    const allocator = std.testing.allocator;
    const source =
        \\@import "reset.css";
        \\@use "variables" as vars;
        \\.class { color: red; }
    ;

    const flags = ExtractionFlags{ .imports = true };

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try extractor.extract(allocator, source, flags, &result);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "@import") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.items, "@use") != null);
    // Should not include regular CSS rules
    try std.testing.expect(std.mem.indexOf(u8, result.items, ".class") == null);
}

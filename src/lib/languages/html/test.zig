const std = @import("std");
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const extractor = @import("extractor.zig");
const formatter = @import("formatter.zig");

test "HTML extraction with structure flags" {
    const allocator = std.testing.allocator;
    const source =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>Test</title>
        \\</head>
        \\<body>
        \\  <div class="container">Content</div>
        \\</body>
        \\</html>
    ;

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    const flags = ExtractionFlags{ .structure = true };
    try extractor.extract(allocator, source, flags, &result);

    const output = result.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "<html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "<div") != null);
}

test "HTML formatting basic" {
    const allocator = std.testing.allocator;
    const source = "<div><p>Hello</p></div>";

    const options = FormatterOptions{};
    const formatted = try formatter.format(allocator, source, options);
    defer allocator.free(formatted);

    // Should have proper indentation
    try std.testing.expect(std.mem.indexOf(u8, formatted, "<div>") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "    <p>") != null);
}

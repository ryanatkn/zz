const std = @import("std");
const testing = std.testing;
const ExtractionFlags = @import("../../language/flags.zig").ExtractionFlags;
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

// Import the modules to test
const extract = @import("extractor.zig").extract;
const format = @import("formatter.zig").format;

test "Svelte script extraction" {
    const allocator = testing.allocator;
    const source =
        \\<script>
        \\  function handleClick() {
        \\    console.log('clicked');
        \\  }
        \\  
        \\  const name = 'world';
        \\</script>
        \\
        \\<div>
        \\  <button on:click={handleClick}>Hello {name}!</button>
        \\</div>
    ;

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    const flags = ExtractionFlags{ .signatures = true };
    try extract(allocator, source, flags, &result);

    // Should contain JavaScript function from script section
    try testing.expect(std.mem.indexOf(u8, result.items, "function handleClick") != null);
}

test "Svelte basic formatting" {
    const allocator = testing.allocator;
    const source =
        \\<div><p>Hello</p></div>
    ;
    const options = FormatterOptions{ .indent_size = 2 };

    const result = try format(allocator, source, options);
    defer allocator.free(result);

    // Should contain formatted HTML
    try testing.expect(result.len > 0);
    try testing.expect(std.mem.indexOf(u8, result, "<div>") != null);
}

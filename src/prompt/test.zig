test {
    _ = @import("main.zig");
    _ = @import("builder.zig");
    _ = @import("config.zig");
    _ = @import("fence.zig");
    _ = @import("glob.zig");
    _ = @import("test/builder_test.zig");
    _ = @import("test/config_test.zig");
    _ = @import("test/directory_support_test.zig");
    _ = @import("test/edge_cases_test.zig");
    _ = @import("test/explicit_ignore_test.zig");
    _ = @import("test/extraction_test.zig");
    _ = @import("test/file_content_test.zig");
    _ = @import("test/flag_combinations_test.zig");
    _ = @import("test/glob_edge_test.zig");
    _ = @import("test/glob_test.zig");
    _ = @import("test/large_files_test.zig");
    _ = @import("test/nested_braces_integration_test.zig");
    _ = @import("test/security_test.zig");
    _ = @import("test/special_chars_test.zig");
    _ = @import("test/symlink_test.zig");
}

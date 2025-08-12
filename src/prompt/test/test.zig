const std = @import("std");

// Import all test files
pub const edge_cases = @import("edge_cases_test.zig");
pub const special_chars = @import("special_chars_test.zig");
pub const symlink = @import("symlink_test.zig");
pub const large_files = @import("large_files_test.zig");
pub const flag_combinations = @import("flag_combinations_test.zig");
pub const file_content = @import("file_content_test.zig");
pub const security = @import("security_test.zig");
pub const glob_edge = @import("glob_edge_test.zig");
pub const nested_braces_integration = @import("nested_braces_integration_test.zig");
pub const explicit_ignore = @import("explicit_ignore_test.zig");
pub const directory_support = @import("directory_support_test.zig");

test {
    // Reference all test modules to ensure they run
    _ = edge_cases;
    _ = special_chars;
    _ = symlink;
    _ = large_files;
    _ = flag_combinations;
    _ = file_content;
    _ = security;
    _ = glob_edge;
    _ = nested_braces_integration;
    _ = explicit_ignore;
    _ = directory_support;
}

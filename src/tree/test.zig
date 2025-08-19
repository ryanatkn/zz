test {
    _ = @import("main.zig");
    _ = @import("config.zig");
    _ = @import("entry.zig");
    _ = @import("filter.zig");
    _ = @import("formatter.zig");
    _ = @import("walker.zig");
    _ = @import("test/concurrency_test.zig");
    _ = @import("test/config_test.zig");
    _ = @import("test/edge_cases_test.zig");
    _ = @import("test/filter_test.zig");
    _ = @import("test/formatter_test.zig");
    _ = @import("test/integration_test.zig");
    _ = @import("test/path_builder_test.zig");
    _ = @import("test/performance_test.zig");
    _ = @import("test/testability_test.zig");
    _ = @import("test/walker_test.zig");
}

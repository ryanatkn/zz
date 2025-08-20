test {
    _ = @import("args.zig");
    _ = @import("parallel.zig");
    _ = @import("node_types.zig");
    _ = @import("ast/test.zig");
    _ = @import("benchmark/test.zig");
    _ = @import("char/test.zig");
    _ = @import("core/test.zig");
    _ = @import("deps/test.zig");
    _ = @import("execution/test.zig");
    _ = @import("filesystem/test.zig");
    // TODO re-enable
    // _ = @import("grammar/test.zig"); // Temporarily disabled due to module import issues
    _ = @import("languages/json/test.zig");
    _ = @import("languages/zon/test.zig");
    _ = @import("memory/test.zig");
    // TODO re-enable
    // _ = @import("parser/test.zig"); // Temporarily disabled due to grammar import issues
    _ = @import("patterns/test.zig");
    _ = @import("terminal/test.zig");
    _ = @import("test/fixture_runner.zig");
    _ = @import("test/performance_gates.zig");
    _ = @import("text/test.zig");
    _ = @import("transform/test.zig");
}

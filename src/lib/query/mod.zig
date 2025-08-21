/// Query Engine with SQL-like DSL for fact streams
/// 
/// Provides powerful query capabilities over fact stores with optimization
/// and streaming execution support.
const std = @import("std");

// Core query types
pub const Query = @import("query.zig").Query;
pub const QueryBuilder = @import("builder.zig").QueryBuilder;
pub const QueryExecutor = @import("executor.zig").QueryExecutor;
pub const QueryOptimizer = @import("optimizer.zig").QueryOptimizer;
pub const QueryPlanner = @import("planner.zig").QueryPlanner;

// Query operators
pub const Op = @import("operators.zig").Op;
pub const Field = @import("operators.zig").Field;
pub const Direction = @import("operators.zig").Direction;
pub const Aggregation = @import("operators.zig").Aggregation;

// Result types
pub const QueryResult = @import("executor.zig").QueryResult;
pub const QueryPlan = @import("planner.zig").QueryPlan;
pub const QueryStats = @import("executor.zig").QueryStats;

// Re-export fact types for convenience
pub const Fact = @import("../fact/mod.zig").Fact;
pub const FactStore = @import("../fact/mod.zig").FactStore;
pub const Predicate = @import("../fact/mod.zig").Predicate;

test {
    _ = @import("test.zig");
}
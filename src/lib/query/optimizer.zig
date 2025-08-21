/// Query optimization logic
const std = @import("std");
const Allocator = std.mem.Allocator;

const Query = @import("query.zig").Query;
const Condition = @import("query.zig").Condition;
const SimpleCondition = @import("query.zig").SimpleCondition;
const CompositeCondition = @import("query.zig").CompositeCondition;
const SelectClause = @import("query.zig").SelectClause;

const Op = @import("operators.zig").Op;
const Field = @import("operators.zig").Field;
const Predicate = @import("../fact/mod.zig").Predicate;

const QueryIndex = @import("../cache/mod.zig").QueryIndex;
const FactStore = @import("../fact/mod.zig").FactStore;

/// Query optimizer
pub const QueryOptimizer = struct {
    allocator: Allocator,
    index: ?*QueryIndex = null,
    stats: OptimizerStats = .{},
    
    pub fn init(allocator: Allocator) QueryOptimizer {
        return .{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *QueryOptimizer) void {
        _ = self;
    }
    
    /// Set the query index for optimization
    pub fn setIndex(self: *QueryOptimizer, index: *QueryIndex) void {
        self.index = index;
    }
    
    /// Optimize a query
    pub fn optimize(self: *QueryOptimizer, query: *const Query) !Query {
        var optimized = try query.clone(self.allocator);
        
        // Apply optimization passes
        try self.predicatePushdown(&optimized);
        try self.constantFolding(&optimized);
        try self.indexSelection(&optimized);
        try self.limitPushdown(&optimized);
        
        return optimized;
    }
    
    /// Estimate query cost
    pub fn estimateCost(self: *QueryOptimizer, query: *const Query) f64 {
        var cost: f64 = 0;
        
        // Base cost for scanning
        const store = @as(*FactStore, @ptrCast(@alignCast(query.from orelse return 1000000)));
        const total_facts = @as(f64, @floatFromInt(store.count()));
        cost += total_facts;
        
        // Reduce cost if using index
        if (self.canUseIndex(query)) {
            cost *= 0.1; // Index reduces cost by 90%
        }
        
        // WHERE clause selectivity
        if (query.where) |where| {
            const selectivity = self.estimateSelectivity(&where.condition);
            cost *= selectivity;
        }
        
        // Sorting cost
        if (query.order_by) |order_by| {
            const rows = cost;
            cost += rows * @log2(rows + 1) * @as(f64, @floatFromInt(order_by.len));
        }
        
        // Grouping cost
        if (query.group_by) |group_by| {
            cost += cost * 0.5 * @as(f64, @floatFromInt(group_by.len));
        }
        
        return cost;
    }
    
    /// Select the best index for the query
    pub fn selectIndex(self: *QueryOptimizer, query: *const Query) ?IndexType {
        if (self.index == null) return null;
        
        // Check for predicate index usage
        switch (query.select) {
            .predicates => |predicates| {
                if (predicates.len == 1) {
                    return .{ .predicate = predicates[0] };
                }
            },
            else => {},
        }
        
        // Check WHERE clause for index opportunities
        if (query.where) |where| {
            if (self.findIndexableCondition(&where.condition)) |index_type| {
                return index_type;
            }
        }
        
        return null;
    }
    
    // Optimization passes
    
    /// Push predicates down to reduce data scanned
    fn predicatePushdown(self: *QueryOptimizer, query: *Query) !void {
        // If we have WHERE conditions on predicates, convert to SELECT predicates
        if (query.where) |where| {
            if (query.select == .all) {
                if (extractPredicateFilter(&where.condition)) |pred| {
                    const predicates = try self.allocator.alloc(Predicate, 1);
                    predicates[0] = pred;
                    query.select = SelectClause{ .predicates = predicates };
                    self.stats.predicate_pushdowns += 1;
                }
            }
        }
    }
    
    /// Fold constant expressions
    fn constantFolding(self: *QueryOptimizer, query: *Query) !void {
        _ = self;
        _ = query;
        // TODO: Implement constant folding
        // For now, no constants to fold in our simple query structure
    }
    
    /// Select best index for query
    fn indexSelection(self: *QueryOptimizer, query: *Query) !void {
        if (self.selectIndex(query)) |index_type| {
            query.metadata.hints.no_cache = false;
            self.stats.index_selections += 1;
            _ = index_type;
        }
    }
    
    /// Push LIMIT down to reduce intermediate results
    fn limitPushdown(self: *QueryOptimizer, query: *Query) !void {
        if (query.limit_) |limit| {
            // If no sorting or grouping, we can stop early
            if (query.order_by == null and query.group_by == null) {
                query.metadata.hints.streaming = true;
                self.stats.limit_pushdowns += 1;
            }
            _ = limit;
        }
    }
    
    // Helper functions
    
    /// Check if query can use an index
    fn canUseIndex(self: *QueryOptimizer, query: *const Query) bool {
        return self.selectIndex(query) != null;
    }
    
    /// Estimate selectivity of a condition (0.0 to 1.0)
    fn estimateSelectivity(self: *QueryOptimizer, condition: *const Condition) f64 {
        return switch (condition.*) {
            .simple => |simple| estimateSimpleSelectivity(simple),
            .composite => |composite| self.estimateCompositeSelectivity(composite),
            .not => 0.9, // NOT conditions are usually less selective
        };
    }
    
    fn estimateSimpleSelectivity(condition: SimpleCondition) f64 {
        // Heuristic selectivity estimates
        return switch (condition.op) {
            .eq => switch (condition.field) {
                .predicate => 0.05, // Predicates are highly selective
                .id => 0.001, // ID is unique
                .confidence => 0.3, // Confidence varies
                else => 0.1,
            },
            .neq => 0.95,
            .lt, .lte, .gt, .gte => 0.5,
            .between => 0.2,
            .in => 0.1,
            .not_in => 0.9,
            .like => 0.3,
            .not_like => 0.7,
            .is_null => 0.1,
            .is_not_null => 0.9,
            else => 0.5,
        };
    }
    
    fn estimateCompositeSelectivity(self: *QueryOptimizer, condition: CompositeCondition) f64 {
        var selectivity: f64 = if (condition.op == .and_op) 1.0 else 0.0;
        
        for (condition.conditions) |cond| {
            const cond_selectivity = self.estimateSelectivity(&cond);
            if (condition.op == .and_op) {
                selectivity *= cond_selectivity;
            } else {
                selectivity = selectivity + cond_selectivity - (selectivity * cond_selectivity);
            }
        }
        
        return selectivity;
    }
    
    /// Find an indexable condition in the WHERE clause
    fn findIndexableCondition(self: *QueryOptimizer, condition: *const Condition) ?IndexType {
        return switch (condition.*) {
            .simple => |simple| {
                if (simple.field == .predicate and simple.op == .eq) {
                    switch (simple.value) {
                        .predicate => |pred| return .{ .predicate = pred },
                        else => {},
                    }
                }
                if (simple.field == .confidence and (simple.op == .gte or simple.op == .between)) {
                    return .confidence_range;
                }
                return null;
            },
            .composite => |composite| {
                // Look for indexable conditions in AND chains
                if (composite.op == .and_op) {
                    for (composite.conditions) |cond| {
                        if (self.findIndexableCondition(&cond)) |index_type| {
                            return index_type;
                        }
                    }
                }
                return null;
            },
            .not => null,
        };
    }
    
    /// Extract predicate filter from condition
    fn extractPredicateFilter(condition: *const Condition) ?Predicate {
        return switch (condition.*) {
            .simple => |simple| {
                if (simple.field == .predicate and simple.op == .eq) {
                    switch (simple.value) {
                        .predicate => |pred| return pred,
                        else => {},
                    }
                }
                return null;
            },
            .composite => |composite| {
                if (composite.op == .and_op) {
                    for (composite.conditions) |cond| {
                        if (extractPredicateFilter(&cond)) |pred| {
                            return pred;
                        }
                    }
                }
                return null;
            },
            .not => null,
        };
    }
};

/// Index types that can be used
const IndexType = union(enum) {
    predicate: Predicate,
    confidence_range,
    span_range,
};

/// Optimizer statistics
pub const OptimizerStats = struct {
    predicate_pushdowns: usize = 0,
    constant_folds: usize = 0,
    index_selections: usize = 0,
    limit_pushdowns: usize = 0,
};
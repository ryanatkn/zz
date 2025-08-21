/// Query AST representation
const std = @import("std");
const Allocator = std.mem.Allocator;

const Op = @import("operators.zig").Op;
const Field = @import("operators.zig").Field;
const Value = @import("operators.zig").Value;
const Direction = @import("operators.zig").Direction;
const Aggregation = @import("operators.zig").Aggregation;
const Predicate = @import("../fact/mod.zig").Predicate;

/// Query AST node representing a complete query
pub const Query = struct {
    allocator: Allocator,

    // SELECT clause
    select: SelectClause,

    // FROM clause (fact store reference)
    from: ?*anyopaque = null,

    // WHERE clause
    where: ?WhereClause = null,

    // GROUP BY clause
    group_by: ?[]const Field = null,

    // HAVING clause (for aggregations)
    having: ?HavingClause = null,

    // ORDER BY clause
    order_by: ?[]const OrderBy = null,

    // LIMIT/OFFSET
    limit_: ?usize = null,
    offset: ?usize = null,

    // Query metadata
    metadata: QueryMetadata = .{},

    pub fn init(allocator: Allocator) Query {
        return .{
            .allocator = allocator,
            .select = .all,
        };
    }

    pub fn deinit(self: *Query) void {
        if (self.where) |*w| w.deinit(self.allocator);
        if (self.group_by) |gb| self.allocator.free(gb);
        if (self.having) |*h| h.deinit(self.allocator);
        if (self.order_by) |ob| self.allocator.free(ob);
    }

    /// Clone the query for optimization passes
    pub fn clone(self: *const Query, allocator: Allocator) !Query {
        var result = Query.init(allocator);
        result.select = self.select;
        result.from = self.from;
        result.limit_ = self.limit_;
        result.offset = self.offset;
        result.metadata = self.metadata;

        if (self.where) |w| {
            result.where = try w.clone(allocator);
        }

        if (self.group_by) |gb| {
            result.group_by = try allocator.dupe(Field, gb);
        }

        if (self.having) |h| {
            result.having = try h.clone(allocator);
        }

        if (self.order_by) |ob| {
            result.order_by = try allocator.dupe(OrderBy, ob);
        }

        return result;
    }

    pub fn format(
        self: Query,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        try writer.writeAll("SELECT ");
        try self.select.format(fmt, options, writer);

        if (self.from) |_| {
            try writer.writeAll(" FROM facts");
        }

        if (self.where) |w| {
            try writer.writeAll(" WHERE ");
            try w.format(fmt, options, writer);
        }

        if (self.group_by) |gb| {
            try writer.writeAll(" GROUP BY ");
            for (gb, 0..) |field, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll(field.toString());
            }
        }

        if (self.having) |h| {
            try writer.writeAll(" HAVING ");
            try h.format(fmt, options, writer);
        }

        if (self.order_by) |ob| {
            try writer.writeAll(" ORDER BY ");
            for (ob, 0..) |order, i| {
                if (i > 0) try writer.writeAll(", ");
                try order.format(fmt, options, writer);
            }
        }

        if (self.limit_) |l| {
            try writer.print(" LIMIT {}", .{l});
        }

        if (self.offset) |o| {
            try writer.print(" OFFSET {}", .{o});
        }
    }
};

/// SELECT clause representation
pub const SelectClause = union(enum) {
    all: void,
    predicates: []const Predicate,
    fields: []const SelectField,

    pub fn format(
        self: SelectClause,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        switch (self) {
            .all => try writer.writeAll("*"),
            .predicates => |preds| {
                for (preds, 0..) |pred, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(@tagName(pred));
                }
            },
            .fields => |fields| {
                for (fields, 0..) |field, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try field.format(fmt, options, writer);
                }
            },
        }
    }
};

/// Field selection with optional aggregation
pub const SelectField = struct {
    field: Field,
    aggregation: ?Aggregation = null,
    alias: ?[]const u8 = null,

    pub fn format(
        self: SelectField,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        _ = fmt;
        _ = options;

        if (self.aggregation) |agg| {
            try writer.print("{s}({s})", .{ agg.toString(), self.field.toString() });
        } else {
            try writer.writeAll(self.field.toString());
        }

        if (self.alias) |a| {
            try writer.print(" AS {s}", .{a});
        }
    }
};

/// WHERE clause with conditions
pub const WhereClause = struct {
    condition: Condition,

    pub fn deinit(self: *WhereClause, allocator: Allocator) void {
        self.condition.deinit(allocator);
    }

    pub fn clone(self: *const WhereClause, allocator: Allocator) !WhereClause {
        return .{
            .condition = try self.condition.clone(allocator),
        };
    }

    pub fn format(
        self: WhereClause,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        try self.condition.format(fmt, options, writer);
    }
};

/// Condition tree for WHERE/HAVING clauses
pub const Condition = union(enum) {
    simple: SimpleCondition,
    composite: CompositeCondition,
    not: *Condition,

    pub fn deinit(self: *Condition, allocator: Allocator) void {
        switch (self.*) {
            .simple => {},
            .composite => |*c| c.deinit(allocator),
            .not => |n| {
                n.deinit(allocator);
                allocator.destroy(n);
            },
        }
    }

    pub fn clone(self: *const Condition, allocator: Allocator) error{OutOfMemory}!Condition {
        return switch (self.*) {
            .simple => |s| .{ .simple = s },
            .composite => |c| .{ .composite = try c.clone(allocator) },
            .not => |n| blk: {
                const cloned = try allocator.create(Condition);
                cloned.* = try n.clone(allocator);
                break :blk .{ .not = cloned };
            },
        };
    }

    pub fn format(
        self: Condition,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        switch (self) {
            .simple => |s| try s.format(fmt, options, writer),
            .composite => |c| try c.format(fmt, options, writer),
            .not => |n| {
                try writer.writeAll("NOT (");
                try n.format(fmt, options, writer);
                try writer.writeAll(")");
            },
        }
    }
};

/// Simple field-operator-value condition
pub const SimpleCondition = struct {
    field: Field,
    op: Op,
    value: Value,

    pub fn format(
        self: SimpleCondition,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        try writer.print("{s} {s} ", .{ self.field.toString(), self.op.toString() });
        try self.value.format(fmt, options, writer);
    }
};

/// Composite condition with AND/OR
pub const CompositeCondition = struct {
    op: enum { and_op, or_op },
    conditions: []Condition,

    pub fn deinit(self: *CompositeCondition, allocator: Allocator) void {
        for (self.conditions) |*cond| {
            cond.deinit(allocator);
        }
        allocator.free(self.conditions);
    }

    pub fn clone(self: *const CompositeCondition, allocator: Allocator) error{OutOfMemory}!CompositeCondition {
        const conditions = try allocator.alloc(Condition, self.conditions.len);
        for (self.conditions, 0..) |*cond, i| {
            conditions[i] = try cond.clone(allocator);
        }
        return .{
            .op = self.op,
            .conditions = conditions,
        };
    }

    pub fn format(
        self: CompositeCondition,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        try writer.writeAll("(");
        for (self.conditions, 0..) |cond, i| {
            if (i > 0) {
                const op_str = if (self.op == .and_op) " AND " else " OR ";
                try writer.writeAll(op_str);
            }
            try cond.format(fmt, options, writer);
        }
        try writer.writeAll(")");
    }
};

/// HAVING clause for aggregations
pub const HavingClause = struct {
    condition: AggregateCondition,

    pub fn deinit(self: *HavingClause, allocator: Allocator) void {
        _ = self;
        _ = allocator;
        // AggregateCondition doesn't allocate
    }

    pub fn clone(self: *const HavingClause, allocator: Allocator) !HavingClause {
        _ = allocator;
        return self.*;
    }

    pub fn format(
        self: HavingClause,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        try self.condition.format(fmt, options, writer);
    }
};

/// Condition for aggregate functions
pub const AggregateCondition = struct {
    aggregation: Aggregation,
    field: Field,
    op: Op,
    value: Value,

    pub fn format(
        self: AggregateCondition,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        try writer.print("{s}({s}) {s} ", .{
            self.aggregation.toString(),
            self.field.toString(),
            self.op.toString(),
        });
        try self.value.format(fmt, options, writer);
    }
};

/// ORDER BY specification
pub const OrderBy = struct {
    field: Field,
    direction: Direction,

    pub fn format(
        self: OrderBy,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        _ = fmt;
        _ = options;

        try writer.print("{s} {s}", .{
            self.field.toString(),
            self.direction.toString(),
        });
    }
};

/// Query metadata for optimization hints
pub const QueryMetadata = struct {
    // Estimated result size
    estimated_rows: ?usize = null,

    // Query source (for debugging)
    source: ?[]const u8 = null,

    // Optimization hints
    hints: struct {
        no_cache: bool = false,
        parallel: bool = false,
        streaming: bool = true,
    } = .{},

    // Statistics collection
    collect_stats: bool = false,
};

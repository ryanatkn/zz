/// Query operators and field definitions
const std = @import("std");
const Predicate = @import("../fact/mod.zig").Predicate;

/// Comparison operators for WHERE clauses
pub const Op = enum {
    // Equality
    eq, // equals
    neq, // not equals

    // Comparison
    lt, // less than
    lte, // less than or equal
    gt, // greater than
    gte, // greater than or equal

    // Range
    between,
    not_between,

    // Set operations
    in,
    not_in,

    // Pattern matching
    like,
    not_like,

    // Null checks
    is_null,
    is_not_null,

    // Logical
    and_op,
    or_op,
    not_op,

    pub fn toString(self: Op) []const u8 {
        return switch (self) {
            .eq => "=",
            .neq => "!=",
            .lt => "<",
            .lte => "<=",
            .gt => ">",
            .gte => ">=",
            .between => "BETWEEN",
            .not_between => "NOT BETWEEN",
            .in => "IN",
            .not_in => "NOT IN",
            .like => "LIKE",
            .not_like => "NOT LIKE",
            .is_null => "IS NULL",
            .is_not_null => "IS NOT NULL",
            .and_op => "AND",
            .or_op => "OR",
            .not_op => "NOT",
        };
    }
};

/// Fields that can be queried
pub const Field = enum {
    // Fact fields
    id,
    subject,
    predicate,
    object,
    confidence,

    // Span fields (via subject)
    span_start,
    span_end,
    span_length,

    // Value fields (via object)
    value_type,
    value_number,
    value_atom,

    // Metadata
    generation,
    timestamp,

    pub fn toString(self: Field) []const u8 {
        return switch (self) {
            .id => "id",
            .subject => "subject",
            .predicate => "predicate",
            .object => "object",
            .confidence => "confidence",
            .span_start => "span.start",
            .span_end => "span.end",
            .span_length => "span.length",
            .value_type => "value.type",
            .value_number => "value.number",
            .value_atom => "value.atom",
            .generation => "generation",
            .timestamp => "timestamp",
        };
    }
};

/// Sort direction for ORDER BY
pub const Direction = enum {
    ascending,
    descending,

    pub fn toString(self: Direction) []const u8 {
        return switch (self) {
            .ascending => "ASC",
            .descending => "DESC",
        };
    }
};

/// Aggregation functions
pub const Aggregation = enum {
    count,
    sum,
    avg,
    min,
    max,
    first,
    last,

    pub fn toString(self: Aggregation) []const u8 {
        return switch (self) {
            .count => "COUNT",
            .sum => "SUM",
            .avg => "AVG",
            .min => "MIN",
            .max => "MAX",
            .first => "FIRST",
            .last => "LAST",
        };
    }
};

/// Value type for query conditions
pub const Value = union(enum) {
    none: void,
    number: i64,
    float: f64,
    string: []const u8,
    atom: u32,
    predicate: Predicate,
    boolean: bool,
    span: struct { start: u32, end: u32 },
    range: struct { min: f64, max: f64 },
    list: []const Value,

    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) anyerror!void {
        switch (self) {
            .none => try writer.writeAll("NULL"),
            .number => |n| try writer.print("{}", .{n}),
            .float => |f| try writer.print("{d:.2}", .{f}),
            .string => |s| try writer.print("'{s}'", .{s}),
            .atom => |a| try writer.print("atom#{}", .{a}),
            .predicate => |p| try writer.print("{s}", .{@tagName(p)}),
            .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
            .span => |s| try writer.print("[{}:{}]", .{ s.start, s.end }),
            .range => |r| try writer.print("{d:.2}..{d:.2}", .{ r.min, r.max }),
            .list => |l| {
                try writer.writeAll("(");
                for (l, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try item.format(fmt, options, writer);
                }
                try writer.writeAll(")");
            },
        }
    }
};

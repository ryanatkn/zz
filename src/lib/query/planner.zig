/// Query planning and execution strategy
const std = @import("std");
const Allocator = std.mem.Allocator;

const Query = @import("query.zig").Query;
const SelectClause = @import("query.zig").SelectClause;
const QueryOptimizer = @import("optimizer.zig").QueryOptimizer;
const Field = @import("operators.zig").Field;

/// Query execution plan
pub const QueryPlan = struct {
    allocator: Allocator,
    root: PlanNode,
    estimated_cost: f64,
    estimated_rows: usize,
    
    pub fn init(allocator: Allocator, root: PlanNode) QueryPlan {
        return .{
            .allocator = allocator,
            .root = root,
            .estimated_cost = 0,
            .estimated_rows = 0,
        };
    }
    
    pub fn deinit(self: *QueryPlan) void {
        self.root.deinit(self.allocator);
    }
    
    pub fn format(
        self: QueryPlan,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.writeAll("QueryPlan {\n");
        try self.formatNode(writer, &self.root, 1);
        try writer.print("  Estimated Cost: {d:.2}\n", .{self.estimated_cost});
        try writer.print("  Estimated Rows: {}\n", .{self.estimated_rows});
        try writer.writeAll("}");
    }
    
    fn formatNode(self: QueryPlan, writer: anytype, node: *const PlanNode, depth: usize) !void {
        // Indent
        for (0..depth) |_| {
            try writer.writeAll("  ");
        }
        
        // Node type
        try writer.print("-> ", .{});
        try node.type.format("", .{}, writer);
        try writer.print(" ", .{});
        
        // Node details
        switch (node.type) {
            .scan => {
                if (node.scan_type) |st| {
                    try writer.print("(", .{});
                    try st.format("", .{}, writer);
                    try writer.print(")", .{});
                }
            },
            .filter => {
                try writer.writeAll("(WHERE)");
            },
            .sort => {
                try writer.writeAll("(ORDER BY)");
            },
            .limit => {
                if (node.limit_count) |l| {
                    try writer.print("({})", .{l});
                }
            },
            .aggregate => {
                try writer.writeAll("(GROUP BY)");
            },
            .project => {
                try writer.writeAll("(SELECT)");
            },
            .index_scan => {
                try writer.writeAll("(INDEX)");
            },
            .hash_join => {
                try writer.writeAll("(JOIN)");
            },
        }
        
        try writer.print(" [cost: {d:.2}, rows: {}]\n", .{ node.cost, node.estimated_rows });
        
        // Children
        for (node.children) |child| {
            try self.formatNode(writer, &child, depth + 1);
        }
    }
};

/// Plan node types
pub const PlanNodeType = enum {
    scan,       // Table/fact scan
    index_scan, // Index scan
    filter,     // WHERE filtering
    sort,       // ORDER BY sorting
    limit,      // LIMIT/OFFSET
    aggregate,  // GROUP BY aggregation
    project,    // SELECT projection
    hash_join,  // Hash join (future)
    
    pub fn format(
        self: PlanNodeType,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        const name = switch (self) {
            .scan => "Scan",
            .index_scan => "IndexScan",
            .filter => "Filter",
            .sort => "Sort",
            .limit => "Limit",
            .aggregate => "Aggregate",
            .project => "Project",
            .hash_join => "HashJoin",
        };
        try writer.writeAll(name);
    }
};

/// Scan types
pub const ScanType = enum {
    full,      // Full table scan
    predicate, // Predicate-filtered scan
    range,     // Range scan
    
    pub fn format(
        self: ScanType,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        const name = switch (self) {
            .full => "full",
            .predicate => "predicate",
            .range => "range",
        };
        try writer.writeAll(name);
    }
};

/// Query plan node
pub const PlanNode = struct {
    type: PlanNodeType,
    children: []PlanNode,
    cost: f64,
    estimated_rows: usize,
    
    // Node-specific data
    scan_type: ?ScanType = null,
    filter_condition: ?*anyopaque = null,
    sort_fields: ?[]const Field = null,
    limit_count: ?usize = null,
    aggregate_fields: ?[]const Field = null,
    
    pub fn init(node_type: PlanNodeType) PlanNode {
        return .{
            .type = node_type,
            .children = &[_]PlanNode{},
            .cost = 0,
            .estimated_rows = 0,
        };
    }
    
    pub fn deinit(self: *PlanNode, allocator: Allocator) void {
        for (self.children) |*child| {
            child.deinit(allocator);
        }
        if (self.children.len > 0) {
            allocator.free(self.children);
        }
    }
};

/// Query planner
pub const QueryPlanner = struct {
    allocator: Allocator,
    optimizer: *QueryOptimizer,
    
    pub fn init(allocator: Allocator, optimizer: *QueryOptimizer) QueryPlanner {
        return .{
            .allocator = allocator,
            .optimizer = optimizer,
        };
    }
    
    pub fn deinit(self: *QueryPlanner) void {
        _ = self;
    }
    
    /// Create execution plan for query
    pub fn createPlan(self: *QueryPlanner, query: *const Query) !QueryPlan {
        // Start with base scan
        var root = try self.createScanNode(query);
        
        // Add filter node if WHERE clause exists
        if (query.where) |_| {
            root = try self.wrapWithNode(root, .filter);
        }
        
        // Add aggregate node if GROUP BY exists
        if (query.group_by) |group_by| {
            root = try self.wrapWithNode(root, .aggregate);
            root.aggregate_fields = group_by;
        }
        
        // Add sort node if ORDER BY exists
        if (query.order_by) |order_by| {
            root = try self.wrapWithNode(root, .sort);
            const fields = try self.allocator.alloc(Field, order_by.len);
            for (order_by, 0..) |ob, i| {
                fields[i] = ob.field;
            }
            root.sort_fields = fields;
        }
        
        // Add limit node if LIMIT exists
        if (query.limit_) |limit| {
            root = try self.wrapWithNode(root, .limit);
            root.limit_count = limit;
        }
        
        // Add projection node for SELECT
        root = try self.wrapWithNode(root, .project);
        
        // Calculate costs
        self.calculateCosts(&root);
        
        var plan = QueryPlan.init(self.allocator, root);
        plan.estimated_cost = root.cost;
        plan.estimated_rows = root.estimated_rows;
        
        return plan;
    }
    
    /// Create base scan node
    fn createScanNode(self: *QueryPlanner, query: *const Query) !PlanNode {
        var node = PlanNode.init(.scan);
        
        // Determine scan type based on query
        if (self.optimizer.selectIndex(query)) |_| {
            node.type = .index_scan;
            node.scan_type = .predicate;
        } else {
            switch (query.select) {
                .all => node.scan_type = .full,
                .predicates => node.scan_type = .predicate,
                .fields => node.scan_type = .full,
            }
        }
        
        return node;
    }
    
    /// Wrap a node with a parent node
    fn wrapWithNode(self: *QueryPlanner, child: PlanNode, node_type: PlanNodeType) !PlanNode {
        var parent = PlanNode.init(node_type);
        const children = try self.allocator.alloc(PlanNode, 1);
        children[0] = child;
        parent.children = children;
        return parent;
    }
    
    /// Calculate costs for plan nodes (bottom-up)
    fn calculateCosts(self: *QueryPlanner, node: *PlanNode) void {
        // First calculate children
        for (node.children) |*child| {
            self.calculateCosts(child);
        }
        
        // Then calculate this node
        switch (node.type) {
            .scan, .index_scan => {
                // Base cost depends on scan type
                node.cost = switch (node.scan_type orelse .full) {
                    .full => 1000,
                    .predicate => 100,
                    .range => 200,
                };
                node.estimated_rows = 1000; // TODO: Get from statistics
            },
            .filter => {
                if (node.children.len > 0) {
                    const child = &node.children[0];
                    node.cost = child.cost + @as(f64, @floatFromInt(child.estimated_rows)) * 0.1;
                    node.estimated_rows = @intFromFloat(@as(f64, @floatFromInt(child.estimated_rows)) * 0.3); // 30% selectivity estimate
                }
            },
            .sort => {
                if (node.children.len > 0) {
                    const child = &node.children[0];
                    const rows = @as(f64, @floatFromInt(child.estimated_rows));
                    node.cost = child.cost + rows * @log2(rows + 1);
                    node.estimated_rows = child.estimated_rows;
                }
            },
            .limit => {
                if (node.children.len > 0) {
                    const child = &node.children[0];
                    node.cost = child.cost;
                    node.estimated_rows = @min(node.limit_count orelse 0, child.estimated_rows);
                }
            },
            .aggregate => {
                if (node.children.len > 0) {
                    const child = &node.children[0];
                    node.cost = child.cost + @as(f64, @floatFromInt(child.estimated_rows)) * 0.5;
                    node.estimated_rows = @max(1, child.estimated_rows / 10); // Estimate 10:1 reduction
                }
            },
            .project => {
                if (node.children.len > 0) {
                    const child = &node.children[0];
                    node.cost = child.cost + @as(f64, @floatFromInt(child.estimated_rows)) * 0.01;
                    node.estimated_rows = child.estimated_rows;
                }
            },
            .hash_join => {
                // TODO: Implement join cost calculation
                node.cost = 10000;
                node.estimated_rows = 1000;
            },
        }
    }
    
    /// Explain plan as string
    pub fn explain(self: *QueryPlanner, query: *const Query) ![]u8 {
        const plan = try self.createPlan(query);
        defer plan.deinit();
        
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        
        try plan.format("", .{}, buffer.writer());
        
        return buffer.toOwnedSlice();
    }
};
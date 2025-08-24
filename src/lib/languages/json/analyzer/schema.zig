/// JSON Analyzer - Schema Analysis and Type Inference
///
/// Specialized module for schema extraction and type inference
const std = @import("std");
// Use local JSON AST
const json_ast = @import("../ast/mod.zig");
const Node = json_ast.Node;

// Forward declare JsonAnalyzer from analyzer_core.zig
const JsonAnalyzer = @import("core.zig").JsonAnalyzer;

/// JSON Schema representation for type inference
pub const JsonSchema = struct {
    schema_type: SchemaType,
    properties: ?std.HashMap([]const u8, JsonSchema, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    items: ?*JsonSchema,
    nullable: bool = false,
    examples: std.ArrayList([]const u8),

    pub const SchemaType = enum {
        string,
        number,
        boolean,
        null,
        object,
        array,
        any,
    };

    pub fn deinit(self: *JsonSchema, allocator: std.mem.Allocator) void {
        if (self.properties) |*props| {
            var iter = props.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            props.deinit();
        }

        if (self.items) |items| {
            items.deinit(allocator);
            allocator.destroy(items);
        }

        for (self.examples.items) |example| {
            allocator.free(example);
        }
        self.examples.deinit();
    }

    pub fn init(allocator: std.mem.Allocator, schema_type: SchemaType) JsonSchema {
        return JsonSchema{
            .schema_type = schema_type,
            .properties = null,
            .items = null,
            .nullable = false,
            .examples = std.ArrayList([]const u8).init(allocator),
        };
    }
};

// =========================================================================
// Schema Analysis Methods
// =========================================================================

pub fn analyzeNode(analyzer: *JsonAnalyzer, node: *const Node, depth: u32) anyerror!JsonSchema {
    if (depth > analyzer.options.max_schema_depth) {
        return JsonSchema.init(analyzer.allocator, .any);
    }

    return switch (node.*) {
        .string => |n| blk: {
            var schema = JsonSchema.init(analyzer.allocator, .string);
            try schema.examples.append(try analyzer.allocator.dupe(u8, n.value));
            break :blk schema;
        },
        .number => |n| blk: {
            var schema = JsonSchema.init(analyzer.allocator, .number);
            try schema.examples.append(try analyzer.allocator.dupe(u8, n.raw));
            break :blk schema;
        },
        .boolean => |n| blk: {
            var schema = JsonSchema.init(analyzer.allocator, .boolean);
            try schema.examples.append(try analyzer.allocator.dupe(u8, if (n.value) "true" else "false"));
            break :blk schema;
        },
        .null => JsonSchema.init(analyzer.allocator, .null),
        .object => analyzeObject(analyzer, node, depth),
        .array => analyzeArray(analyzer, node, depth),
        else => JsonSchema.init(analyzer.allocator, .any),
    };
}

pub fn analyzeObject(analyzer: *JsonAnalyzer, node: *const Node, depth: u32) !JsonSchema {
    var schema = JsonSchema.init(analyzer.allocator, .object);
    schema.properties = std.HashMap([]const u8, JsonSchema, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(analyzer.allocator);

    const object_node = node.object;
    const properties = object_node.properties;
    if (properties.len == 0) return schema;

    for (properties) |property| {
        if (property != .property) continue;
        const prop_node = property.property;

        // Extract key name from the key node (should be a string)
        const key_name = if (prop_node.key.* == .string)
            prop_node.key.string.value
        else
            "unknown"; // fallback

        const owned_key = try analyzer.allocator.dupe(u8, key_name);
        const value_schema = try analyzeNode(analyzer, prop_node.value, depth + 1);

        try schema.properties.?.put(owned_key, value_schema);
    }

    return schema;
}

pub fn analyzeArray(analyzer: *JsonAnalyzer, node: *const Node, depth: u32) !JsonSchema {
    var schema = JsonSchema.init(analyzer.allocator, .array);

    const array_node = node.array;
    const elements = array_node.elements;
    if (elements.len == 0) {
        // Empty array - infer as any[]
        schema.items = try analyzer.allocator.create(JsonSchema);
        schema.items.?.* = JsonSchema.init(analyzer.allocator, .any);
        return schema;
    }

    if (analyzer.options.infer_array_types) {
        // Analyze first element to determine array type
        const first_element_schema = try analyzeNode(analyzer, &elements[0], depth + 1);

        // Check if all elements have the same type
        var uniform_type = true;
        for (elements[1..]) |element| {
            const element_schema = try analyzeNode(analyzer, &element, depth + 1);
            if (element_schema.schema_type != first_element_schema.schema_type) {
                uniform_type = false;
                var mutable_element_schema = element_schema;
                mutable_element_schema.deinit(analyzer.allocator);
                break;
            }
            var mutable_element_schema = element_schema;
            mutable_element_schema.deinit(analyzer.allocator);
        }

        if (uniform_type) {
            schema.items = try analyzer.allocator.create(JsonSchema);
            schema.items.?.* = first_element_schema;
        } else {
            // Mixed types - use any
            var mutable_first_schema = first_element_schema;
            mutable_first_schema.deinit(analyzer.allocator);
            schema.items = try analyzer.allocator.create(JsonSchema);
            schema.items.?.* = JsonSchema.init(analyzer.allocator, .any);
        }
    } else {
        schema.items = try analyzer.allocator.create(JsonSchema);
        schema.items.?.* = JsonSchema.init(analyzer.allocator, .any);
    }

    return schema;
}

// =========================================================================
// Schema Type Utilities
// =========================================================================

pub fn inferSchemaFromMultipleValues(analyzer: *JsonAnalyzer, values: []const Node) !JsonSchema {
    if (values.len == 0) {
        return JsonSchema.init(analyzer.allocator, .any);
    }

    // Start with the schema of the first value
    var base_schema = try analyzeNode(analyzer, &values[0], 0);
    if (values.len == 1) {
        return base_schema;
    }

    // Check compatibility with other values
    for (values[1..]) |value| {
        const value_schema = try analyzeNode(analyzer, &value, 0);

        if (base_schema.schema_type != value_schema.schema_type) {
            // Incompatible types, fall back to any
            base_schema.deinit(analyzer.allocator);
            var mutable_value_schema = value_schema;
            mutable_value_schema.deinit(analyzer.allocator);
            return JsonSchema.init(analyzer.allocator, .any);
        }

        // For compatible types, we could merge examples
        for (value_schema.examples.items) |example| {
            try base_schema.examples.append(try analyzer.allocator.dupe(u8, example));
        }

        var mutable_value_schema = value_schema;
        mutable_value_schema.deinit(analyzer.allocator);
    }

    return base_schema;
}

pub fn isSchemaCompatible(schema1: *const JsonSchema, schema2: *const JsonSchema) bool {
    // Basic type compatibility check
    if (schema1.schema_type != schema2.schema_type) {
        return false;
    }

    // For objects, check if they have compatible property structures
    if (schema1.schema_type == .object) {
        if (schema1.properties == null and schema2.properties == null) {
            return true;
        }
        if (schema1.properties == null or schema2.properties == null) {
            return false;
        }

        const props1 = schema1.properties.?;
        const props2 = schema2.properties.?;

        // Check if all properties in schema1 exist in schema2 with compatible types
        var iter = props1.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value1 = entry.value_ptr;

            if (!props2.contains(key)) {
                return false;
            }

            const value2 = props2.get(key).?;
            if (!isSchemaCompatible(value1, &value2)) {
                return false;
            }
        }
    }

    // For arrays, check if element types are compatible
    if (schema1.schema_type == .array) {
        if (schema1.items == null and schema2.items == null) {
            return true;
        }
        if (schema1.items == null or schema2.items == null) {
            return false;
        }

        return isSchemaCompatible(schema1.items.?, schema2.items.?);
    }

    return true;
}

// =========================================================================
// Schema Optimization Suggestions
// =========================================================================

pub fn generateOptimizationSuggestions(analyzer: *JsonAnalyzer, schema: *const JsonSchema) ![][]const u8 {
    var suggestions = std.ArrayList([]const u8).init(analyzer.allocator);

    switch (schema.schema_type) {
        .object => {
            if (schema.properties) |props| {
                if (props.count() > 50) {
                    try suggestions.append(try analyzer.allocator.dupe(u8, "Consider splitting large objects with >50 properties"));
                }

                // Check for properties that might be better as arrays
                var iter = props.iterator();
                while (iter.next()) |entry| {
                    const key = entry.key_ptr.*;
                    if (std.mem.startsWith(u8, key, "item") or
                        std.mem.endsWith(u8, key, "_0") or
                        std.mem.endsWith(u8, key, "_1"))
                    {
                        try suggestions.append(try std.fmt.allocPrint(analyzer.allocator, "Property '{s}' suggests array-like structure", .{key}));
                    }
                }
            }
        },
        .array => {
            if (schema.items) |items| {
                if (items.schema_type == .any) {
                    try suggestions.append(try analyzer.allocator.dupe(u8, "Array has mixed types - consider using consistent types"));
                }
            }
        },
        .string => {
            if (schema.examples.items.len > 0) {
                const first_example = schema.examples.items[0];
                if (std.mem.startsWith(u8, first_example, "http://") or
                    std.mem.startsWith(u8, first_example, "https://"))
                {
                    try suggestions.append(try analyzer.allocator.dupe(u8, "String appears to be URL - consider URL validation"));
                }
                if (std.mem.indexOf(u8, first_example, "@") != null and
                    std.mem.indexOf(u8, first_example, ".") != null)
                {
                    try suggestions.append(try analyzer.allocator.dupe(u8, "String appears to be email - consider email validation"));
                }
            }
        },
        else => {
            // No specific suggestions for other types
        },
    }

    return suggestions.toOwnedSlice();
}

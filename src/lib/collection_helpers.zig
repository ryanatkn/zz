const std = @import("std");

/// Collection helpers to eliminate duplicate ArrayList patterns across the codebase
pub const CollectionHelpers = struct {

    /// Automatically managed ArrayList with RAII cleanup
    pub fn ManagedArrayList(comptime T: type) type {
        return struct {
            const Self = @This();
            
            list: std.ArrayList(T),
            allocator: std.mem.Allocator,
            
            pub fn init(allocator: std.mem.Allocator) Self {
                return .{
                    .list = std.ArrayList(T).init(allocator),
                    .allocator = allocator,
                };
            }
            
            pub fn initWithCapacity(allocator: std.mem.Allocator, initial_capacity: usize) !Self {
                var result = Self.init(allocator);
                try result.list.ensureTotalCapacity(initial_capacity);
                return result;
            }
            
            pub fn deinit(self: *Self) void {
                self.list.deinit();
            }
            
            // Delegate common ArrayList methods
            pub fn append(self: *Self, item: T) !void {
                try self.list.append(item);
            }
            
            pub fn appendSlice(self: *Self, slice_items: []const T) !void {
                try self.list.appendSlice(slice_items);
            }
            
            pub fn insert(self: *Self, index: usize, item: T) !void {
                try self.list.insert(index, item);
            }
            
            pub fn pop(self: *Self) T {
                return self.list.pop();
            }
            
            pub fn popSafe(self: *Self) ?T {
                if (self.list.items.len == 0) return null;
                return self.list.pop();
            }
            
            pub fn popOrNull(self: *Self) ?T {
                if (self.list.items.len == 0) return null;
                return self.list.pop();
            }
            
            pub fn clearAndFree(self: *Self) void {
                self.list.clearAndFree();
            }
            
            pub fn clearRetainingCapacity(self: *Self) void {
                self.list.clearRetainingCapacity();
            }
            
            pub fn items(self: Self) []T {
                return self.list.items;
            }
            
            pub fn toOwnedSlice(self: *Self) ![]T {
                return self.list.toOwnedSlice();
            }
            
            pub fn len(self: Self) usize {
                return self.list.items.len;
            }
            
            pub fn capacity(self: Self) usize {
                return self.list.capacity;
            }
        };
    }

    /// Fluent builder pattern for ArrayLists
    pub fn ArrayListBuilder(comptime T: type) type {
        return struct {
            const Self = @This();
            
            list: ManagedArrayList(T),
            
            pub fn init(allocator: std.mem.Allocator) Self {
                return .{
                    .list = ManagedArrayList(T).init(allocator),
                };
            }
            
            pub fn withCapacity(allocator: std.mem.Allocator, capacity: usize) !Self {
                return .{
                    .list = try ManagedArrayList(T).initWithCapacity(allocator, capacity),
                };
            }
            
            pub fn add(self: *Self, item: T) !*Self {
                try self.list.append(item);
                return self;
            }
            
            pub fn addAll(self: *Self, items: []const T) !*Self {
                try self.list.appendSlice(items);
                return self;
            }
            
            pub fn build(self: *Self) ![]T {
                return self.list.toOwnedSlice();
            }
            
            pub fn buildManaged(self: Self) ManagedArrayList(T) {
                return self.list;
            }
            
            pub fn deinit(self: *Self) void {
                self.list.deinit();
            }
        };
    }

    /// Scoped allocation helper for automatic cleanup
    pub fn ScopedAllocation(comptime T: type) type {
        return struct {
            const Self = @This();
            
            allocator: std.mem.Allocator,
            ptr: ?[]T,
            
            pub fn init(allocator: std.mem.Allocator) Self {
                return .{
                    .allocator = allocator,
                    .ptr = null,
                };
            }
            
            pub fn alloc(self: *Self, size: usize) ![]T {
                self.ptr = try self.allocator.alloc(T, size);
                return self.ptr.?;
            }
            
            pub fn dupeSlice(self: *Self, slice: []const T) ![]T {
                self.ptr = try self.allocator.dupe(T, slice);
                return self.ptr.?;
            }
            
            pub fn dupeString(self: *Self, str: []const u8) ![]u8 {
                if (T != u8) @compileError("dupeString only works with u8");
                self.ptr = try self.allocator.dupe(u8, str);
                return @ptrCast(self.ptr.?);
            }
            
            pub fn get(self: Self) ?[]T {
                return self.ptr;
            }
            
            pub fn deinit(self: *Self) void {
                if (self.ptr) |ptr| {
                    self.allocator.free(ptr);
                    self.ptr = null;
                }
            }
        };
    }

    /// String list builder for common string collection patterns
    pub const StringListBuilder = struct {
        builder: ArrayListBuilder([]const u8),
        string_allocator: std.mem.Allocator,
        
        pub fn init(allocator: std.mem.Allocator) StringListBuilder {
            return .{
                .builder = ArrayListBuilder([]const u8).init(allocator),
                .string_allocator = allocator,
            };
        }
        
        pub fn addOwned(self: *StringListBuilder, string: []const u8) !*StringListBuilder {
            try self.builder.add(string);
            return self;
        }
        
        pub fn addDupe(self: *StringListBuilder, string: []const u8) !*StringListBuilder {
            const duped = try self.string_allocator.dupe(u8, string);
            _ = try self.builder.add(duped);
            return self;
        }
        
        pub fn addFmt(self: *StringListBuilder, comptime format: []const u8, args: anytype) !*StringListBuilder {
            const formatted = try std.fmt.allocPrint(self.string_allocator, format, args);
            _ = try self.builder.add(formatted);
            return self;
        }
        
        pub fn build(self: *StringListBuilder) ![][]const u8 {
            return self.builder.build();
        }
        
        pub fn buildManaged(self: StringListBuilder) ManagedArrayList([]const u8) {
            return self.builder.buildManaged();
        }
        
        pub fn deinit(self: *StringListBuilder) void {
            // Free all strings first
            for (self.builder.list.items()) |str| {
                self.string_allocator.free(str);
            }
            self.builder.deinit();
        }
    };

    /// Common collection operations as helpers
    pub const Operations = struct {
        
        /// Check if slice contains item
        pub fn contains(comptime T: type, slice: []const T, item: T) bool {
            return std.mem.indexOfScalar(T, slice, item) != null;
        }
        
        /// Remove duplicates from slice, preserving order
        pub fn deduplicate(comptime T: type, allocator: std.mem.Allocator, slice: []const T) ![]T {
            var result = ManagedArrayList(T).init(allocator);
            defer result.deinit();
            
            for (slice) |item| {
                if (!contains(T, result.items(), item)) {
                    try result.append(item);
                }
            }
            
            return result.toOwnedSlice();
        }
        
        /// Filter slice based on predicate function
        pub fn filter(
            comptime T: type, 
            allocator: std.mem.Allocator, 
            slice: []const T, 
            predicate: fn(T) bool
        ) ![]T {
            var result = ManagedArrayList(T).init(allocator);
            defer result.deinit();
            
            for (slice) |item| {
                if (predicate(item)) {
                    try result.append(item);
                }
            }
            
            return result.toOwnedSlice();
        }
        
        /// Map slice to new type using transform function
        pub fn map(
            comptime T: type,
            comptime U: type,
            allocator: std.mem.Allocator,
            slice: []const T,
            transform: fn(std.mem.Allocator, T) anyerror!U
        ) ![]U {
            var result = ManagedArrayList(U).init(allocator);
            defer result.deinit();
            
            for (slice) |item| {
                const transformed = try transform(allocator, item);
                try result.append(transformed);
            }
            
            return result.toOwnedSlice();
        }
        
        /// Join string slice with separator
        pub fn joinStrings(
            allocator: std.mem.Allocator,
            strings: []const []const u8,
            separator: []const u8
        ) ![]u8 {
            if (strings.len == 0) return try allocator.dupe(u8, "");
            if (strings.len == 1) return try allocator.dupe(u8, strings[0]);
            
            var total_len: usize = 0;
            for (strings) |str| total_len += str.len;
            total_len += separator.len * (strings.len - 1);
            
            var result = try allocator.alloc(u8, total_len);
            var pos: usize = 0;
            
            for (strings, 0..) |str, i| {
                @memcpy(result[pos..pos + str.len], str);
                pos += str.len;
                
                if (i < strings.len - 1) {
                    @memcpy(result[pos..pos + separator.len], separator);
                    pos += separator.len;
                }
            }
            
            return result;
        }
    };
};

test "ManagedArrayList basic functionality" {
    const testing = std.testing;
    
    var list = CollectionHelpers.ManagedArrayList(i32).init(testing.allocator);
    defer list.deinit();
    
    try list.append(1);
    try list.append(2);
    try list.append(3);
    
    try testing.expectEqual(@as(usize, 3), list.len());
    try testing.expectEqual(@as(i32, 1), list.items()[0]);
    try testing.expectEqual(@as(i32, 3), list.popSafe().?);
}

test "ArrayListBuilder fluent interface" {
    const testing = std.testing;
    
    var builder = CollectionHelpers.ArrayListBuilder(i32).init(testing.allocator);
    defer builder.deinit();
    
    const items = try (try (try (try builder.add(1))
        .add(2))
        .addAll(&[_]i32{ 3, 4, 5 }))
        .build();
    defer testing.allocator.free(items);
    
    try testing.expectEqual(@as(usize, 5), items.len);
    try testing.expectEqual(@as(i32, 1), items[0]);
    try testing.expectEqual(@as(i32, 5), items[4]);
}

test "ScopedAllocation automatic cleanup" {
    const testing = std.testing;
    
    // Test alloc
    {
        var scoped = CollectionHelpers.ScopedAllocation(u8).init(testing.allocator);
        defer scoped.deinit();
        
        const buffer = try scoped.alloc(10);
        try testing.expectEqual(@as(usize, 10), buffer.len);
    }
    
    // Test dupeString separately to avoid double allocation
    {
        var scoped = CollectionHelpers.ScopedAllocation(u8).init(testing.allocator);
        defer scoped.deinit();
        
        const duped = try scoped.dupeString("hello");
        try testing.expectEqualStrings("hello", duped);
    }
}

test "StringListBuilder functionality" {
    const testing = std.testing;
    
    var builder = CollectionHelpers.StringListBuilder.init(testing.allocator);
    defer builder.deinit();
    
    _ = try (try (try builder.addDupe("first"))
        .addDupe("second"))
        .addFmt("number_{d}", .{42});
    
    const items = builder.buildManaged().items();
    try testing.expectEqual(@as(usize, 3), items.len);
    try testing.expectEqualStrings("first", items[0]);
    try testing.expectEqualStrings("number_42", items[2]);
}

test "Operations helpers" {
    const testing = std.testing;
    
    // Test contains
    const slice = [_]i32{ 1, 2, 3, 4, 5 };
    try testing.expect(CollectionHelpers.Operations.contains(i32, &slice, 3));
    try testing.expect(!CollectionHelpers.Operations.contains(i32, &slice, 6));
    
    // Test deduplicate
    const duped_slice = [_]i32{ 1, 2, 2, 3, 1, 4, 3 };
    const deduped = try CollectionHelpers.Operations.deduplicate(i32, testing.allocator, &duped_slice);
    defer testing.allocator.free(deduped);
    
    try testing.expectEqual(@as(usize, 4), deduped.len);
    try testing.expectEqual(@as(i32, 1), deduped[0]);
    try testing.expectEqual(@as(i32, 4), deduped[3]);
}
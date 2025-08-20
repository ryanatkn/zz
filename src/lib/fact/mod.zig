/// Fact module - Universal data unit for the stream-first architecture
/// Provides 24-byte Fact struct, 8-byte Value union, and append-only FactStore
const std = @import("std");

// Core fact type and ID
pub const Fact = @import("fact.zig").Fact;
pub const FactId = @import("fact.zig").FactId;
pub const Generation = @import("fact.zig").Generation;

// Predicate and value types
pub const Predicate = @import("predicate.zig").Predicate;
pub const PredicateCategory = @import("predicate.zig").PredicateCategory;
pub const getCategory = @import("predicate.zig").getCategory;

pub const Value = @import("value.zig").Value;
pub const AtomId = @import("value.zig").AtomId;

// Storage and builder
pub const FactStore = @import("store.zig").FactStore;
pub const Builder = @import("builder.zig").Builder;

// Size assertions for all core types
comptime {
    std.debug.assert(@sizeOf(Fact) == 24);
    std.debug.assert(@sizeOf(FactId) == 4);
    std.debug.assert(@sizeOf(Predicate) == 2);
    std.debug.assert(@sizeOf(Value) == 8);
}

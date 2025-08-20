const std = @import("std");

pub fn main() void {
    const Fact = @import("src/lib/fact/fact.zig").Fact;
    const Value = @import("src/lib/fact/value.zig").Value;
    const Predicate = @import("src/lib/fact/predicate.zig").Predicate;
    const PackedSpan = @import("src/lib/span/mod.zig").PackedSpan;
    
    std.debug.print("\nSize Analysis:\n", .{});
    std.debug.print("  FactId (u32): {d} bytes\n", .{@sizeOf(u32)});
    std.debug.print("  PackedSpan: {d} bytes\n", .{@sizeOf(PackedSpan)});
    std.debug.print("  Predicate: {d} bytes\n", .{@sizeOf(Predicate)});
    std.debug.print("  f16: {d} bytes\n", .{@sizeOf(f16)});
    std.debug.print("  Value: {d} bytes (expected 8)\n", .{@sizeOf(Value)});
    std.debug.print("  Fact: {d} bytes (expected 24)\n", .{@sizeOf(Fact)});
    
    if (@sizeOf(Fact) != 24) {
        std.debug.print("\nFact field analysis:\n", .{});
        std.debug.print("  id offset: {d}\n", .{@offsetOf(Fact, "id")});
        std.debug.print("  subject offset: {d}\n", .{@offsetOf(Fact, "subject")});
        std.debug.print("  predicate offset: {d}\n", .{@offsetOf(Fact, "predicate")});
        std.debug.print("  confidence offset: {d}\n", .{@offsetOf(Fact, "confidence")});
        std.debug.print("  object offset: {d}\n", .{@offsetOf(Fact, "object")});
    }
}
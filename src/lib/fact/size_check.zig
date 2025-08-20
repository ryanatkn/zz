const std = @import("std");
const Fact = @import("fact.zig").Fact;
const Value = @import("value.zig").Value;
const Predicate = @import("predicate.zig").Predicate;
const PackedSpan = @import("../span/mod.zig").PackedSpan;

pub fn main() void {
    std.debug.print("Fact size: {d} bytes (target: 24)\n", .{@sizeOf(Fact)});
    std.debug.print("FactId size: {d} bytes (target: 4)\n", .{@sizeOf(u32)});
    std.debug.print("PackedSpan size: {d} bytes (target: 8)\n", .{@sizeOf(PackedSpan)});
    std.debug.print("Predicate size: {d} bytes (target: 2)\n", .{@sizeOf(Predicate)});
    std.debug.print("f16 size: {d} bytes (target: 2)\n", .{@sizeOf(f16)});
    std.debug.print("Value size: {d} bytes (target: 8)\n", .{@sizeOf(Value)});
    
    std.debug.print("\nFact field offsets:\n", .{});
    std.debug.print("  id: {d}\n", .{@offsetOf(Fact, "id")});
    std.debug.print("  subject: {d}\n", .{@offsetOf(Fact, "subject")});
    std.debug.print("  predicate: {d}\n", .{@offsetOf(Fact, "predicate")});
    std.debug.print("  confidence: {d}\n", .{@offsetOf(Fact, "confidence")});
    std.debug.print("  object: {d}\n", .{@offsetOf(Fact, "object")});
}
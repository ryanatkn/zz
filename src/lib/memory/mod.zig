/// Memory management utilities for the stream-first architecture
/// Provides arena pools, atom tables, and other zero-allocation patterns
const std = @import("std");

// Core arena and pooling utilities
pub const Arena = @import("pools.zig").Arena;
pub const StringIntern = @import("pools.zig").StringIntern;
pub const PathCache = @import("pools.zig").PathCache;
pub const ListPool = @import("pools.zig").ListPool;

// Arena pool with rotation for generational collection
pub const ArenaPool = @import("arena_pool.zig").ArenaPool;
pub const ScopedArena = @import("arena_pool.zig").ScopedArena;
pub const PoolStats = @import("arena_pool.zig").PoolStats;

// Atom table for string interning
pub const AtomTable = @import("atom_table.zig").AtomTable;
pub const AtomId = @import("atom_table.zig").AtomId;
pub const INVALID_ATOM = @import("atom_table.zig").INVALID_ATOM;

// Global atom table functions
pub const initGlobalAtoms = @import("atom_table.zig").initGlobal;
pub const deinitGlobalAtoms = @import("atom_table.zig").deinitGlobal;
pub const internGlobal = @import("atom_table.zig").internGlobal;
pub const getStringGlobal = @import("atom_table.zig").lookupGlobal;

// Scoped memory utilities
pub const ScopedAllocator = @import("scoped.zig").ScopedAllocator;

test {
    _ = @import("test.zig");
    _ = @import("arena_pool.zig");
    _ = @import("atom_table.zig");
}

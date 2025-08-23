const std = @import("std");
const MemoryStrategy = @import("strategy.zig").MemoryStrategy;
const NodeStrategy = @import("strategy.zig").NodeStrategy;
const ArrayStrategy = @import("strategy.zig").ArrayStrategy;
const StringStrategy = @import("strategy.zig").StringStrategy;

/// System-wide default strategy - safe and adaptive
pub const DEFAULT_STRATEGY = MemoryStrategy{
    .adaptive = .{
        .config = .{
            .sample_period = 1000,
            .upgrade_threshold = 10.0,
            .memory_threshold = 1024 * 1024,
            .allow_downgrade = false,
        },
        .initial = &SIMPLE_STRATEGY,
        .target = &OPTIMIZED_STRATEGY,
    },
};

/// Simple strategy for small inputs
pub const SIMPLE_STRATEGY = MemoryStrategy{ .arena_only = {} };

/// Optimized strategy for complex inputs
pub const OPTIMIZED_STRATEGY = MemoryStrategy{
    .hybrid = .{
        .nodes = .small_pool,
        .arrays = .size_classed,
        .strings = .persistent,
    },
};

// =============================================================================
// Language-Specific Default Strategies
// =============================================================================

/// JSON: Complex nested structures, high allocation churn
/// - Many small objects (nodes) benefit from pooling
/// - Variable array sizes need size classes
/// - Property keys repeat frequently (benefit from interning)
pub const JSON_DEFAULT_STRATEGY = MemoryStrategy{
    .hybrid = .{
        .nodes = .small_pool, // Frequent object/array nodes
        .arrays = .size_classed, // Arrays of various sizes
        .strings = .interned, // "name", "id", "type" repeat constantly
    },
};

/// ZON: Configuration files, typically smaller and simpler
/// - Usually parsed once and kept
/// - Simpler structure with less nesting
/// - Fewer repeated strings
pub const ZON_DEFAULT_STRATEGY = MemoryStrategy{
    .hybrid = .{
        .nodes = .arena, // Simple cleanup
        .arrays = .arena, // Usually small arrays
        .strings = .persistent, // Keep strings for AST lifetime
    },
};

/// TypeScript: Mix of complex and simple structures
/// - Lots of small nodes (expressions, statements)
/// - Many repeated identifiers
/// - Benefit from pooling for AST nodes
pub const TYPESCRIPT_DEFAULT_STRATEGY = MemoryStrategy{
    .hybrid = .{
        .nodes = .small_pool, // Many AST nodes
        .arrays = .size_classed, // Parameter lists, etc.
        .strings = .interned, // Identifiers repeat heavily
    },
};

/// CSS: Lots of repeated property names and values
/// - Property names repeat constantly
/// - Many small rule nodes
/// - Relatively flat structure
pub const CSS_DEFAULT_STRATEGY = MemoryStrategy{
    .hybrid = .{
        .nodes = .small_pool, // Rule and declaration nodes
        .arrays = .arena, // Selector lists usually small
        .strings = .interned, // "color", "margin", "padding" everywhere
    },
};

/// HTML: Hierarchical with repeated tag/attribute names
/// - Deep nesting possible
/// - Tag names and attributes repeat
/// - Text content usually unique
pub const HTML_DEFAULT_STRATEGY = MemoryStrategy{
    .hybrid = .{
        .nodes = .small_pool, // Element nodes
        .arrays = .size_classed, // Child lists vary in size
        .strings = .interned, // Tag and attribute names repeat
    },
};

/// Zig: Complex AST with many node types
/// - Very deep and complex AST
/// - Many unique identifiers
/// - Benefits from advanced optimization
pub const ZIG_DEFAULT_STRATEGY = MemoryStrategy{
    .hybrid = .{
        .nodes = .large_pool, // Complex AST needs larger pool
        .arrays = .metadata_tracked, // Advanced optimization for performance
        .strings = .persistent, // Identifiers mostly unique
    },
};

/// Svelte: Mix of HTML, CSS, and JavaScript
/// - Combines multiple language patterns
/// - Benefits from flexible strategy
pub const SVELTE_DEFAULT_STRATEGY = MemoryStrategy{
    .adaptive = .{
        .config = .{
            .sample_period = 500, // Check more frequently
            .upgrade_threshold = 5.0, // Upgrade sooner
            .memory_threshold = 512 * 1024,
            .allow_downgrade = true, // Can switch between modes
        },
        .initial = &SIMPLE_STRATEGY,
        .target = &TYPESCRIPT_DEFAULT_STRATEGY, // Similar to TS when complex
    },
};

// =============================================================================
// Workload-Specific Strategies
// =============================================================================

/// Strategy for very large files (>10MB)
pub const LARGE_FILE_STRATEGY = MemoryStrategy{
    .metadata_tracked = .{
        .track_allocations = true,
        .track_lifetime = false, // Too expensive for large files
        .max_tracked = 50000,
        .enable_diagnostics = false,
    },
};

/// Strategy for high-performance scenarios
pub const HIGH_PERFORMANCE_STRATEGY = MemoryStrategy{
    .tagged_allocation = .{
        .magic_number = 0xFEEDFACE,
        .alignment = 64, // Cache line alignment
        .enable_bounds_checking = false,
        .enable_double_free_detection = false,
    },
};

/// Strategy for memory-constrained environments
pub const LOW_MEMORY_STRATEGY = MemoryStrategy{ .arena_only = {} };

/// Strategy for debugging and development
pub const DEBUG_STRATEGY = MemoryStrategy{
    .tagged_allocation = .{
        .magic_number = 0xDEB00000,
        .alignment = 16,
        .enable_bounds_checking = true,
        .enable_double_free_detection = true,
    },
};

// =============================================================================
// Helper Functions
// =============================================================================

/// Select strategy based on file size and complexity hints
pub fn selectStrategyForWorkload(
    file_size: usize,
    estimated_nodes: usize,
    language_hint: ?[]const u8,
) MemoryStrategy {
    // Very large files need special handling
    if (file_size > 10 * 1024 * 1024) {
        return LARGE_FILE_STRATEGY;
    }

    // Small files can use simple strategy
    if (file_size < 1024 and estimated_nodes < 100) {
        return SIMPLE_STRATEGY;
    }

    // Use language-specific defaults if provided
    if (language_hint) |lang| {
        if (std.mem.eql(u8, lang, "json")) return JSON_DEFAULT_STRATEGY;
        if (std.mem.eql(u8, lang, "zon")) return ZON_DEFAULT_STRATEGY;
        if (std.mem.eql(u8, lang, "typescript")) return TYPESCRIPT_DEFAULT_STRATEGY;
        if (std.mem.eql(u8, lang, "css")) return CSS_DEFAULT_STRATEGY;
        if (std.mem.eql(u8, lang, "html")) return HTML_DEFAULT_STRATEGY;
        if (std.mem.eql(u8, lang, "zig")) return ZIG_DEFAULT_STRATEGY;
        if (std.mem.eql(u8, lang, "svelte")) return SVELTE_DEFAULT_STRATEGY;
    }

    // Default to adaptive for unknown workloads
    return DEFAULT_STRATEGY;
}

/// Get strategy description for a language
pub fn describeLanguageStrategy(language: []const u8) []const u8 {
    if (std.mem.eql(u8, language, "json")) {
        return "JSON: Pooled nodes, size-classed arrays, interned strings (optimized for nested objects)";
    } else if (std.mem.eql(u8, language, "zon")) {
        return "ZON: Simple arena allocation (optimized for config files)";
    } else if (std.mem.eql(u8, language, "typescript")) {
        return "TypeScript: Pooled nodes, interned identifiers (optimized for complex AST)";
    } else if (std.mem.eql(u8, language, "css")) {
        return "CSS: Pooled nodes, heavily interned strings (optimized for repeated properties)";
    } else if (std.mem.eql(u8, language, "html")) {
        return "HTML: Pooled nodes, interned tag names (optimized for hierarchical structure)";
    } else if (std.mem.eql(u8, language, "zig")) {
        return "Zig: Large pools, metadata tracking (optimized for complex AST)";
    } else if (std.mem.eql(u8, language, "svelte")) {
        return "Svelte: Adaptive strategy (switches based on content complexity)";
    }
    return "Unknown language: Using default adaptive strategy";
}

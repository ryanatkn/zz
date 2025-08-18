const std = @import("std");

/// Configuration flags for code extraction and analysis
/// Moved from legacy l../core/extraction.zig to core utilities
pub const ExtractionFlags = struct {
    signatures: bool = false,
    types: bool = false,
    docs: bool = false,
    structure: bool = false,
    imports: bool = false,
    errors: bool = false,
    tests: bool = false,
    full: bool = false,

    /// Check if all flags are at their default (false) values
    pub fn isDefault(self: ExtractionFlags) bool {
        return !self.signatures and !self.types and !self.docs and
            !self.structure and !self.imports and !self.errors and
            !self.tests and !self.full;
    }

    /// Set full extraction if no specific flags are set
    pub fn setDefault(self: *ExtractionFlags) void {
        if (self.isDefault()) {
            self.full = true;
        }
    }

    /// Create flags for API documentation extraction
    pub fn forApiDocs() ExtractionFlags {
        return .{
            .signatures = true,
            .types = true,
            .docs = true,
            .structure = true,
            .imports = true,
        };
    }

    /// Create flags for code analysis
    pub fn forAnalysis() ExtractionFlags {
        return .{
            .structure = true,
            .imports = true,
            .errors = true,
        };
    }

    /// Create flags for testing
    pub fn forTesting() ExtractionFlags {
        return .{
            .tests = true,
            .structure = true,
        };
    }

    /// Create flags for full extraction
    pub fn forFull() ExtractionFlags {
        return .{ .full = true };
    }

    /// Convert to ZON representation for serialization
    pub fn toZon(self: ExtractionFlags, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator,
            \\.{{
            \\    .signatures = {},
            \\    .types = {},
            \\    .docs = {},
            \\    .structure = {},
            \\    .imports = {},
            \\    .errors = {},
            \\    .tests = {},
            \\    .full = {},
            \\}}
        , .{
            self.signatures, self.types,  self.docs,  self.structure,
            self.imports,    self.errors, self.tests, self.full,
        });
    }

    /// Check if any extraction flag is enabled
    pub fn hasAnyExtraction(self: ExtractionFlags) bool {
        return self.signatures or self.types or self.docs or
            self.structure or self.imports or self.errors or
            self.tests or self.full;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "extraction flags default behavior" {
    var flags = ExtractionFlags{};
    try testing.expect(flags.isDefault());

    flags.setDefault();
    try testing.expect(flags.full);
    try testing.expect(!flags.isDefault());
}

test "extraction flags presets" {
    const api_flags = ExtractionFlags.forApiDocs();
    try testing.expect(api_flags.signatures);
    try testing.expect(api_flags.types);
    try testing.expect(api_flags.docs);

    const analysis_flags = ExtractionFlags.forAnalysis();
    try testing.expect(analysis_flags.structure);
    try testing.expect(analysis_flags.imports);

    const test_flags = ExtractionFlags.forTesting();
    try testing.expect(test_flags.tests);
}

test "extraction flags ZON serialization" {
    const flags = ExtractionFlags{ .signatures = true, .types = true };
    const zon = try flags.toZon(testing.allocator);
    defer testing.allocator.free(zon);

    try testing.expect(std.mem.indexOf(u8, zon, ".signatures = true") != null);
    try testing.expect(std.mem.indexOf(u8, zon, ".types = true") != null);
}

test "extraction flags utilities" {
    const empty_flags = ExtractionFlags{};
    try testing.expect(!empty_flags.hasAnyExtraction());

    const sig_flags = ExtractionFlags{ .signatures = true };
    try testing.expect(sig_flags.hasAnyExtraction());
}

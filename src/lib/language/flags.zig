const std = @import("std");

/// Configuration flags for code extraction
pub const ExtractionFlags = struct {
    signatures: bool = false,
    types: bool = false,
    docs: bool = false,
    structure: bool = false,
    imports: bool = false,
    errors: bool = false,
    tests: bool = false,
    full: bool = false,

    pub fn isDefault(self: ExtractionFlags) bool {
        return !self.signatures and !self.types and !self.docs and 
               !self.structure and !self.imports and !self.errors and 
               !self.tests and !self.full;
    }

    pub fn setDefault(self: *ExtractionFlags) void {
        if (self.isDefault()) {
            self.full = true;
        }
    }
};

test "extraction flags" {
    const testing = std.testing;
    
    var flags = ExtractionFlags{};
    try testing.expect(flags.isDefault());
    
    flags.setDefault();
    try testing.expect(flags.full);
    
    flags = ExtractionFlags{ .signatures = true };
    try testing.expect(!flags.isDefault());
}
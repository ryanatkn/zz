const std = @import("std");

/// Simple import information structure
pub const Import = struct {
    path: []const u8,
    alias: ?[]const u8 = null,
    is_default: bool = false,

    pub fn deinit(self: Import, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.alias) |alias| {
            allocator.free(alias);
        }
    }
};

/// Export information (same structure as Import for now)
pub const Export = Import;

/// Import/export resolver
pub const Resolver = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Resolver {
        return .{ .allocator = allocator };
    }

    pub fn initOwning(allocator: std.mem.Allocator, project_root: []const u8, search_paths: []const []const u8) !Resolver {
        _ = project_root;
        _ = search_paths;
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Resolver) void {
        _ = self;
    }

    pub fn deinitOwning(self: *Resolver) void {
        _ = self;
    }

    pub fn resolve(self: *Resolver, imports: []const Import, base_path: []const u8) ![][]const u8 {
        _ = base_path;
        var resolved = std.ArrayList([]const u8).init(self.allocator);
        defer resolved.deinit();

        for (imports) |import| {
            const resolved_path = try self.allocator.dupe(u8, import.path);
            try resolved.append(resolved_path);
        }

        return resolved.toOwnedSlice();
    }
};

/// Extraction result containing imports and exports
pub const ExtractionResult = struct {
    imports: []const Import,
    exports: []const Import,

    pub fn deinit(self: ExtractionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.imports);
        allocator.free(self.exports);
    }
};

/// Simple imports extractor using text-based parsing
pub const Extractor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Extractor {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Extractor) void {
        _ = self;
    }

    /// Extract imports from source code
    pub fn extract(self: *Extractor, file_path: []const u8, source: []const u8) !ExtractionResult {
        _ = file_path;

        var imports = std.ArrayList(Import).init(self.allocator);
        defer imports.deinit();

        var exports = std.ArrayList(Import).init(self.allocator);
        defer exports.deinit();

        // Simple text-based extraction
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Look for import statements
            if (std.mem.startsWith(u8, trimmed, "import ") or
                std.mem.startsWith(u8, trimmed, "@import("))
            {
                if (try self.extractImportPath(trimmed)) |import_path| {
                    try imports.append(Import{ .path = import_path });
                }
            }

            // Look for export statements
            if (std.mem.startsWith(u8, trimmed, "export ")) {
                if (try self.extractExportPath(trimmed)) |export_path| {
                    try exports.append(Import{ .path = export_path });
                }
            }
        }

        return ExtractionResult{
            .imports = try imports.toOwnedSlice(),
            .exports = try exports.toOwnedSlice(),
        };
    }

    fn extractImportPath(self: *Extractor, line: []const u8) !?[]const u8 {
        // Look for quoted strings
        if (std.mem.indexOf(u8, line, "\"")) |start| {
            if (std.mem.indexOfPos(u8, line, start + 1, "\"")) |end| {
                const path = line[start + 1 .. end];
                return try self.allocator.dupe(u8, path);
            }
        }
        return null;
    }

    fn extractExportPath(self: *Extractor, line: []const u8) !?[]const u8 {
        // Similar to import extraction
        return self.extractImportPath(line);
    }
};

test "imports extraction" {
    const testing = std.testing;

    var extractor = Extractor.init(testing.allocator);
    defer extractor.deinit();

    const source =
        \\import { foo } from "./foo.js";
        \\const bar = @import("bar.zig");
        \\export { baz } from "./baz.js";
    ;

    const result = try extractor.extract("test.js", source);
    defer result.deinit(testing.allocator);

    try testing.expect(result.imports.len >= 1);
    try testing.expect(result.exports.len >= 1);
}

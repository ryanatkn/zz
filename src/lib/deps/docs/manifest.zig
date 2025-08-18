const std = @import("std");
const path = @import("../../core/path.zig");
const io = @import("../../core/io.zig");
const builders = @import("../../text/builders.zig");

const DependencyDoc = @import("types.zig").DependencyDoc;

/// JSON manifest generator for machine-readable documentation
pub const ManifestGenerator = struct {
    allocator: std.mem.Allocator,
    deps_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, deps_dir: []const u8) Self {
        return Self{
            .allocator = allocator,
            .deps_dir = deps_dir,
        };
    }

    /// Generate manifest.json machine-readable documentation
    pub fn generateManifest(self: *Self, dep_docs: []const DependencyDoc) !void {
        var builder = builders.ResultBuilder.init(self.allocator);
        defer builder.deinit();

        try builder.appendLine("{");
        try builder.appendLine("  \"generator\": \"zz-deps-v1.0.0\",");
        try builder.appendLine("  \"dependencies\": {");

        for (dep_docs, 0..) |doc, i| {
            try builder.appendLineFmt("    \"{s}\": {{", .{doc.name});
            try builder.appendLineFmt("      \"category\": \"{s}\",", .{doc.category.toString()});
            try builder.appendLineFmt("      \"version\": \"{s}\",", .{doc.version_info.version});
            try builder.appendLineFmt("      \"repository\": \"{s}\",", .{doc.version_info.repository});
            try builder.appendLineFmt("      \"commit\": \"{s}\",", .{doc.version_info.commit});
            try builder.appendFmt("      \"purpose\": \"{s}\"", .{doc.purpose});

            if (doc.language) |lang| {
                try builder.appendFmt(",\n      \"language\": \"{s}\"", .{lang});
            }

            if (doc.build_config.parser_function) |func| {
                try builder.appendFmt(",\n      \"parser_function\": \"{s}\"", .{func});
            }

            try builder.appendLine("");
            try builder.append("    }");

            if (i < dep_docs.len - 1) {
                try builder.append(",");
            }
            try builder.appendLine("");
        }

        try builder.appendLine("  }");
        try builder.appendLine("}");

        // Write to file
        const manifest_path = try path.joinPath(self.allocator, self.deps_dir, "manifest.json");
        defer self.allocator.free(manifest_path);

        try io.writeFile(manifest_path, builder.items());
    }
};

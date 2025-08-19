const std = @import("std");

/// Generate large test files for streaming validation
/// Target: 1MB JSON and ZON files for memory reduction testing
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Generating large test fixtures...", .{});

    try generateLargeJson(allocator, "large_1mb.json", 1024 * 1024);
    try generateLargeZon(allocator, "large_1mb.zon", 1024 * 1024);

    std.log.info("Test fixtures generated successfully", .{});
}

fn generateLargeJson(allocator: std.mem.Allocator, path: []const u8, target_size: usize) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var buffered_writer = std.io.bufferedWriter(file.writer());
    const writer = buffered_writer.writer();

    try writer.writeAll("{\n");
    try writer.writeAll("  \"metadata\": {\n");
    try writer.writeAll("    \"generated\": true,\n");
    try writer.writeAll("    \"purpose\": \"streaming memory test\",\n");
    try writer.writeAll("    \"target_size_mb\": 1\n");
    try writer.writeAll("  },\n");
    try writer.writeAll("  \"users\": [\n");

    var current_size: usize = 100; // Approximate size so far
    var user_id: u32 = 1;

    while (current_size < target_size - 1000) { // Leave room for closing
        if (user_id > 1) {
            try writer.writeAll(",\n");
        }

        const user_json = try std.fmt.allocPrint(allocator, 
            \\    {{
            \\      "id": {},
            \\      "name": "User {} with a longer name for size",
            \\      "email": "user{}@example-domain-for-testing.com",
            \\      "age": {},
            \\      "active": {},
            \\      "profile": {{
            \\        "bio": "This is a longer biography text for user {} to increase the JSON size for streaming memory testing purposes. Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
            \\        "preferences": {{
            \\          "theme": "dark",
            \\          "notifications": true,
            \\          "language": "en-US",
            \\          "timezone": "UTC"
            \\        }},
            \\        "tags": ["tag{}", "category{}", "group{}", "type{}"],
            \\        "scores": [
            \\          {{ "name": "skill1", "value": {} }},
            \\          {{ "name": "skill2", "value": {} }},
            \\          {{ "name": "skill3", "value": {} }}
            \\        ],
            \\        "metadata": {{
            \\          "created_at": "2024-01-{}T10:30:00Z",
            \\          "updated_at": "2024-01-{}T15:45:30Z",
            \\          "version": {},
            \\          "flags": ["verified", "premium", "active"]
            \\        }}
            \\      }}
            \\    }}
        , .{
            user_id,
            user_id,
            user_id,
            20 + (user_id % 50),
            user_id % 2 == 0,
            user_id,
            user_id % 100,
            (user_id + 1) % 100,
            (user_id + 2) % 100,
            (user_id + 3) % 100,
            (user_id * 7) % 100,
            (user_id * 11) % 100,
            (user_id * 13) % 100,
            1 + (user_id % 28),
            1 + ((user_id + 10) % 28),
            user_id,
        });
        defer allocator.free(user_json);

        try writer.writeAll(user_json);
        current_size += user_json.len + 2; // +2 for comma and newline
        user_id += 1;
    }

    try writer.writeAll("\n  ],\n");
    try writer.writeAll("  \"statistics\": {\n");
    try writer.print("    \"total_users\": {},\n", .{user_id - 1});
    try writer.print("    \"generated_size_bytes\": {},\n", .{current_size});
    try writer.writeAll("    \"compression_ratio\": 0.0,\n");
    try writer.writeAll("    \"schema_version\": \"1.0\"\n");
    try writer.writeAll("  }\n");
    try writer.writeAll("}");

    try buffered_writer.flush();
}

fn generateLargeZon(allocator: std.mem.Allocator, path: []const u8, target_size: usize) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var buffered_writer = std.io.bufferedWriter(file.writer());
    const writer = buffered_writer.writer();

    try writer.writeAll(".{\n");
    try writer.writeAll("    .name = \"large_test_package\",\n");
    try writer.writeAll("    .version = \"1.0.0\",\n");
    try writer.writeAll("    .description = \"Large ZON file for streaming memory testing\",\n");
    try writer.writeAll("    .minimum_zig_version = \"0.14.0\",\n");
    try writer.writeAll("\n");
    try writer.writeAll("    .metadata = .{\n");
    try writer.writeAll("        .generated = true,\n");
    try writer.writeAll("        .purpose = \"streaming memory test\",\n");
    try writer.writeAll("        .target_size_mb = 1,\n");
    try writer.writeAll("    },\n");
    try writer.writeAll("\n");
    try writer.writeAll("    .dependencies = .{\n");

    var current_size: usize = 300; // Approximate size so far
    var dep_id: u32 = 1;

    while (current_size < target_size - 2000) { // Leave room for closing
        if (dep_id > 1) {
            try writer.writeAll(",\n");
        }

        const dep_zon = try std.fmt.allocPrint(allocator,
            \\        .@"dependency-{}" = .{{
            \\            .url = "https://github.com/example-org/dependency-{}-with-long-name-for-size",
            \\            .hash = "1220abcdef{}1234567890abcdef{}1234567890abcdef{}1234567890abcdef{}",
            \\            .lazy = {},
            \\            .version = "1.{}.{}",
            \\            .description = "This is dependency {} with a longer description for testing streaming memory usage in ZON files. Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt.",
            \\            .features = .{{
            \\                "feature_{}_a",
            \\                "feature_{}_b", 
            \\                "feature_{}_c",
            \\                "feature_{}_experimental",
            \\            }},
            \\            .build_options = .{{
            \\                .optimization = "ReleaseFast",
            \\                .target = "native",
            \\                .cpu = "baseline",
            \\                .zig_lib_dir = null,
            \\                .strip = false,
            \\                .single_threaded = false,
            \\            }},
            \\            .paths = .{{
            \\                "src/lib{}.zig",
            \\                "src/lib{}/mod.zig",
            \\                "include/lib{}.h",
            \\                "docs/lib{}.md",
            \\            }},
            \\        }}
        , .{
            dep_id,
            dep_id,
            dep_id,
            dep_id * 2,
            dep_id * 3,
            dep_id * 4,
            dep_id % 2 == 0,
            dep_id % 10,
            (dep_id + 5) % 10,
            dep_id,
            dep_id,
            dep_id,
            dep_id,
            dep_id,
            dep_id,
            dep_id,
            dep_id,
            dep_id,
        });
        defer allocator.free(dep_zon);

        try writer.writeAll(dep_zon);
        current_size += dep_zon.len + 2; // +2 for comma and newline
        dep_id += 1;
    }

    try writer.writeAll("\n    },\n");
    try writer.writeAll("\n");
    try writer.writeAll("    .build_configs = .{\n");
    
    // Add some build configurations
    for (0..10) |i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.print(
            \\        .@"config_{}" = .{{
            \\            .target = "native",
            \\            .optimize = "ReleaseFast",
            \\            .strip = {},
            \\            .single_threaded = {},
            \\            .use_llvm = true,
            \\            .use_lld = true,
            \\            .pic = false,
            \\        }}
        , .{ i, i % 2 == 0, i % 3 == 0 });
    }
    
    try writer.writeAll("\n    },\n");
    try writer.writeAll("\n");
    try writer.writeAll("    .paths = .{\n");
    try writer.writeAll("        \"build.zig\",\n");
    try writer.writeAll("        \"build.zig.zon\",\n");
    try writer.writeAll("        \"src\",\n");
    try writer.writeAll("        \"include\",\n");
    try writer.writeAll("        \"docs\",\n");
    try writer.writeAll("        \"examples\",\n");
    try writer.writeAll("        \"tests\",\n");
    try writer.writeAll("        \"README.md\",\n");
    try writer.writeAll("        \"LICENSE\",\n");
    try writer.writeAll("    },\n");
    try writer.writeAll("\n");
    try writer.writeAll("    .statistics = .{\n");
    try writer.print("        .total_dependencies = {},\n", .{dep_id - 1});
    try writer.print("        .generated_size_bytes = {},\n", .{current_size});
    try writer.writeAll("        .schema_version = \"1.0\",\n");
    try writer.writeAll("    },\n");
    try writer.writeAll("}");

    try buffered_writer.flush();
}
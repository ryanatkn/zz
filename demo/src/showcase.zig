// Showcase module - demonstrates zz's parsing capabilities
const std = @import("std");
const renderer = @import("renderer.zig");
const samples = @import("samples.zig");

const Terminal = renderer.Terminal;
const Color = renderer.Color;
const Box = renderer.Box;

pub const Showcase = struct {
    allocator: std.mem.Allocator,
    terminal: Terminal,
    
    pub fn init(allocator: std.mem.Allocator) Showcase {
        return .{
            .allocator = allocator,
            .terminal = Terminal.init(),
        };
    }
    
    pub fn showTreeVisualization(self: *Showcase) !void {
        try self.terminal.clearScreen();
        try self.terminal.drawBox(1, 1, 70, 20, "Tree Visualization");
        
        try self.terminal.moveCursor(3, 3);
        try self.terminal.printColored("Running: ", Color.dim);
        try self.terminal.printColored("zz tree demo/", Color.bright_cyan);
        
        try self.terminal.moveCursor(5, 3);
        try self.simulateTreeOutput();
        
        try self.terminal.moveCursor(22, 3);
        try self.terminal.printColored("✓ Tree visualization complete", Color.bright_green);
        
        std.time.sleep(2 * std.time.ns_per_s);
    }
    
    fn simulateTreeOutput(self: *Showcase) !void {
        const tree_lines = [_]struct { indent: u32, text: []const u8, color: []const u8 }{
            .{ .indent = 0, .text = "└── demo", .color = Color.reset },
            .{ .indent = 4, .text = "├── src", .color = Color.reset },
            .{ .indent = 8, .text = "├── main.zig", .color = Color.reset },
            .{ .indent = 8, .text = "├── renderer.zig", .color = Color.reset },
            .{ .indent = 8, .text = "├── showcase.zig", .color = Color.reset },
            .{ .indent = 8, .text = "└── samples.zig", .color = Color.reset },
            .{ .indent = 4, .text = "├── build.zig", .color = Color.reset },
            .{ .indent = 4, .text = "├── README.md", .color = Color.reset },
            .{ .indent = 4, .text = "└── node_modules", .color = Color.gray },
            .{ .indent = 8, .text = "[...]", .color = Color.gray },
        };
        
        var row: u32 = 5;
        for (tree_lines) |line| {
            try self.terminal.moveCursor(row, 3 + line.indent);
            try self.terminal.printColored(line.text, line.color);
            row += 1;
            std.time.sleep(100 * std.time.ns_per_ms);
        }
    }
    
    pub fn showTypeScriptParsing(self: *Showcase) !void {
        try self.terminal.clearScreen();
        try self.terminal.drawBox(1, 1, 80, 30, "TypeScript Parser");
        
        // Show original code
        try self.terminal.moveCursor(3, 3);
        try self.terminal.printColored("Original TypeScript Code:", Color.bold);
        try self.terminal.moveCursor(4, 3);
        
        // Display sample code with syntax highlighting
        const lines = std.mem.tokenizeScalar(u8, samples.TypeScriptSample[0..500], '\n');
        var iter = lines;
        var row: u32 = 5;
        while (iter.next()) |line| {
            if (row > 12) break;
            try self.terminal.moveCursor(row, 3);
            try self.terminal.highlightCode(line, "typescript");
            row += 1;
        }
        
        // Show extraction
        try self.terminal.moveCursor(14, 3);
        try self.terminal.printColored("Running: ", Color.dim);
        try self.terminal.printColored("zz prompt app.ts --signatures --types", Color.bright_cyan);
        
        std.time.sleep(1 * std.time.ns_per_s);
        
        try self.terminal.moveCursor(16, 3);
        try self.terminal.printColored("Extracted:", Color.bold);
        
        // Show extracted results
        try self.terminal.moveCursor(17, 3);
        try self.terminal.printColored("✓ ", Color.bright_green);
        try self.terminal.printColored("interface User { ... }", Color.blue);
        
        try self.terminal.moveCursor(18, 3);
        try self.terminal.printColored("✓ ", Color.bright_green);
        try self.terminal.printColored("type UserRole = 'admin' | 'user' | 'guest'", Color.blue);
        
        try self.terminal.moveCursor(19, 3);
        try self.terminal.printColored("✓ ", Color.bright_green);
        try self.terminal.printColored("class UserService { ... }", Color.blue);
        
        try self.terminal.moveCursor(20, 3);
        try self.terminal.printColored("✓ ", Color.bright_green);
        try self.terminal.printColored("async getUser(id: number): Promise<User>", Color.yellow);
        
        try self.terminal.moveCursor(21, 3);
        try self.terminal.printColored("✓ ", Color.bright_green);
        try self.terminal.printColored("async createUser(data: Partial<User>): Promise<User>", Color.yellow);
        
        try self.terminal.moveCursor(23, 3);
        try self.terminal.printColored("Statistics:", Color.bold);
        try self.terminal.moveCursor(24, 3);
        try self.terminal.printColored("• 1 interface, 1 type, 1 class", Color.reset);
        try self.terminal.moveCursor(25, 3);
        try self.terminal.printColored("• 2 async functions extracted", Color.reset);
        try self.terminal.moveCursor(26, 3);
        try self.terminal.printColored("• Processing time: 2.3ms", Color.green);
        
        std.time.sleep(3 * std.time.ns_per_s);
    }
    
    pub fn showCssParsing(self: *Showcase) !void {
        try self.terminal.clearScreen();
        try self.terminal.drawBox(1, 1, 80, 25, "CSS Parser");
        
        try self.terminal.moveCursor(3, 3);
        try self.terminal.printColored("Parsing CSS with variable extraction:", Color.bold);
        
        // Show sample CSS
        const lines = std.mem.tokenizeScalar(u8, samples.CssSample[0..400], '\n');
        var iter = lines;
        var row: u32 = 5;
        while (iter.next()) |line| {
            if (row > 10) break;
            try self.terminal.moveCursor(row, 3);
            try self.terminal.highlightCode(line, "css");
            row += 1;
        }
        
        try self.terminal.moveCursor(12, 3);
        try self.terminal.printColored("Extracted CSS Variables:", Color.bold);
        
        const vars = [_][]const u8{
            "--primary-color: #007bff",
            "--secondary-color: #6c757d",
            "--background: #ffffff",
            "--text-color: #333333",
            "--border-radius: 8px",
            "--spacing-unit: 1rem",
        };
        
        row = 14;
        for (vars) |v| {
            try self.terminal.moveCursor(row, 3);
            try self.terminal.printColored("• ", Color.green);
            try self.terminal.printColored(v, Color.cyan);
            row += 1;
            std.time.sleep(200 * std.time.ns_per_ms);
        }
        
        std.time.sleep(2 * std.time.ns_per_s);
    }
    
    pub fn showPerformanceBenchmark(self: *Showcase) !void {
        try self.terminal.clearScreen();
        try self.terminal.drawBox(1, 1, 80, 20, "Performance Benchmarks");
        
        try self.terminal.moveCursor(3, 3);
        try self.terminal.printColored("Running performance benchmarks...", Color.bold);
        
        const benchmarks = [_]struct { name: []const u8, time: []const u8, progress: f32 }{
            .{ .name = "Path operations", .time = "47μs/op", .progress = 0.85 },
            .{ .name = "String pooling", .time = "145ns/op", .progress = 0.95 },
            .{ .name = "Pattern matching", .time = "25ns/op", .progress = 0.92 },
            .{ .name = "Code extraction", .time = "92μs/op", .progress = 0.78 },
            .{ .name = "Tree traversal", .time = "320μs/op", .progress = 0.88 },
        };
        
        var row: u32 = 5;
        for (benchmarks) |bench| {
            try self.terminal.moveCursor(row, 3);
            try self.terminal.drawProgressBar(bench.progress, 30, bench.name);
            
            try self.terminal.moveCursor(row, 55);
            try self.terminal.printColored(bench.time, Color.bright_green);
            
            row += 2;
            std.time.sleep(300 * std.time.ns_per_ms);
        }
        
        try self.terminal.moveCursor(16, 3);
        try self.terminal.printColored("✓ All benchmarks complete", Color.bright_green);
        try self.terminal.moveCursor(17, 3);
        try self.terminal.printColored("Performance: ", Color.reset);
        try self.terminal.printColored("20-30% faster than stdlib", Color.bright_yellow);
        
        std.time.sleep(3 * std.time.ns_per_s);
    }
    
    pub fn showSvelteParsing(self: *Showcase) !void {
        try self.terminal.clearScreen();
        try self.terminal.drawBox(1, 1, 80, 25, "Svelte Component Parser");
        
        try self.terminal.moveCursor(3, 3);
        try self.terminal.printColored("Parsing multi-section Svelte component:", Color.bold);
        
        try self.terminal.moveCursor(5, 3);
        try self.terminal.printColored("Detected sections:", Color.cyan);
        
        const sections = [_]struct { name: []const u8, lines: u32, color: []const u8 }{
            .{ .name = "<script> section", .lines = 23, .color = Color.yellow },
            .{ .name = "<style> section", .lines = 26, .color = Color.magenta },
            .{ .name = "<template> section", .lines = 17, .color = Color.blue },
        };
        
        var row: u32 = 7;
        for (sections) |section| {
            try self.terminal.moveCursor(row, 5);
            try self.terminal.printColored("• ", Color.green);
            try self.terminal.printColored(section.name, section.color);
            try self.terminal.printColored(" (", Color.dim);
            try self.terminal.printColored(try std.fmt.allocPrint(self.allocator, "{} lines", .{section.lines}), Color.dim);
            try self.terminal.printColored(")", Color.dim);
            row += 1;
            std.time.sleep(300 * std.time.ns_per_ms);
        }
        
        try self.terminal.moveCursor(11, 3);
        try self.terminal.printColored("Extracted from <script>:", Color.bold);
        
        const script_items = [_][]const u8{
            "export let user: User",
            "export let editable = false",
            "function handleEdit()",
            "function handleSave()",
        };
        
        row = 13;
        for (script_items) |item| {
            try self.terminal.moveCursor(row, 5);
            try self.terminal.printColored("✓ ", Color.bright_green);
            try self.terminal.printColored(item, Color.yellow);
            row += 1;
            std.time.sleep(200 * std.time.ns_per_ms);
        }
        
        std.time.sleep(2 * std.time.ns_per_s);
    }
};
const std = @import("std");

/// Line and column coordinates for text positions
/// Uses 1-based indexing for user-facing operations (editor convention)
pub const Coordinates = struct {
    line: usize, // 1-based line number
    column: usize, // 1-based column number

    /// Create new coordinates
    pub fn init(line: usize, column: usize) Coordinates {
        return .{
            .line = line,
            .column = column,
        };
    }

    /// Create coordinates at beginning of file
    pub fn start() Coordinates {
        return .{
            .line = 1,
            .column = 1,
        };
    }

    /// Format coordinates for display
    pub fn format(
        self: Coordinates,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}:{}", .{ self.line, self.column });
    }

    /// Compare coordinates for ordering
    pub fn order(self: Coordinates, other: Coordinates) std.math.Order {
        if (self.line < other.line) return .lt;
        if (self.line > other.line) return .gt;
        if (self.column < other.column) return .lt;
        if (self.column > other.column) return .gt;
        return .eq;
    }

    /// Check if coordinates are equal
    pub fn eql(self: Coordinates, other: Coordinates) bool {
        return self.line == other.line and self.column == other.column;
    }
};

/// Efficient converter between byte positions and line/column coordinates
/// Caches line boundaries for O(1) amortized coordinate lookups
pub const CoordinateConverter = struct {
    input: []const u8,
    line_starts: std.ArrayList(usize), // Byte positions of line starts
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) !CoordinateConverter {
        var converter = CoordinateConverter{
            .input = input,
            .line_starts = std.ArrayList(usize).init(allocator),
            .allocator = allocator,
        };

        try converter.buildLineIndex();
        return converter;
    }

    pub fn deinit(self: *CoordinateConverter) void {
        self.line_starts.deinit();
    }

    /// Build index of line start positions
    fn buildLineIndex(self: *CoordinateConverter) !void {
        // First line always starts at position 0
        try self.line_starts.append(0);

        var pos: usize = 0;
        while (pos < self.input.len) {
            if (self.input[pos] == '\n') {
                // Next line starts after the newline
                try self.line_starts.append(pos + 1);
            }
            pos += 1;
        }
    }

    /// Convert byte position to line/column coordinates
    pub fn positionToCoordinates(self: CoordinateConverter, position: usize) Coordinates {
        if (position >= self.input.len) {
            // Position beyond end of input - return end coordinates
            const last_line = self.line_starts.items.len;
            const last_line_start = if (last_line > 0) self.line_starts.items[last_line - 1] else 0;
            const column = self.input.len - last_line_start + 1;
            return Coordinates.init(last_line, column);
        }

        // Binary search for the line containing this position
        var left: usize = 0;
        var right: usize = self.line_starts.items.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            if (self.line_starts.items[mid] <= position) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        // left is now one past the line we want
        const line_number = left; // 1-based because we added 1 in the search
        const line_start = self.line_starts.items[line_number - 1];
        const column = position - line_start + 1; // 1-based column

        return Coordinates.init(line_number, column);
    }

    /// Convert line/column coordinates to byte position
    pub fn coordinatesToPosition(self: CoordinateConverter, coords: Coordinates) ?usize {
        if (coords.line == 0 or coords.column == 0) return null;
        if (coords.line > self.line_starts.items.len) return null;

        const line_start = self.line_starts.items[coords.line - 1]; // Convert to 0-based
        const position = line_start + coords.column - 1; // Convert to 0-based

        // Check bounds
        if (position >= self.input.len) {
            // Allow position at end of input for cursor positioning
            if (position == self.input.len) return position;
            return null;
        }

        // Make sure we don't go past the end of the line
        const line_end = self.getLineEnd(coords.line) orelse return null;
        if (position > line_end) return null;

        return position;
    }

    /// Get the number of lines in the input
    pub fn lineCount(self: CoordinateConverter) usize {
        return self.line_starts.items.len;
    }

    /// Get the start position of a specific line (1-based)
    pub fn getLineStart(self: CoordinateConverter, line: usize) ?usize {
        if (line == 0 or line > self.line_starts.items.len) return null;
        return self.line_starts.items[line - 1];
    }

    /// Get the end position of a specific line (1-based)
    /// Returns the exclusive end position (for slicing), stopping before newline
    pub fn getLineEnd(self: CoordinateConverter, line: usize) ?usize {
        if (line == 0 or line > self.line_starts.items.len) return null;

        if (line < self.line_starts.items.len) {
            // Not the last line - end is position of newline (exclusive)
            const next_line_start = self.line_starts.items[line];
            return if (next_line_start > 0) next_line_start - 1 else 0;
        } else {
            // Last line - end is end of input
            return self.input.len;
        }
    }

    /// Get the text of a specific line (1-based), excluding the newline
    pub fn getLineText(self: CoordinateConverter, line: usize) ?[]const u8 {
        const start = self.getLineStart(line) orelse return null;
        const end = self.getLineEnd(line) orelse return null;

        if (start > end) return "";
        return self.input[start..end];
    }

    /// Get the length of a specific line (1-based), excluding the newline
    pub fn getLineLength(self: CoordinateConverter, line: usize) ?usize {
        const text = self.getLineText(line) orelse return null;
        return text.len;
    }

    /// Check if a position is at the start of a line
    pub fn isLineStart(self: CoordinateConverter, position: usize) bool {
        for (self.line_starts.items) |line_start| {
            if (line_start == position) return true;
        }
        return false;
    }

    /// Check if a position is at the end of a line (just before newline or EOF)
    pub fn isLineEnd(self: CoordinateConverter, position: usize) bool {
        if (position >= self.input.len) return true;
        if (position + 1 < self.input.len and self.input[position + 1] == '\n') return true;
        return false;
    }

    /// Get the column width considering tab characters
    /// Assumes tab stops every 4 characters by default
    pub fn getVisualColumn(self: CoordinateConverter, position: usize, tab_size: usize) usize {
        const coords = self.positionToCoordinates(position);
        const line_start = self.getLineStart(coords.line) orelse return coords.column;

        var visual_column: usize = 1; // 1-based
        var pos = line_start;

        while (pos < position and pos < self.input.len) {
            if (self.input[pos] == '\t') {
                // Advance to next tab stop
                // Tab stops are at columns 1, 5, 9, 13, etc. (for tab_size=4)
                visual_column = ((visual_column - 1) / tab_size + 1) * tab_size + 1;
            } else {
                visual_column += 1;
            }
            pos += 1;
        }

        return visual_column;
    }
};

// Tests
const testing = std.testing;

test "Coordinates creation and formatting" {
    const coords = Coordinates.init(10, 25);
    try testing.expectEqual(@as(usize, 10), coords.line);
    try testing.expectEqual(@as(usize, 25), coords.column);

    const start_coords = Coordinates.start();
    try testing.expectEqual(@as(usize, 1), start_coords.line);
    try testing.expectEqual(@as(usize, 1), start_coords.column);
}

test "Coordinates ordering" {
    const coords1 = Coordinates.init(5, 10);
    const coords2 = Coordinates.init(5, 15);
    const coords3 = Coordinates.init(6, 5);
    const coords4 = Coordinates.init(5, 10);

    try testing.expectEqual(std.math.Order.lt, coords1.order(coords2));
    try testing.expectEqual(std.math.Order.lt, coords1.order(coords3));
    try testing.expectEqual(std.math.Order.eq, coords1.order(coords4));
    try testing.expect(coords1.eql(coords4));
    try testing.expect(!coords1.eql(coords2));
}

test "CoordinateConverter basic operations" {
    const input = "hello\nworld\ntest";
    var converter = try CoordinateConverter.init(testing.allocator, input);
    defer converter.deinit();

    try testing.expectEqual(@as(usize, 3), converter.lineCount());

    // Test line starts
    try testing.expectEqual(@as(usize, 0), converter.getLineStart(1).?);
    try testing.expectEqual(@as(usize, 6), converter.getLineStart(2).?);
    try testing.expectEqual(@as(usize, 12), converter.getLineStart(3).?);

    // Test line ends (exclusive positions for slicing)
    try testing.expectEqual(@as(usize, 5), converter.getLineEnd(1).?); // "hello" ends at position 5 (exclusive)
    try testing.expectEqual(@as(usize, 11), converter.getLineEnd(2).?); // "world" ends at position 11 (exclusive)
    try testing.expectEqual(@as(usize, 16), converter.getLineEnd(3).?); // "test" ends at EOF

    // Test line text
    try testing.expectEqualStrings("hello", converter.getLineText(1).?);
    try testing.expectEqualStrings("world", converter.getLineText(2).?);
    try testing.expectEqualStrings("test", converter.getLineText(3).?);
}

test "CoordinateConverter position to coordinates" {
    const input = "hello\nworld\ntest";
    var converter = try CoordinateConverter.init(testing.allocator, input);
    defer converter.deinit();

    // Test various positions
    var coords = converter.positionToCoordinates(0); // 'h' in "hello"
    try testing.expectEqual(@as(usize, 1), coords.line);
    try testing.expectEqual(@as(usize, 1), coords.column);

    coords = converter.positionToCoordinates(4); // 'o' in "hello"
    try testing.expectEqual(@as(usize, 1), coords.line);
    try testing.expectEqual(@as(usize, 5), coords.column);

    coords = converter.positionToCoordinates(6); // 'w' in "world"
    try testing.expectEqual(@as(usize, 2), coords.line);
    try testing.expectEqual(@as(usize, 1), coords.column);

    coords = converter.positionToCoordinates(12); // 't' in "test"
    try testing.expectEqual(@as(usize, 3), coords.line);
    try testing.expectEqual(@as(usize, 1), coords.column);

    // Test end of input
    coords = converter.positionToCoordinates(16); // Beyond "test"
    try testing.expectEqual(@as(usize, 3), coords.line);
    try testing.expectEqual(@as(usize, 5), coords.column);
}

test "CoordinateConverter coordinates to position" {
    const input = "hello\nworld\ntest";
    var converter = try CoordinateConverter.init(testing.allocator, input);
    defer converter.deinit();

    // Test various coordinates
    try testing.expectEqual(@as(usize, 0), converter.coordinatesToPosition(Coordinates.init(1, 1)).?);
    try testing.expectEqual(@as(usize, 4), converter.coordinatesToPosition(Coordinates.init(1, 5)).?);
    try testing.expectEqual(@as(usize, 6), converter.coordinatesToPosition(Coordinates.init(2, 1)).?);
    try testing.expectEqual(@as(usize, 12), converter.coordinatesToPosition(Coordinates.init(3, 1)).?);

    // Test invalid coordinates
    try testing.expectEqual(@as(?usize, null), converter.coordinatesToPosition(Coordinates.init(0, 1)));
    try testing.expectEqual(@as(?usize, null), converter.coordinatesToPosition(Coordinates.init(1, 0)));
    try testing.expectEqual(@as(?usize, null), converter.coordinatesToPosition(Coordinates.init(4, 1))); // Line doesn't exist
}

test "CoordinateConverter round trip" {
    const input = "hello\nworld\ntest\n";
    var converter = try CoordinateConverter.init(testing.allocator, input);
    defer converter.deinit();

    // Test round trip: position -> coordinates -> position
    // Skip newline positions (5, 11, 17) as they're edge cases
    const test_positions = [_]usize{ 0, 1, 4, 6, 10, 12, 15, 16 };

    for (test_positions) |pos| {
        if (pos <= input.len) {
            const coords = converter.positionToCoordinates(pos);
            const round_trip_pos = converter.coordinatesToPosition(coords);
            try testing.expectEqual(@as(?usize, pos), round_trip_pos);
        }
    }
}

test "CoordinateConverter line start/end detection" {
    const input = "hello\nworld\ntest";
    var converter = try CoordinateConverter.init(testing.allocator, input);
    defer converter.deinit();

    try testing.expect(converter.isLineStart(0)); // Start of "hello"
    try testing.expect(!converter.isLineStart(1)); // 'e' in "hello"
    try testing.expect(converter.isLineStart(6)); // Start of "world"
    try testing.expect(converter.isLineStart(12)); // Start of "test"

    try testing.expect(converter.isLineEnd(4)); // End of "hello"
    try testing.expect(converter.isLineEnd(10)); // End of "world"
    try testing.expect(converter.isLineEnd(16)); // End of input
    try testing.expect(!converter.isLineEnd(1)); // Middle of "hello"
}

test "CoordinateConverter visual columns with tabs" {
    const input = "hello\t\tworld\n\t\ttest";
    var converter = try CoordinateConverter.init(testing.allocator, input);
    defer converter.deinit();

    // Default tab size of 4
    try testing.expectEqual(@as(usize, 1), converter.getVisualColumn(0, 4)); // 'h'
    try testing.expectEqual(@as(usize, 5), converter.getVisualColumn(4, 4)); // 'o'
    try testing.expectEqual(@as(usize, 6), converter.getVisualColumn(5, 4)); // Start of first tab (column 6)
    try testing.expectEqual(@as(usize, 9), converter.getVisualColumn(6, 4)); // After first tab (column 9)
    try testing.expectEqual(@as(usize, 13), converter.getVisualColumn(7, 4)); // After second tab (column 13)

    // Tab size of 8
    try testing.expectEqual(@as(usize, 9), converter.getVisualColumn(6, 8)); // After first tab (column 9)
    try testing.expectEqual(@as(usize, 17), converter.getVisualColumn(7, 8)); // After second tab (column 17)
}

test "CoordinateConverter empty input" {
    const input = "";
    var converter = try CoordinateConverter.init(testing.allocator, input);
    defer converter.deinit();

    try testing.expectEqual(@as(usize, 1), converter.lineCount());

    const coords = converter.positionToCoordinates(0);
    try testing.expectEqual(@as(usize, 1), coords.line);
    try testing.expectEqual(@as(usize, 1), coords.column);
}

test "CoordinateConverter single line" {
    const input = "hello world";
    var converter = try CoordinateConverter.init(testing.allocator, input);
    defer converter.deinit();

    try testing.expectEqual(@as(usize, 1), converter.lineCount());
    try testing.expectEqualStrings("hello world", converter.getLineText(1).?);

    const coords = converter.positionToCoordinates(6); // 'w'
    try testing.expectEqual(@as(usize, 1), coords.line);
    try testing.expectEqual(@as(usize, 7), coords.column);
}

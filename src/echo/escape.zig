const std = @import("std");

/// Process escape sequences in text
/// Returns newly allocated string with escape sequences processed
pub fn process(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // Quick scan to see if we have any backslashes
    var has_escapes = false;
    for (input) |c| {
        if (c == '\\') {
            has_escapes = true;
            break;
        }
    }

    // If no backslashes, return a copy
    if (!has_escapes) {
        return allocator.dupe(u8, input);
    }

    // Process escape sequences
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len) {
            const escape_char = input[i + 1];
            switch (escape_char) {
                'n' => {
                    try result.append('\n');
                    i += 2;
                },
                't' => {
                    try result.append('\t');
                    i += 2;
                },
                'r' => {
                    try result.append('\r');
                    i += 2;
                },
                'a' => {
                    try result.append('\x07'); // Bell
                    i += 2;
                },
                'b' => {
                    try result.append('\x08'); // Backspace
                    i += 2;
                },
                'f' => {
                    try result.append('\x0C'); // Form feed
                    i += 2;
                },
                'v' => {
                    try result.append('\x0B'); // Vertical tab
                    i += 2;
                },
                '\\' => {
                    try result.append('\\');
                    i += 2;
                },
                '"' => {
                    try result.append('"');
                    i += 2;
                },
                '\'' => {
                    try result.append('\'');
                    i += 2;
                },
                '0'...'7' => {
                    // Octal escape sequence \0NNN
                    const octal_result = try parseOctal(input[i + 1 ..]);
                    try result.append(octal_result.value);
                    i += 1 + octal_result.consumed; // Skip backslash + consumed digits
                },
                'x' => {
                    // Hexadecimal escape sequence \xHH
                    if (i + 2 < input.len) {
                        const hex_result = try parseHex(input[i + 2 ..]);
                        try result.append(hex_result.value);
                        i += 2 + hex_result.consumed; // Skip backslash + 'x' + consumed digits
                    } else {
                        // Invalid hex escape, output literally
                        try result.append('\\');
                        try result.append('x');
                        i += 2;
                    }
                },
                else => {
                    // Unknown escape sequence, output literally
                    try result.append('\\');
                    try result.append(escape_char);
                    i += 2;
                },
            }
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

const OctalResult = struct {
    value: u8,
    consumed: usize,
};

fn parseOctal(input: []const u8) !OctalResult {
    var value: u16 = 0; // Use u16 to detect overflow
    var consumed: usize = 0;

    // Parse up to 3 octal digits
    for (input[0..@min(input.len, 3)]) |c| {
        if (c >= '0' and c <= '7') {
            const digit = c - '0';
            const new_value = value * 8 + digit;
            if (new_value > 255) break; // Prevent overflow
            value = new_value;
            consumed += 1;
        } else {
            break;
        }
    }

    // If no valid octal digits found, treat as literal
    if (consumed == 0) {
        return OctalResult{ .value = '0', .consumed = 0 };
    }

    return OctalResult{ .value = @intCast(value), .consumed = consumed };
}

const HexResult = struct {
    value: u8,
    consumed: usize,
};

fn parseHex(input: []const u8) !HexResult {
    var value: u8 = 0;
    var consumed: usize = 0;

    // Parse up to 2 hex digits
    for (input[0..@min(input.len, 2)]) |c| {
        if (std.ascii.isHex(c)) {
            const digit = std.fmt.charToDigit(c, 16) catch break;
            value = value * 16 + digit;
            consumed += 1;
        } else {
            break;
        }
    }

    // If no valid hex digits found, treat as literal
    if (consumed == 0) {
        return HexResult{ .value = 'x', .consumed = 0 };
    }

    return HexResult{ .value = value, .consumed = consumed };
}

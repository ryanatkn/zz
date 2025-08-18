const std = @import("std");

/// Date/time constants for calculations
pub const SECONDS_PER_DAY: i64 = 86400;
pub const SECONDS_PER_HOUR: i64 = 3600;
pub const UNIX_EPOCH_TO_DAYS_OFFSET: i64 = 719163; // Unix epoch to days since year 1
pub const DAYS_PER_YEAR_APPROX: i64 = 365; // Approximate for documentation purposes
pub const DAYS_PER_MONTH_APPROX: i64 = 30; // Approximate for documentation purposes

/// Simple date structure for documentation purposes
pub const SimpleDate = struct {
    year: u32,
    month: u32,
    day: u32,
    hour: u32 = 0,
    minute: u32 = 0,
    second: u32 = 0,

    /// Format as ISO 8601 date string (YYYY-MM-DD)
    pub fn formatDate(self: SimpleDate, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
    }

    /// Format as ISO 8601 datetime string (YYYY-MM-DDTHH:MM:SSZ)
    pub fn formatDateTime(self: SimpleDate, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{ self.year, self.month, self.day, self.hour, self.minute, self.second });
    }
};

/// Calculate simple date from Unix timestamp for documentation purposes
/// Note: This is a simplified calculation suitable for documentation generation,
/// not precise calendar arithmetic
pub fn timestampToSimpleDate(timestamp: i64) SimpleDate {
    const epoch_days = @divFloor(timestamp, SECONDS_PER_DAY) + UNIX_EPOCH_TO_DAYS_OFFSET;

    // Calculate time components
    const seconds_today = @mod(timestamp, SECONDS_PER_DAY);
    const hour: u32 = @intCast(@divFloor(seconds_today, SECONDS_PER_HOUR));
    const minute: u32 = @intCast(@divFloor(@mod(seconds_today, SECONDS_PER_HOUR), 60));
    const second: u32 = @intCast(@mod(seconds_today, 60));

    // Simple date calculation (approximation for documentation)
    const year: u32 = @intCast(@divFloor(epoch_days, DAYS_PER_YEAR_APPROX) + 1);
    const day_of_year = @mod(epoch_days, DAYS_PER_YEAR_APPROX);
    const month: u32 = @intCast(@min(12, @divFloor(day_of_year, DAYS_PER_MONTH_APPROX) + 1));
    const day: u32 = @intCast(@min(31, @mod(day_of_year, DAYS_PER_MONTH_APPROX) + 1));

    return SimpleDate{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

/// Get current timestamp as SimpleDate
pub fn getCurrentDate() SimpleDate {
    return timestampToSimpleDate(std.time.timestamp());
}

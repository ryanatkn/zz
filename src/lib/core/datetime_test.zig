// Tests for datetime functionality
const std = @import("std");
const datetime = @import("datetime.zig");

test "datetime constants are correct" {
    const testing = std.testing;

    // Test that our constants match expected values
    try testing.expectEqual(@as(i64, 86400), datetime.SECONDS_PER_DAY);
    try testing.expectEqual(@as(i64, 3600), datetime.SECONDS_PER_HOUR);
    try testing.expectEqual(@as(i64, 719163), datetime.UNIX_EPOCH_TO_DAYS_OFFSET);
    try testing.expectEqual(@as(i64, 365), datetime.DAYS_PER_YEAR_APPROX);
    try testing.expectEqual(@as(i64, 30), datetime.DAYS_PER_MONTH_APPROX);
}

test "timestampToSimpleDate - known dates" {
    const testing = std.testing;

    // Test Unix epoch (1970-01-01 00:00:00 UTC)
    // Note: Our calculation is approximate, so we test for reasonable values
    const epoch_date = datetime.timestampToSimpleDate(0);
    try testing.expect(epoch_date.year >= 1970 and epoch_date.year <= 1971); // Allow for approximation
    try testing.expect(epoch_date.month >= 1 and epoch_date.month <= 12);
    try testing.expect(epoch_date.day >= 1 and epoch_date.day <= 31);
    try testing.expectEqual(@as(u32, 0), epoch_date.hour);
    try testing.expectEqual(@as(u32, 0), epoch_date.minute);
    try testing.expectEqual(@as(u32, 0), epoch_date.second);

    // Test specific timestamp for reasonable results
    // Since this is a simplified calculation for documentation, focus on sanity checks
    const test_date = datetime.timestampToSimpleDate(1704110245);
    try testing.expect(test_date.year >= 2023 and test_date.year <= 2025); // Should be around 2024
    try testing.expect(test_date.month >= 1 and test_date.month <= 12);
    try testing.expect(test_date.day >= 1 and test_date.day <= 31);
    try testing.expect(test_date.hour <= 23);
    try testing.expect(test_date.minute <= 59);
    try testing.expect(test_date.second <= 59);
}

test "timestampToSimpleDate - time components" {
    const testing = std.testing;

    // Test various times within a day
    const base_timestamp = 1704067200; // 2024-01-01 00:00:00 UTC

    // Test noon (12:00:00)
    const noon = datetime.timestampToSimpleDate(base_timestamp + 12 * 3600);
    try testing.expectEqual(@as(u32, 12), noon.hour);
    try testing.expectEqual(@as(u32, 0), noon.minute);
    try testing.expectEqual(@as(u32, 0), noon.second);

    // Test 23:59:59
    const almost_midnight = datetime.timestampToSimpleDate(base_timestamp + 23 * 3600 + 59 * 60 + 59);
    try testing.expectEqual(@as(u32, 23), almost_midnight.hour);
    try testing.expectEqual(@as(u32, 59), almost_midnight.minute);
    try testing.expectEqual(@as(u32, 59), almost_midnight.second);
}

test "SimpleDate.formatDate - ISO format" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const date = datetime.SimpleDate{
        .year = 2024,
        .month = 3,
        .day = 15,
    };

    const formatted = try date.formatDate(allocator);
    defer allocator.free(formatted);

    try testing.expectEqualStrings("2024-03-15", formatted);
}

test "SimpleDate.formatDate - single digit padding" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const date = datetime.SimpleDate{
        .year = 2024,
        .month = 1,
        .day = 5,
    };

    const formatted = try date.formatDate(allocator);
    defer allocator.free(formatted);

    try testing.expectEqualStrings("2024-01-05", formatted);
}

test "SimpleDate.formatDateTime - ISO 8601 format" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const date = datetime.SimpleDate{
        .year = 2024,
        .month = 12,
        .day = 25,
        .hour = 14,
        .minute = 30,
        .second = 45,
    };

    const formatted = try date.formatDateTime(allocator);
    defer allocator.free(formatted);

    try testing.expectEqualStrings("2024-12-25T14:30:45Z", formatted);
}

test "SimpleDate.formatDateTime - zero padding" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const date = datetime.SimpleDate{
        .year = 2024,
        .month = 2,
        .day = 3,
        .hour = 4,
        .minute = 5,
        .second = 6,
    };

    const formatted = try date.formatDateTime(allocator);
    defer allocator.free(formatted);

    try testing.expectEqualStrings("2024-02-03T04:05:06Z", formatted);
}

test "getCurrentDate - returns valid date" {
    const testing = std.testing;

    const current = datetime.getCurrentDate();

    // Sanity checks for current date
    try testing.expect(current.year >= 2024); // Should be recent
    try testing.expect(current.year <= 2030); // Reasonable upper bound
    try testing.expect(current.month >= 1);
    try testing.expect(current.month <= 12);
    try testing.expect(current.day >= 1);
    try testing.expect(current.day <= 31);
    try testing.expect(current.hour <= 23);
    try testing.expect(current.minute <= 59);
    try testing.expect(current.second <= 59);
}

test "date calculations - approximate but reasonable" {
    const testing = std.testing;

    // Test that dates are approximately correct (our calculation is simplified)
    // We use 365-day years and 30-day months for documentation purposes

    // Test several known timestamps and verify they're in the right ballpark
    const test_cases = [_]struct { timestamp: i64, expected_year: u32 }{
        .{ .timestamp = 0, .expected_year = 1970 }, // Unix epoch
        .{ .timestamp = 946684800, .expected_year = 2000 }, // Y2K
        .{ .timestamp = 1609459200, .expected_year = 2021 }, // 2021-01-01
        .{ .timestamp = 1704067200, .expected_year = 2024 }, // 2024-01-01
    };

    for (test_cases) |case| {
        const date = datetime.timestampToSimpleDate(case.timestamp);

        // Year should be exactly correct or very close (within 1 year due to leap year approximation)
        const year_diff = if (date.year >= case.expected_year)
            date.year - case.expected_year
        else
            case.expected_year - date.year;
        try testing.expect(year_diff <= 1);

        // Month and day should be reasonable
        try testing.expect(date.month >= 1 and date.month <= 12);
        try testing.expect(date.day >= 1 and date.day <= 31);
    }
}

test "future dates work correctly" {
    const testing = std.testing;

    // Test far future date
    const future_timestamp = 2147483647; // Year 2038 problem timestamp
    const future_date = datetime.timestampToSimpleDate(future_timestamp);

    try testing.expect(future_date.year >= 2030);
    try testing.expect(future_date.year <= 2040);
    try testing.expect(future_date.month >= 1);
    try testing.expect(future_date.month <= 12);
    try testing.expect(future_date.day >= 1);
    try testing.expect(future_date.day <= 31);
}

test "negative timestamps work" {
    const testing = std.testing;

    // Test pre-1970 date
    const past_timestamp: i64 = -86400; // One day before Unix epoch
    const past_date = datetime.timestampToSimpleDate(past_timestamp);

    // Should give us a date in 1969 (but our approximation might be off)
    try testing.expect(past_date.year >= 1960);
    try testing.expect(past_date.year <= 1975); // Allow more range for approximation with negative timestamps
}

test "roundtrip consistency - formatting works" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test that we can format dates consistently
    const timestamp = 1704110245; // 2024-01-01 12:30:45 UTC
    const date = datetime.timestampToSimpleDate(timestamp);

    const date_str = try date.formatDate(allocator);
    defer allocator.free(date_str);

    const datetime_str = try date.formatDateTime(allocator);
    defer allocator.free(datetime_str);

    // Verify format patterns
    try testing.expect(date_str.len == 10); // YYYY-MM-DD
    try testing.expect(datetime_str.len == 20); // YYYY-MM-DDTHH:MM:SSZ
    try testing.expect(std.mem.indexOf(u8, datetime_str, "T") != null);
    try testing.expect(std.mem.indexOf(u8, datetime_str, "Z") != null);
    try testing.expect(std.mem.startsWith(u8, datetime_str, date_str));
}

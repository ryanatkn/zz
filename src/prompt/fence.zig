const std = @import("std");

pub fn detectFence(text: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var backtick_count: usize = 3;
    
    while (true) {
        const fence = try allocator.alloc(u8, backtick_count);
        @memset(fence, '`');
        
        if (std.mem.indexOf(u8, text, fence) == null) {
            return fence;
        }
        
        allocator.free(fence);
        backtick_count += 1;
        if (backtick_count > 32) {
            // Fallback to max size
            const max_fence = try allocator.alloc(u8, 32);
            @memset(max_fence, '`');
            return max_fence;
        }
    }
}

test "detectFence basic" {
    const allocator = std.testing.allocator;
    
    const text1 = "hello world";
    const fence1 = try detectFence(text1, allocator);
    defer allocator.free(fence1);
    try std.testing.expectEqualStrings("```", fence1);
    
    const text2 = "hello ```world```";
    const fence2 = try detectFence(text2, allocator);
    defer allocator.free(fence2);
    try std.testing.expectEqualStrings("````", fence2);
    
    const text3 = "``` and ```` and `````";
    const fence3 = try detectFence(text3, allocator);
    defer allocator.free(fence3);
    try std.testing.expectEqualStrings("``````", fence3);
}
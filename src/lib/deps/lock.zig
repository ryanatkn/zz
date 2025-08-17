const std = @import("std");
const io = @import("../core/io.zig");
const path = @import("../core/path.zig");

/// Lock file management for preventing concurrent dependency updates
pub const Lock = struct {
    allocator: std.mem.Allocator,
    lock_file_path: []const u8,
    pid: std.process.Child.Id,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, deps_dir: []const u8) !Self {
        const lock_file_path = try path.joinPath(allocator, deps_dir, ".update-deps.lock");
        // Use POSIX-portable getpid
        const pid = std.c.getpid();

        return Self{
            .allocator = allocator,
            .lock_file_path = lock_file_path,
            .pid = @intCast(pid),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.lock_file_path);
    }

    /// Acquire the lock, returning error if another process holds it
    pub fn acquire(self: *Self) !void {
        // Check if lock file exists
        if (try io.readFileOptional(self.allocator, self.lock_file_path)) |content| {
            defer self.allocator.free(content);

            // Parse PID from lock file
            const existing_pid = std.fmt.parseInt(std.process.Child.Id, std.mem.trim(u8, content, " \t\r\n"), 10) catch {
                // Invalid lock file, remove it
                self.removeStale() catch {};
                return self.createLock();
            };

            // Check if process is still running
            if (self.isProcessRunning(existing_pid)) {
                return error.LockHeld;
            } else {
                // Stale lock, remove it
                try self.removeStale();
            }
        } else {
            // File doesn't exist, that's fine
        }

        try self.createLock();
    }

    /// Release the lock
    pub fn release(self: *Self) void {
        io.deleteFile(self.lock_file_path) catch {};
    }

    /// Create the lock file with current PID
    fn createLock(self: *Self) !void {
        const pid_str = try std.fmt.allocPrint(self.allocator, "{d}\n", .{self.pid});
        defer self.allocator.free(pid_str);

        try io.writeFile(self.lock_file_path, pid_str);
    }

    /// Remove stale lock file
    fn removeStale(self: *Self) !void {
        io.deleteFile(self.lock_file_path) catch {};
    }

    /// Check if a process is still running
    fn isProcessRunning(self: *Self, pid: std.process.Child.Id) bool {
        _ = self;
        
        // Use kill(pid, 0) to check if process exists
        // This is POSIX-specific
        const result = std.c.kill(@intCast(pid), 0);
        return result == 0;
    }
};

/// RAII lock management
pub const LockGuard = struct {
    lock: Lock,
    acquired: bool,

    const Self = @This();

    pub fn acquire(allocator: std.mem.Allocator, deps_dir: []const u8) !Self {
        var lock = try Lock.init(allocator, deps_dir);
        errdefer lock.deinit();

        try lock.acquire();

        return Self{
            .lock = lock,
            .acquired = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.acquired) {
            self.lock.release();
        }
        self.lock.deinit();
    }
};

test "Lock acquisition and release" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Create temporary directory for testing
    const temp_dir = "test_lock_dir";
    try io.ensureDir(temp_dir);
    defer io.deleteTree(temp_dir) catch {};
    
    // Test basic lock acquisition
    {
        var lock1 = try Lock.init(allocator, temp_dir);
        defer lock1.deinit();
        
        try lock1.acquire();
        defer lock1.release();
        
        // Try to acquire second lock - should fail
        var lock2 = try Lock.init(allocator, temp_dir);
        defer lock2.deinit();
        
        try testing.expectError(error.LockHeld, lock2.acquire());
    }
    
    // Test lock release
    {
        var lock3 = try Lock.init(allocator, temp_dir);
        defer lock3.deinit();
        
        try lock3.acquire();
        lock3.release();
        
        // Should be able to acquire again after release
        var lock4 = try Lock.init(allocator, temp_dir);
        defer lock4.deinit();
        
        try lock4.acquire();
        lock4.release();
    }
}

test "LockGuard RAII" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Create temporary directory for testing
    const temp_dir = "test_lockguard_dir";
    try io.ensureDir(temp_dir);
    defer io.deleteTree(temp_dir) catch {};
    
    // Test RAII lock guard
    {
        var guard = try LockGuard.acquire(allocator, temp_dir);
        defer guard.deinit();
        
        // Try to acquire second lock - should fail
        try testing.expectError(error.LockHeld, LockGuard.acquire(allocator, temp_dir));
    }
    
    // Lock should be released after guard goes out of scope
    {
        var guard2 = try LockGuard.acquire(allocator, temp_dir);
        defer guard2.deinit();
        // Should succeed since previous guard was released
    }
}
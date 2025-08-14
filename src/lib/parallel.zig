const std = @import("std");

/// Task priority levels for work scheduling
pub const TaskPriority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,

    pub fn compare(self: TaskPriority, other: TaskPriority) std.math.Order {
        return std.math.order(@intFromEnum(self), @intFromEnum(other));
    }
};

/// Task status tracking
pub const TaskStatus = enum {
    pending,
    running,
    completed,
    failed,
    cancelled,
};

/// Generic task interface
pub const Task = struct {
    id: u64,
    priority: TaskPriority,
    status: TaskStatus,
    dependencies: []const u64, // Task IDs this task depends on
    execute_fn: *const fn (task: *Task, context: ?*anyopaque) anyerror!void,
    context: ?*anyopaque,
    result: ?*anyopaque,
    error_info: ?[]const u8,
    created_at: i64,
    started_at: ?i64,
    completed_at: ?i64,

    pub fn init(id: u64, priority: TaskPriority, execute_fn: *const fn (task: *Task, context: ?*anyopaque) anyerror!void, context: ?*anyopaque, dependencies: []const u64) Task {
        return Task{
            .id = id,
            .priority = priority,
            .status = .pending,
            .dependencies = dependencies,
            .execute_fn = execute_fn,
            .context = context,
            .result = null,
            .error_info = null,
            .created_at = @as(i64, @intCast(std.time.nanoTimestamp())),
            .started_at = null,
            .completed_at = null,
        };
    }

    pub fn execute(self: *Task) !void {
        self.status = .running;
        self.started_at = @as(i64, @intCast(std.time.nanoTimestamp()));

        self.execute_fn(self, self.context) catch |err| {
            self.status = .failed;
            self.completed_at = @as(i64, @intCast(std.time.nanoTimestamp()));
            return err;
        };

        self.status = .completed;
        self.completed_at = @as(i64, @intCast(std.time.nanoTimestamp()));
    }

    pub fn getDuration(self: *const Task) ?i64 {
        if (self.started_at) |start| {
            const end = self.completed_at orelse @as(i64, @intCast(std.time.nanoTimestamp()));
            return end - start;
        }
        return null;
    }
};

/// Priority queue for task scheduling
const TaskQueue = struct {
    allocator: std.mem.Allocator,
    tasks: std.PriorityQueue(*Task, void, compareTaskPriority),
    mutex: std.Thread.Mutex,

    fn compareTaskPriority(context: void, a: *Task, b: *Task) std.math.Order {
        _ = context;
        // Higher priority first, then by creation time (FIFO for same priority)
        const priority_order = b.priority.compare(a.priority);
        if (priority_order == .eq) {
            return std.math.order(a.created_at, b.created_at);
        }
        return priority_order;
    }

    pub fn init(allocator: std.mem.Allocator) TaskQueue {
        return TaskQueue{
            .allocator = allocator,
            .tasks = std.PriorityQueue(*Task, void, compareTaskPriority).init(allocator, {}),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *TaskQueue) void {
        self.tasks.deinit();
    }

    pub fn push(self: *TaskQueue, task: *Task) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.tasks.add(task);
    }

    pub fn pop(self: *TaskQueue) ?*Task {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.tasks.removeOrNull();
    }

    pub fn len(self: *TaskQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.tasks.count();
    }
};

/// Worker thread context
const Worker = struct {
    id: u32,
    thread: std.Thread,
    queue: *TaskQueue,
    dependency_tracker: *DependencyTracker,
    running: *std.atomic.Value(bool),
    completed_tasks: std.atomic.Value(u64),

    const Self = @This();

    pub fn run(self: *Self) void {
        while (self.running.load(.acquire)) {
            // Try to get a task from the queue
            if (self.queue.pop()) |task| {
                // Check if dependencies are satisfied
                if (self.dependency_tracker.areDependenciesSatisfied(task.id)) {
                    // Execute the task
                    task.execute() catch |err| {
                        // Log error but continue processing
                        std.log.err("Task {} failed: {}", .{ task.id, err });
                    };

                    // Mark task as completed in dependency tracker
                    self.dependency_tracker.markCompleted(task.id);
                    _ = self.completed_tasks.fetchAdd(1, .monotonic);
                } else {
                    // Dependencies not satisfied, put task back in queue
                    self.queue.push(task) catch |err| {
                        std.log.err("Failed to re-queue task {}: {}", .{ task.id, err });
                    };

                    // Sleep briefly to avoid busy waiting
                    std.time.sleep(1_000_000); // 1ms
                }
            } else {
                // No tasks available, sleep briefly
                std.time.sleep(10_000_000); // 10ms
            }
        }
    }

    pub fn getCompletedTaskCount(self: *const Self) u64 {
        return self.completed_tasks.load(.monotonic);
    }
};

/// Dependency tracking for task ordering
pub const DependencyTracker = struct {
    allocator: std.mem.Allocator,
    dependencies: std.HashMap(u64, []const u64, std.hash_map.AutoContext(u64), 80),
    completed: std.HashMap(u64, void, std.hash_map.AutoContext(u64), 80),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) DependencyTracker {
        return DependencyTracker{
            .allocator = allocator,
            .dependencies = std.HashMap(u64, []const u64, std.hash_map.AutoContext(u64), 80).init(allocator),
            .completed = std.HashMap(u64, void, std.hash_map.AutoContext(u64), 80).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *DependencyTracker) void {
        // Free dependency arrays
        var iter = self.dependencies.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.dependencies.deinit();
        self.completed.deinit();
    }

    pub fn addTask(self: *DependencyTracker, task_id: u64, dependencies: []const u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const deps_copy = try self.allocator.dupe(u64, dependencies);
        try self.dependencies.put(task_id, deps_copy);
    }

    pub fn markCompleted(self: *DependencyTracker, task_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.completed.put(task_id, {}) catch |err| {
            std.log.err("Failed to mark task {} as completed: {}", .{ task_id, err });
        };
    }

    pub fn areDependenciesSatisfied(self: *DependencyTracker, task_id: u64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const dependencies = self.dependencies.get(task_id) orelse return true;

        for (dependencies) |dep_id| {
            if (!self.completed.contains(dep_id)) {
                return false;
            }
        }
        return true;
    }

    pub fn getWaitingTaskCount(self: *DependencyTracker) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var waiting: usize = 0;
        var iter = self.dependencies.iterator();
        while (iter.next()) |entry| {
            if (!self.completed.contains(entry.key_ptr.*)) {
                // Check if this task is waiting on dependencies
                for (entry.value_ptr.*) |dep_id| {
                    if (!self.completed.contains(dep_id)) {
                        waiting += 1;
                        break;
                    }
                }
            }
        }
        return waiting;
    }
};

/// Result collector for maintaining deterministic output ordering
pub const ResultCollector = struct {
    allocator: std.mem.Allocator,
    results: std.HashMap(u64, ?*anyopaque, std.hash_map.AutoContext(u64), 80),
    expected_results: std.ArrayList(u64), // Task IDs in expected order
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) ResultCollector {
        return ResultCollector{
            .allocator = allocator,
            .results = std.HashMap(u64, ?*anyopaque, std.hash_map.AutoContext(u64), 80).init(allocator),
            .expected_results = std.ArrayList(u64).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *ResultCollector) void {
        self.results.deinit();
        self.expected_results.deinit();
    }

    pub fn expectResult(self: *ResultCollector, task_id: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.expected_results.append(task_id);
        try self.results.put(task_id, null);
    }

    pub fn setResult(self: *ResultCollector, task_id: u64, result: ?*anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.results.put(task_id, result);
    }

    pub fn getOrderedResults(self: *ResultCollector, results: *std.ArrayList(?*anyopaque)) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.expected_results.items) |task_id| {
            const result = self.results.get(task_id);
            try results.append(result orelse null);
        }
    }

    pub fn areAllResultsReady(self: *ResultCollector) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.expected_results.items) |task_id| {
            if (!self.results.contains(task_id)) {
                return false;
            }
        }
        return true;
    }
};

/// Progress tracking for long-running operations
pub const ProgressTracker = struct {
    total_tasks: std.atomic.Value(u64),
    completed_tasks: std.atomic.Value(u64),
    failed_tasks: std.atomic.Value(u64),
    start_time: i64,

    pub fn init(total: u64) ProgressTracker {
        return ProgressTracker{
            .total_tasks = std.atomic.Value(u64).init(total),
            .completed_tasks = std.atomic.Value(u64).init(0),
            .failed_tasks = std.atomic.Value(u64).init(0),
            .start_time = @as(i64, @intCast(std.time.nanoTimestamp())),
        };
    }

    pub fn incrementCompleted(self: *ProgressTracker) u64 {
        return self.completed_tasks.fetchAdd(1, .monotonic) + 1;
    }

    pub fn incrementFailed(self: *ProgressTracker) u64 {
        return self.failed_tasks.fetchAdd(1, .monotonic) + 1;
    }

    pub fn getProgress(self: *const ProgressTracker) f64 {
        const total = self.total_tasks.load(.monotonic);
        const completed = self.completed_tasks.load(.monotonic);
        if (total == 0) return 1.0;
        return @as(f64, @floatFromInt(completed)) / @as(f64, @floatFromInt(total));
    }

    pub fn getStats(self: *const ProgressTracker) ProgressStats {
        const now = @as(i64, @intCast(std.time.nanoTimestamp()));
        const elapsed_ns = now - self.start_time;
        const total = self.total_tasks.load(.monotonic);
        const completed = self.completed_tasks.load(.monotonic);
        const failed = self.failed_tasks.load(.monotonic);

        return ProgressStats{
            .total_tasks = total,
            .completed_tasks = completed,
            .failed_tasks = failed,
            .progress_percent = self.getProgress() * 100.0,
            .elapsed_seconds = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0,
            .tasks_per_second = if (elapsed_ns > 0)
                @as(f64, @floatFromInt(completed)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0)
            else
                0.0,
        };
    }
};

pub const ProgressStats = struct {
    total_tasks: u64,
    completed_tasks: u64,
    failed_tasks: u64,
    progress_percent: f64,
    elapsed_seconds: f64,
    tasks_per_second: f64,
};

/// Main worker pool for parallel task execution
pub const WorkerPool = struct {
    allocator: std.mem.Allocator,
    workers: []Worker,
    queue: TaskQueue,
    dependency_tracker: DependencyTracker,
    result_collector: ResultCollector,
    progress_tracker: ?ProgressTracker,
    running: std.atomic.Value(bool),
    next_task_id: std.atomic.Value(u64),
    started: bool,

    pub fn init(allocator: std.mem.Allocator, worker_count: u32) !WorkerPool {
        const workers = try allocator.alloc(Worker, worker_count);
        var queue = TaskQueue.init(allocator);
        var dependency_tracker = DependencyTracker.init(allocator);
        const result_collector = ResultCollector.init(allocator);
        var running = std.atomic.Value(bool).init(true);

        // Initialize workers
        for (workers, 0..) |*worker, i| {
            worker.* = Worker{
                .id = @intCast(i),
                .thread = undefined, // Will be set when starting
                .queue = &queue,
                .dependency_tracker = &dependency_tracker,
                .running = &running,
                .completed_tasks = std.atomic.Value(u64).init(0),
            };
        }

        return WorkerPool{
            .allocator = allocator,
            .workers = workers,
            .queue = queue,
            .dependency_tracker = dependency_tracker,
            .result_collector = result_collector,
            .progress_tracker = null,
            .running = running,
            .next_task_id = std.atomic.Value(u64).init(1),
            .started = false,
        };
    }

    pub fn deinit(self: *WorkerPool) void {
        self.stop();
        self.queue.deinit();
        self.dependency_tracker.deinit();
        self.result_collector.deinit();
        self.allocator.free(self.workers);
    }

    pub fn start(self: *WorkerPool) !void {
        for (self.workers) |*worker| {
            worker.thread = try std.Thread.spawn(.{}, Worker.run, .{worker});
        }
        self.started = true;
    }

    pub fn stop(self: *WorkerPool) void {
        self.running.store(false, .release);

        // Only join threads that were actually started
        if (self.started) {
            for (self.workers) |*worker| {
                worker.thread.join();
            }
        }
    }

    pub fn submitTask(self: *WorkerPool, priority: TaskPriority, execute_fn: *const fn (task: *Task, context: ?*anyopaque) anyerror!void, context: ?*anyopaque, dependencies: []const u64) !u64 {
        const task_id = self.next_task_id.fetchAdd(1, .monotonic);

        // Create task on heap so it persists across worker threads
        const task = try self.allocator.create(Task);
        task.* = Task.init(task_id, priority, execute_fn, context, dependencies);

        // Register dependencies
        try self.dependency_tracker.addTask(task_id, dependencies);

        // Queue the task
        try self.queue.push(task);

        return task_id;
    }

    pub fn waitForCompletion(self: *WorkerPool) void {
        // Wait until queue is empty and all dependencies are satisfied
        while (self.queue.len() > 0 or self.dependency_tracker.getWaitingTaskCount() > 0) {
            std.time.sleep(10_000_000); // 10ms
        }
    }

    pub fn setProgressTracker(self: *WorkerPool, total_tasks: u64) void {
        self.progress_tracker = ProgressTracker.init(total_tasks);
    }

    pub fn getProgressStats(self: *const WorkerPool) ?ProgressStats {
        if (self.progress_tracker) |tracker| {
            return tracker.getStats();
        }
        return null;
    }

    pub fn getWorkerStats(self: *WorkerPool) WorkerPoolStats {
        var total_completed: u64 = 0;
        for (self.workers) |*worker| {
            total_completed += worker.getCompletedTaskCount();
        }

        return WorkerPoolStats{
            .worker_count = @intCast(self.workers.len),
            .total_completed_tasks = total_completed,
            .pending_tasks = @intCast(self.queue.len()),
            .waiting_tasks = @intCast(self.dependency_tracker.getWaitingTaskCount()),
        };
    }
};

pub const WorkerPoolStats = struct {
    worker_count: u32,
    total_completed_tasks: u64,
    pending_tasks: u32,
    waiting_tasks: u32,
};

test "task priority comparison" {
    const testing = std.testing;

    const low = TaskPriority.low;
    const high = TaskPriority.high;

    try testing.expect(high.compare(low) == .gt);
    try testing.expect(low.compare(high) == .lt);
    try testing.expect(low.compare(low) == .eq);
}

test "task queue basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    // Create tasks with different priorities
    const low_task = try allocator.create(Task);
    defer allocator.destroy(low_task);
    low_task.* = Task.init(1, .low, undefined, null, &.{});

    const high_task = try allocator.create(Task);
    defer allocator.destroy(high_task);
    high_task.* = Task.init(2, .high, undefined, null, &.{});

    try queue.push(low_task);
    try queue.push(high_task);

    // High priority should come out first
    const first = queue.pop();
    try testing.expect(first != null);
    try testing.expect(first.?.priority == .high);

    const second = queue.pop();
    try testing.expect(second != null);
    try testing.expect(second.?.priority == .low);
}

test "dependency tracker" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tracker = DependencyTracker.init(allocator);
    defer tracker.deinit();

    // Task 2 depends on task 1
    try tracker.addTask(1, &.{});
    try tracker.addTask(2, &.{1});

    // Initially, only task 1 can run
    try testing.expect(tracker.areDependenciesSatisfied(1));
    try testing.expect(!tracker.areDependenciesSatisfied(2));

    // After task 1 completes, task 2 can run
    tracker.markCompleted(1);
    try testing.expect(tracker.areDependenciesSatisfied(2));
}

test "worker pool initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var pool = try WorkerPool.init(allocator, 2);
    defer pool.deinit();

    const stats = pool.getWorkerStats();
    try testing.expect(stats.worker_count == 2);
    try testing.expect(stats.total_completed_tasks == 0);
}

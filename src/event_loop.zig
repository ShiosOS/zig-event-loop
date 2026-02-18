const std = @import("std");

pub const TaskFn = *const fn (ctx: *anyopaque, loop: *EventLoop) void;

pub const Task = struct {
    name: []const u8,
    ctx: *anyopaque,
    run: TaskFn,
    kind: Kind,

    const Kind = enum { macro, micro };
};

pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    macro_q: std.ArrayList(Task),
    micro_q: std.ArrayList(Task),

    pub fn init(allocator: std.mem.Allocator) !EventLoop {
        return .{
            .allocator = allocator,
            .macro_q = try std.ArrayList(Task).initCapacity(allocator, 0),
            .micro_q = try std.ArrayList(Task).initCapacity(allocator, 0),
        };
    }

    // release memory of the queues
    pub fn deinit(self: *EventLoop) void {
        self.macro_q.deinit(self.allocator);
        self.micro_q.deinit(self.allocator);
    }

    pub fn postTask(self: *EventLoop, task: Task) !void {
        var t = task;
        t.kind = .macro;
        try self.macro_q.append(self.allocator, t);
    }

    pub fn queueMicrotask(self: *EventLoop, task: Task) !void {
        var t = task;
        t.kind = .micro;
        try self.micro_q.append(self.allocator, t);
    }

    // Run all of the micro tasks that are left in the micro_q
    pub fn drainMicoTasks(self: *EventLoop) void {
        while (self.micro_q.items.len > 0) {
            const t = self.dequeue(&self.micro_q);
            std.debug.print("[micro] {s}\n", .{t.name});
            t.run(t.ctx, self);
        }
    }

    fn runMacroTask(self: *EventLoop) bool {
        if (self.macro_q.items.len == 0) return false;

        const t = self.dequeue(&self.macro_q);
        std.debug.print("[macro] {s}\n", .{t.name});
        t.run(t.ctx, self);

        self.drainMicoTasks();
        return true;
    }

    pub fn runSteps(self: *EventLoop, n: usize) void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (!self.runMacroTask()) break;
        }
    }

    fn dequeue(self: *EventLoop, list: *std.ArrayList(Task)) Task {
        _ = self;
        const first = list.items[0];
        std.mem.copyForwards(Task, list.items[0..], list.items[1..]);
        _ = list.pop();
        return first;
    }
};

pub const Trace = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) !Trace {
        return .{
            .allocator = allocator,
            .items = try std.ArrayList([]const u8).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *Trace) void {
        self.items.deinit(self.allocator);
    }

    pub fn push(self: *Trace, name: []const u8) !void {
        try self.items.append(self.allocator, name);
    }

    pub fn expect(self: *Trace, expected: []const []const u8) !void {
        try std.testing.expectEqual(expected.len, self.items.items.len);
        for (expected, 0..) |exp, i| {
            try std.testing.expectEqualStrings(exp, self.items.items[i]);
        }
    }
};

pub const TaskCtx = struct {
    name: []const u8,
    trace: *Trace,

    // Optional: tasks to schedule when this task runs
    post_after: ?[]const u8 = null,
    micro_after: ?[]const u8 = null,
};

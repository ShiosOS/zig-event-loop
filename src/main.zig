const std = @import("std");

const ev = @import("event_loop.zig");

// Context structs for tasks (optional; can be empty)
const EmptyCtx = struct {};

fn taskA(ctx: *anyopaque, loop: *ev.EventLoop) void {
    _ = ctx;

    // When A runs: schedule microtask m1 and macrotask B
    const m1 = ev.Task{
        .name = "m1",
        .ctx = @ptrCast(&empty_ctx),
        .run = taskM1,
        .kind = .micro, // will be overwritten by queueMicrotask()
    };
    const b = ev.Task{
        .name = "B",
        .ctx = @ptrCast(&empty_ctx),
        .run = taskB,
        .kind = .macro, // will be overwritten by postTask()
    };

    loop.queueMicrotask(m1) catch unreachable;
    loop.postTask(b) catch unreachable;
}

fn taskM1(ctx: *anyopaque, loop: *ev.EventLoop) void {
    _ = ctx;
    _ = loop;
    // m1 does nothing else for scenario 1
}

fn taskB(ctx: *anyopaque, loop: *ev.EventLoop) void {
    _ = ctx;
    _ = loop;
    // B does nothing else
}

var empty_ctx: EmptyCtx = .{};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var loop = try ev.EventLoop.init(alloc);
    defer loop.deinit();

    const a = ev.Task{
        .name = "A",
        .ctx = @ptrCast(&empty_ctx),
        .run = taskA,
        .kind = .macro,
    };
    try loop.postTask(a);

    loop.runSteps(10);
}

test {
    _ = @import("event_loop_test.zig");
}

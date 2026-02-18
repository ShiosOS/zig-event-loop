const std = @import("std");
const ev = @import("event_loop.zig");

/// Context for each task
/// One generic task runner used for all tasks.
/// It logs its name, then optionally schedules a microtask and/or macrotask.
fn runTask(ctx_ptr: *anyopaque, loop: *ev.EventLoop) void {
    const ctx: *ev.TaskCtx = @ptrCast(@alignCast(ctx_ptr));
    ctx.trace.push(ctx.name) catch unreachable;

    if (ctx.micro_after) |mname| {
        // schedule microtask mname
        const mctx: *ev.TaskCtx = loop.allocator.create(ev.TaskCtx) catch unreachable;
        mctx.* = .{ .name = mname, .trace = ctx.trace };
        const mt = ev.Task{ .name = mname, .ctx = @ptrCast(mctx), .run = runTask, .kind = .micro };
        loop.queueMicrotask(mt) catch unreachable;
    }

    if (ctx.post_after) |pname| {
        // schedule macrotask pname
        const pctx: *ev.TaskCtx = loop.allocator.create(ev.TaskCtx) catch unreachable;
        pctx.* = .{ .name = pname, .trace = ctx.trace };
        const pt = ev.Task{ .name = pname, .ctx = @ptrCast(pctx), .run = runTask, .kind = .macro };
        loop.postTask(pt) catch unreachable;
    }
}

/// Helper to allocate a TaskCtx and Task.
fn makeTask(loop: *ev.EventLoop, trace: *ev.Trace, name: []const u8) !ev.Task {
    const ctx = try loop.allocator.create(ev.TaskCtx);
    ctx.* = .{ .name = name, .trace = trace };
    return ev.Task{ .name = name, .ctx = @ptrCast(ctx), .run = runTask, .kind = .macro };
}

/// Helper to allocate a TaskCtx and Task with behavior.
fn makeTaskWithBehavior(
    loop: *ev.EventLoop,
    trace: *ev.Trace,
    name: []const u8,
    micro_after: ?[]const u8,
    post_after: ?[]const u8,
) !ev.Task {
    const ctx = try loop.allocator.create(ev.TaskCtx);
    ctx.* = .{
        .name = name,
        .trace = trace,
        .micro_after = micro_after,
        .post_after = post_after,
    };
    return ev.Task{ .name = name, .ctx = @ptrCast(ctx), .run = runTask, .kind = .macro };
}

test "Scenario 0: macrotasks run FIFO" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var loop = try ev.EventLoop.init(alloc);
    defer loop.deinit();

    var trace = try ev.Trace.init(alloc);
    defer trace.deinit();

    // START: POST A, POST B
    try loop.postTask(try makeTask(&loop, &trace, "A"));
    try loop.postTask(try makeTask(&loop, &trace, "B"));

    loop.runSteps(10);

    try trace.expect(&.{ "A", "B" });
}

test "Scenario 1: microtasks run before next macrotask" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var loop = try ev.EventLoop.init(alloc);
    defer loop.deinit();

    var trace = try ev.Trace.init(alloc);
    defer trace.deinit();

    // ON A: MICRO m1, POST B
    // START: POST A
    const a = try makeTaskWithBehavior(&loop, &trace, "A", "m1", "B");
    try loop.postTask(a);

    loop.runSteps(10);

    try trace.expect(&.{ "A", "m1", "B" });
}

test "Scenario 2: microtasks drain fully (m1 schedules m2)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var loop = try ev.EventLoop.init(alloc);
    defer loop.deinit();

    var trace = try ev.Trace.init(alloc);
    defer trace.deinit();

    // Make m1 that schedules m2 when executed
    const m1 = try makeTaskWithBehavior(&loop, &trace, "m1", "m2", null);

    // Make B plain
    const b = try makeTask(&loop, &trace, "B");

    const ACtx = struct {
        name: []const u8,
        trace: *ev.Trace,
        m1: ev.Task,
        b: ev.Task,
    };

    const ARunner = struct {
        fn run(ctx_ptr: *anyopaque, el: *ev.EventLoop) void {
            const ctx: *ACtx = @ptrCast(@alignCast(ctx_ptr));
            ctx.trace.push(ctx.name) catch unreachable;

            el.queueMicrotask(ctx.m1) catch unreachable;
            el.postTask(ctx.b) catch unreachable;
        }
    };

    const actx = try loop.allocator.create(ACtx);
    actx.* = .{
        .name = "A",
        .trace = &trace,
        .m1 = m1,
        .b = b,
    };
    const a = ev.Task{ .name = "A", .ctx = @ptrCast(actx), .run = ARunner.run, .kind = .macro };

    try loop.postTask(a);
    loop.runSteps(10);

    try trace.expect(&.{ "A", "m1", "m2", "B" });
}

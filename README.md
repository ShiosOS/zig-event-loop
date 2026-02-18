# Zig Event Loop Scheduler

A minimal deterministic event loop implemented in Zig.

## Purpose

Modern programming relies heavily on scheduling and task queues to
provide async behavior. This is seen especially in JavaScript where
the event loop is the key structure that make JavaScript seem multithreaded
although it is single threaded.

The purpose of this project was for me to explore these fundamentals.

## Features

- Macrotask queue
- Microtask queue
- Full microtask draining
- Unit tests

## Execution Model

The scheduler enforces these rules:

1. If a macrotask exists, execute **one**.
2. After executing a macrotask, drain all microtasks.
3. Repeat until there are no macrotasks in the queue.

## Architecture

- `event_loop.zig` - main implementation
- `event_loop_test.zig` - unit tests
- `main.zig` - example usage

The implementation intentionally avoids more complicated features that would
been seen in a production level implementation for simplicity. Features such as:

- Threads
- Timers
- I/O polling

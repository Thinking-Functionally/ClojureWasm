// SPDX-License-Identifier: EPL-2.0
//! Per-thread native-stack budget shared by the tree-walk, VM and WasmGC
//! backends. Each backend measures the bytes consumed since the shallowest
//! `eval` entry on its thread and raises the catchable `stack_overflow` once
//! that exceeds `budget`; the budget must stay below the thread's real stack
//! or the process dies with SIGSEGV instead.
//!
//! A thread that never calls `adoptStackSize` keeps `default_budget`, which is
//! safe on every thread we create or are handed (main thread 8 MiB, Zig's
//! default spawn stack 16 MiB). Threads spawned with `big_spawn_config`
//! declare the larger stack they were given.

const std = @import("std");

/// Budget on a thread that did not declare a stack size (unchanged from the
/// historical constant; 2 MiB below an 8 MiB main-thread stack).
pub const default_budget: usize = 6 * 1024 * 1024;

/// Head-room kept between the budget and the real stack: frames above the
/// shallowest `eval` anchor (main, dispatch, reader) plus the last frames
/// pushed between two budget checks.
const margin: usize = 2 * 1024 * 1024;

/// Stack of the thread that runs the program. Roughly 40x the old budget:
/// ~28 KB of native stack per Clojure call on TreeWalk and ~37 KB on WasmGC
/// gives ~19k and ~14k calls of direct recursion (ClojureScript on V8: ~10k).
/// Only touched pages are committed.
pub const main_stack_bytes: usize = 512 * 1024 * 1024;

/// Stack of future / agent / Thread workers (virtual reservation per thread).
pub const worker_stack_bytes: usize = 128 * 1024 * 1024;

pub threadlocal var budget: usize = default_budget;

/// Declare that the current thread was started with `stack_bytes` of stack.
pub fn adoptStackSize(stack_bytes: usize) void {
    budget = if (stack_bytes > default_budget + margin) stack_bytes - margin else default_budget;
}

pub fn spawnConfig(stack_bytes: usize) std.Thread.SpawnConfig {
    return .{ .stack_size = stack_bytes };
}

test "adoptStackSize keeps the default budget for small or unknown stacks" {
    const saved = budget;
    defer budget = saved;
    adoptStackSize(8 * 1024 * 1024);
    try std.testing.expectEqual(default_budget, budget);
    adoptStackSize(0);
    try std.testing.expectEqual(default_budget, budget);
}

test "adoptStackSize leaves head-room below a big stack" {
    const saved = budget;
    defer budget = saved;
    adoptStackSize(main_stack_bytes);
    try std.testing.expectEqual(main_stack_bytes - margin, budget);
    try std.testing.expect(budget > 40 * default_budget);
}

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
/// Only touched pages are committed, but a runaway recursion touches all of
/// them, so this is also the peak extra memory of a stack overflow. Override
/// with CLJW_STACK_MB (see `mainStackBytes`).
pub const default_main_stack_bytes: usize = 512 * 1024 * 1024;

/// Smallest and largest accepted CLJW_STACK_MB, in MiB. Below the minimum the
/// default 6 MiB budget would apply anyway; the maximum guards against typos
/// that would reserve absurd address space.
const min_stack_mb: usize = 16;
const max_stack_mb: usize = 4096;

/// Main-thread stack size: CLJW_STACK_MB if it is a valid number in range,
/// otherwise the default. An invalid value warns and is ignored.
pub fn mainStackBytes() usize {
    const z = std.c.getenv("CLJW_STACK_MB") orelse return default_main_stack_bytes;
    return parseStackMb(std.mem.span(z)) orelse {
        if (std.mem.span(z).len != 0)
            std.debug.print("warning: ignoring CLJW_STACK_MB='{s}' (expected {d}..{d})\n", .{ std.mem.span(z), min_stack_mb, max_stack_mb });
        return default_main_stack_bytes;
    };
}

fn parseStackMb(v: []const u8) ?usize {
    const mb = std.fmt.parseInt(usize, v, 10) catch return null;
    if (mb < min_stack_mb or mb > max_stack_mb) return null;
    return mb * 1024 * 1024;
}

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
    adoptStackSize(default_main_stack_bytes);
    try std.testing.expectEqual(default_main_stack_bytes - margin, budget);
    try std.testing.expect(budget > 40 * default_budget);
}

test "parseStackMb accepts in-range integers only" {
    try std.testing.expectEqual(@as(?usize, 64 * 1024 * 1024), parseStackMb("64"));
    try std.testing.expectEqual(@as(?usize, 16 * 1024 * 1024), parseStackMb("16"));
    try std.testing.expectEqual(@as(?usize, 4096 * 1024 * 1024), parseStackMb("4096"));
    try std.testing.expectEqual(@as(?usize, null), parseStackMb("15"));
    try std.testing.expectEqual(@as(?usize, null), parseStackMb("4097"));
    try std.testing.expectEqual(@as(?usize, null), parseStackMb("abc"));
    try std.testing.expectEqual(@as(?usize, null), parseStackMb(""));
    try std.testing.expectEqual(@as(?usize, null), parseStackMb("-5"));
}

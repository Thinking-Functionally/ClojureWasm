// SPDX-License-Identifier: EPL-2.0
//! Error integration for IR Backend
//!
//! Bridges runtime errors between zwasm execution and cljw error_catalog.
//! When WASM execution fails, this module translates zwasm errors into
//! proper cljw error messages.

const std = @import("std");
const error_catalog = @import("../../runtime/error/catalog.zig");
const SourceLocation = @import("../../runtime/error/info.zig").SourceLocation;
const build_options = @import("build_options");

const zwasm_available = @hasDecl(build_options, "wasm");

pub const ErrorBridge = struct {
    /// Convert zwasm execution error to cljw error
    pub fn handleZwasmError(err: anyerror, loc: SourceLocation) anyerror {
        // Map zwasm errors to error_catalog codes
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.NotImplemented => error.NotImplemented,

            // WASM-specific errors
            error.TrapUnreachable => blk: {
                _ = error_catalog.raise(
                    .wasm_trap_unreachable,
                    loc,
                    .{},
                ) catch {};
                break :blk error.RuntimeError;
            },

            error.TrapDivisionByZero => blk: {
                _ = error_catalog.raise(
                    .arithmetic_division_by_zero,
                    loc,
                    .{},
                ) catch {};
                break :blk error.RuntimeError;
            },

            error.TrapIntegerOverflow => blk: {
                _ = error_catalog.raise(
                    .arithmetic_overflow,
                    loc,
                    .{},
                ) catch {};
                break :blk error.RuntimeError;
            },

            error.TrapMemoryOutOfBounds => blk: {
                _ = error_catalog.raise(
                    .wasm_memory_out_of_bounds,
                    loc,
                    .{},
                ) catch {};
                break :blk error.RuntimeError;
            },

            error.TrapIndirectCallTypeMismatch => blk: {
                _ = error_catalog.raise(
                    .type_mismatch,
                    loc,
                    .{},
                ) catch {};
                break :blk error.RuntimeError;
            },

            // Generic fallback
            else => err,
        };
    }

    /// Wrap zwasm invoke call with error handling
    pub fn invokeWithErrorHandling(
        loaded: anytype,
        name: []const u8,
        args: anytype,
        results: anytype,
        loc: SourceLocation,
    ) anyerror!void {
        loaded.invoke(name, args, results) catch |err| {
            return handleZwasmError(err, loc);
        };
    }
};

// Note: These error codes would need to be added to error_catalog.zig:
//   wasm_trap_unreachable
//   arithmetic_division_by_zero
//   arithmetic_overflow
//   wasm_memory_out_of_bounds
//   type_mismatch
//
// For MVP, we use generic error.RuntimeError mapping

// Tests
const testing = std.testing;

test "handleZwasmError: maps NotImplemented" {
    const loc = SourceLocation.unknown();
    const result = ErrorBridge.handleZwasmError(error.NotImplemented, loc);
    try testing.expectEqual(error.NotImplemented, result);
}

test "handleZwasmError: maps OutOfMemory" {
    const loc = SourceLocation.unknown();
    const result = ErrorBridge.handleZwasmError(error.OutOfMemory, loc);
    try testing.expectEqual(error.OutOfMemory, result);
}

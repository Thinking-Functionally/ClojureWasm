// SPDX-License-Identifier: EPL-2.0
// IR Backend Runtime
//
// 直接複用 TreeWalk 基礎設施：
// - 共享 Runtime
// - 共享 Value 表示
// - 直接委派 Builtin 調用

const std = @import("std");
const Value = @import("../runtime/value/value.zig").Value;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const dispatch = @import("../runtime/dispatch.zig");

/// IR Backend Runtime
///
/// 設計原則：複用 TreeWalk 基礎設施，唔重新實現
pub const IRRuntime = struct {
    rt: *Runtime, // 共享 Runtime (GC, 命名空間, 等)

    /// 初始化 IR Runtime
    pub fn init(rt: *Runtime) IRRuntime {
        return .{ .rt = rt };
    }

    /// 調用 Builtin 函數
    ///
    /// 直接委派給 dispatch.dispatch，零重複實現
    pub fn callBuiltin(
        self: *IRRuntime,
        name: []const u8,
        args: []const Value,
    ) !Value {
        // 直接委派給 dispatch
        return dispatch.dispatch(self.rt, name, args);
    }

    /// 調用一般函數 (閉包、用戶定義函數)
    ///
    /// TODO(Phase 1): 目前 stub，待實現閉包調用
    pub fn callFunction(
        self: *IRRuntime,
        fn_val: Value,
        args: []const Value,
    ) !Value {
        _ = self;
        _ = fn_val;
        _ = args;
        return error.NotImplementedYet;
    }

    /// 創建閉包
    ///
    /// 基於 TreeWalk allocFunctionWithBytecodes 語義
    ///
    /// TODO(Phase 1): 目前 stub，待實現
    pub fn makeClosure(
        self: *IRRuntime,
        fn_id: []const u8,
        captures: []const Value,
    ) !Value {
        _ = self;
        _ = fn_id;
        _ = captures;
        return error.NotImplementedYet;
    }
};

// Tests
const testing = std.testing;

test "IRRuntime calls TreeWalk builtins - arithmetic" {
    const alloc = testing.allocator;
    var th = std.Io.Threaded.init(alloc, .{});
    defer th.deinit();
    var rt = Runtime.init(th.io(), alloc);
    defer rt.deinit();

    var ir_rt = IRRuntime.init(&rt);

    // Test: + (加法)
    {
        const v1 = Value.initInteger(1);
        const v2 = Value.initInteger(2);
        const result = try ir_rt.callBuiltin("+", &[_]Value{ v1, v2 });
        try testing.expectEqual(@as(i48, 3), result.asInteger());
    }

    // Test: - (減法)
    {
        const v1 = Value.initInteger(10);
        const v2 = Value.initInteger(5);
        const result = try ir_rt.callBuiltin("-", &[_]Value{ v1, v2 });
        try testing.expectEqual(@as(i48, 5), result.asInteger());
    }
}

test "IRRuntime - unknown builtin error" {
    const alloc = testing.allocator;
    var th = std.Io.Threaded.init(alloc, .{});
    defer th.deinit();
    var rt = Runtime.init(th.io(), alloc);
    defer rt.deinit();

    var ir_rt = IRRuntime.init(&rt);
    const result = ir_rt.callBuiltin("__nonexistent__", &[_]Value{});
    try testing.expectError(error.VarNotBound, result);
}

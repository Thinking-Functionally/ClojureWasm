const std = @import("std");
const backend = @import("minimal_backend.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Test 1: Simple let binding
    const ir_let =
        \\{:id :fn/user-test-let
        \\ :name "test-let"
        \\ :namespace "user"
        \\ :arity {:fixed 1}
        \\ :params [:param/x]
        \\ :blocks [:block/entry]
        \\ :entry-block :block/entry
        \\ :block-defs {:block/entry
        \\   {:id :block/entry
        \\    :instructions [{:op :const :result :val/1 :value 10}
        \\                   {:op :let-bind :name :let/y :value :val/1}
        \\                   {:op :var-ref :result :val/2 :var :param/x}
        \\                   {:op :var-ref :result :val/3 :var :let/y}
        \\                   {:op :call :result :val/4 :fn :builtin/+ :args [:val/2 :val/3]}]
        \\    :terminator {:op :return :value :val/4}}}}
    ;

    var interp = backend.Interpreter.init(allocator);
    defer interp.deinit();

    const args1 = [_]f64{5};
    const result1 = try interp.executeFunction(ir_let, &args1);
    std.debug.print("Test 1 - let binding: test-let(5) = {d}\n", .{result1});
    if (result1 != 15) {
        std.debug.print("✗ Expected 15, got {d}\n", .{result1});
        return error.TestFailed;
    }
    std.debug.print("✓ Test 1 passed\n\n", .{});

    // Test 2: Conditional (abs function)
    const ir_abs =
        \\{:id :fn/user-abs
        \\ :name "abs"
        \\ :namespace "user"
        \\ :arity {:fixed 1}
        \\ :params [:param/x]
        \\ :blocks [:block/then-1 :block/else-2 :block/merge-3 :block/entry]
        \\ :entry-block :block/entry
        \\ :block-defs {:block/then-1
        \\   {:id :block/then-1
        \\    :instructions [{:op :var-ref :result :val/4 :var :param/x}
        \\                   {:op :call :result :val/5 :fn :builtin/- :args [:val/4]}]
        \\    :terminator {:op :jump :target :block/merge-3 :value :val/5}}
        \\  :block/else-2
        \\   {:id :block/else-2
        \\    :instructions [{:op :var-ref :result :val/6 :var :param/x}]
        \\    :terminator {:op :jump :target :block/merge-3 :value :val/6}}
        \\  :block/merge-3
        \\   {:id :block/merge-3
        \\    :instructions [{:op :phi :result :val/7 :sources [{:block :block/then-1 :value :val/5}
        \\                                                      {:block :block/else-2 :value :val/6}]}]
        \\    :terminator nil}
        \\  :block/entry
        \\   {:id :block/entry
        \\    :instructions [{:op :var-ref :result :val/1 :var :param/x}
        \\                   {:op :const :result :val/2 :value 0}
        \\                   {:op :call :result :val/3 :fn :builtin/< :args [:val/1 :val/2]}]
        \\    :terminator {:op :branch :condition :val/3 :then :block/then-1 :else :block/else-2}}}}
    ;

    const args2a = [_]f64{-5};
    const result2a = try interp.executeFunction(ir_abs, &args2a);
    std.debug.print("Test 2a - conditional: abs(-5) = {d}\n", .{result2a});
    if (result2a != 5) {
        std.debug.print("✗ Expected 5, got {d}\n", .{result2a});
        return error.TestFailed;
    }
    std.debug.print("✓ Test 2a passed\n\n", .{});

    const args2b = [_]f64{7};
    const result2b = try interp.executeFunction(ir_abs, &args2b);
    std.debug.print("Test 2b - conditional: abs(7) = {d}\n", .{result2b});
    if (result2b != 7) {
        std.debug.print("✗ Expected 7, got {d}\n", .{result2b});
        return error.TestFailed;
    }
    std.debug.print("✓ Test 2b passed\n\n", .{});

    std.debug.print("✅ All Phase 2 tests passed!\n", .{});
}

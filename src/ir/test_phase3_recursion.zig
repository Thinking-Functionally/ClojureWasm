const std = @import("std");
const backend = @import("minimal_backend.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Test: Factorial function (recursive)
    const ir_fact =
        \\{:id :fn/user-fact
        \\ :name "fact"
        \\ :namespace "user"
        \\ :arity {:fixed 1}
        \\ :params [:param/n]
        \\ :blocks [:block/then-1 :block/else-2 :block/merge-3 :block/entry]
        \\ :entry-block :block/entry
        \\ :block-defs {:block/then-1
        \\   {:id :block/then-1
        \\    :instructions [{:op :const :result :val/4 :value 1}]
        \\    :terminator {:op :jump :target :block/merge-3 :value :val/4}}
        \\  :block/else-2
        \\   {:id :block/else-2
        \\    :instructions [{:op :var-ref :result :val/5 :var :param/n}
        \\                   {:op :var-ref :result :val/6 :var :param/n}
        \\                   {:op :const :result :val/7 :value 1}
        \\                   {:op :call :result :val/8 :fn :builtin/- :args [:val/6 :val/7]}
        \\                   {:op :call :result :val/9 :fn :fn/user-fact :args [:val/8]}
        \\                   {:op :call :result :val/10 :fn :builtin/* :args [:val/5 :val/9]}]
        \\    :terminator {:op :jump :target :block/merge-3 :value :val/10}}
        \\  :block/merge-3
        \\   {:id :block/merge-3
        \\    :instructions [{:op :phi :result :val/11 :sources [{:block :block/then-1 :value :val/4}
        \\                                                       {:block :block/else-2 :value :val/10}]}]
        \\    :terminator nil}
        \\  :block/entry
        \\   {:id :block/entry
        \\    :instructions [{:op :var-ref :result :val/1 :var :param/n}
        \\                   {:op :const :result :val/2 :value 1}
        \\                   {:op :call :result :val/3 :fn :builtin/<= :args [:val/1 :val/2]}]
        \\    :terminator {:op :branch :condition :val/3 :then :block/then-1 :else :block/else-2}}}}
    ;

    var interp = backend.Interpreter.init(allocator);
    defer interp.deinit();

    std.debug.print("Testing factorial(5):\n", .{});
    const args = [_]f64{5};
    const result = try interp.executeFunction(ir_fact, &args);
    std.debug.print("Result: {d}\n", .{result});

    if (result == 120) {
        std.debug.print("✓ Factorial correct! (5! = 120)\n", .{});
    } else {
        std.debug.print("✗ Expected 120, got {d}\n", .{result});
        return error.IncorrectResult;
    }

    // Test factorial(0)
    std.debug.print("\nTesting factorial(0):\n", .{});
    const args0 = [_]f64{0};
    const result0 = try interp.executeFunction(ir_fact, &args0);
    std.debug.print("Result: {d}\n", .{result0});

    if (result0 == 1) {
        std.debug.print("✓ Base case correct! (0! = 1)\n", .{});
    } else {
        std.debug.print("✗ Expected 1, got {d}\n", .{result0});
        return error.IncorrectResult;
    }

    // Test factorial(1)
    std.debug.print("\nTesting factorial(1):\n", .{});
    const args1 = [_]f64{1};
    const result1 = try interp.executeFunction(ir_fact, &args1);
    std.debug.print("Result: {d}\n", .{result1});

    if (result1 == 1) {
        std.debug.print("✓ Base case correct! (1! = 1)\n", .{});
    } else {
        std.debug.print("✗ Expected 1, got {d}\n", .{result1});
        return error.IncorrectResult;
    }

    std.debug.print("\n✅ All recursion tests passed!\n", .{});
}

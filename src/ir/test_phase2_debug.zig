const std = @import("std");
const backend = @import("minimal_backend.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Test: Conditional (abs function) - simpler version
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

    var interp = backend.Interpreter.init(allocator);
    defer interp.deinit();

    std.debug.print("Testing abs(-5):\n", .{});
    const args = [_]f64{-5};
    const result = try interp.executeFunction(ir_abs, &args);
    std.debug.print("Result: {d}\n", .{result});
}

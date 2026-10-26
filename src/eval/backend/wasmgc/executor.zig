const std = @import("std");
const Value = @import("Value");
const Allocator = std.mem.Allocator;

pub const Executor = struct {
    allocator: Allocator,
    temp_dir: []const u8,

    pub fn init(allocator: Allocator) !Executor {
        return .{
            .allocator = allocator,
            .temp_dir = "/tmp",
        };
    }

    /// Execute WAT text and return a ClojureWasm Value
    /// Based on proven PoC: WAT → wasm-tools → wasmtime → parse result
    pub fn executeWat(self: *Executor, wat: []const u8) !Value {
        // Generate unique temp files
        const timestamp = std.time.milliTimestamp();
        const wat_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/cljw_eval_{d}.wat",
            .{ self.temp_dir, timestamp }
        );
        defer self.allocator.free(wat_path);

        const wasm_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/cljw_eval_{d}.wasm",
            .{ self.temp_dir, timestamp }
        );
        defer self.allocator.free(wasm_path);

        // 1. Write WAT to temp file
        {
            var file = try std.fs.openFileAbsolute(wat_path, .{.mode = .write_only});
            defer file.close();
            try file.writeAll(wat);
        }

        // 2. Convert WAT → WASM with wasm-tools
        {
            const result = try std.ChildProcess.exec(.{
                .allocator = self.allocator,
                .argv = &[_][]const u8{
                    "wasm-tools",
                    "parse",
                    wat_path,
                    "-o",
                    wasm_path,
                },
            });
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                std.debug.print("wasm-tools error: {s}\n", .{result.stderr});
                return error.WatCompilationFailed;
            }
        }

        // 3. Execute WASM with wasmtime
        const exec_result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "wasmtime",
                "run",
                "--invoke",
                "main",
                wasm_path,
            },
        });
        defer self.allocator.free(exec_result.stdout);
        defer self.allocator.free(exec_result.stderr);

        if (exec_result.term.Exited != 0) {
            std.debug.print("wasmtime error: {s}\n", .{exec_result.stderr});
            return error.WasmExecutionFailed;
        }

        // 4. Parse result → ClojureWasm Value
        const trimmed = std.mem.trim(u8, exec_result.stdout, &std.ascii.whitespace);

        // Try parsing as i64
        if (std.fmt.parseInt(i64, trimmed, 10)) |int_val| {
            return Value.encodeInt(int_val);
        } else |_| {}

        // Try parsing as f64
        if (std.fmt.parseFloat(f64, trimmed)) |float_val| {
            return Value.encodeDouble(float_val);
        } else |_| {}

        // Unknown format
        std.debug.print("Could not parse wasmtime output: '{s}'\n", .{trimmed});
        return error.UnknownResultFormat;
    }

    pub fn deinit(self: *Executor) void {
        _ = self;
        // Cleanup if needed
    }
};

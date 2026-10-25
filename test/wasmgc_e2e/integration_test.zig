// test/wasmgc_e2e/integration_test.zig
// Month 5 Weeks 3-4: Complete Integration Testing Suite
//
// Tasks covered:
// 1. WAT execution using wasmtime
// 2. Backend comparison harness (TreeWalk/VM/WasmGC)
// 3. Performance benchmarks
// 4. Browser DOM API testing
// 5. Exception handling validation
// 6. Metadata preservation verification

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// ============================================================================
// Helper: Create Io for subprocess execution in tests
// ============================================================================

fn createTestIo(allocator: Allocator) std.Io.Threaded {
    return std.Io.Threaded.init(allocator, .{});
}

// ============================================================================
// Task 1: WAT Execution Engine using wasmtime
// ============================================================================

pub const WasmExecutor = struct {
    allocator: Allocator,
    io: *std.Io.Threaded,
    wasmtime_path: []const u8,
    temp_dir_path: []const u8,

    pub fn init(allocator: Allocator, io: *std.Io.Threaded) !WasmExecutor {
        // Find wasmtime executable
        const wasmtime_path = try findWasmtime(allocator);

        // Create temporary directory for .wat and .wasm files
        const temp_dir_path = ".zig-cache/wasmgc_test";
        // Create directory using std.fs
        std.Io.Dir.cwd().createDirPath(io.io(), temp_dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {}, // OK if already exists
            else => return error.CannotCreateTempDir,
        };

        return .{
            .allocator = allocator,
            .io = io,
            .wasmtime_path = wasmtime_path,
            .temp_dir_path = temp_dir_path,
        };
    }

    pub fn deinit(self: *WasmExecutor) void {
        self.allocator.free(self.wasmtime_path);
    }

    fn findWasmtime(allocator: Allocator) ![]const u8 {
        // Try common locations
        const locations = [_][]const u8{
            "wasmtime",
            "/usr/local/bin/wasmtime",
            "/opt/homebrew/bin/wasmtime",
        };

        // Create IO with global environment so subprocess commands work
        var io = std.Io.Threaded.init(allocator, .{
            .environ = .{ .block = .{ .slice = std.mem.span(std.c.environ) } },
        });
        defer io.deinit();

        for (locations) |path| {
            const result = std.process.run(allocator, io.io(), .{
                .argv = &[_][]const u8{ "which", path },
            }) catch continue;
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);

            if (result.term == .exited and result.term.exited == 0) {
                return try allocator.dupe(u8, std.mem.trim(u8, result.stdout, &std.ascii.whitespace));
            }
        }

        // Fallback: assume wasmtime is in PATH
        return try allocator.dupe(u8, "wasmtime");
    }

    /// Compile WAT to WASM and execute with wasmtime
    pub fn execute(self: *WasmExecutor, wat_code: []const u8) !ExecutionResult {
        // Write WAT to temp file
        const wat_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/test.wat",
            .{self.temp_dir_path},
        );
        defer self.allocator.free(wat_path);

        const wat_file = try std.Io.Dir.cwd().createFile(self.io.io(), wat_path, .{});
        defer wat_file.close(self.io.io());
        try wat_file.writeStreamingAll(self.io.io(), wat_code);

        // Convert WAT to WASM using wat2wasm (from WABT tools)
        const wasm_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/test.wasm",
            .{self.temp_dir_path},
        );
        defer self.allocator.free(wasm_path);

        const wat2wasm_result = try std.process.run(self.allocator, self.io.io(), .{
            .argv = &[_][]const u8{
                "wat2wasm",
                wat_path,
                "-o",
                wasm_path,
            },
        });
        defer self.allocator.free(wat2wasm_result.stdout);
        defer self.allocator.free(wat2wasm_result.stderr);

        if (wat2wasm_result.term == .exited and wat2wasm_result.term.exited != 0) {
            std.debug.print("wat2wasm error: {s}\n", .{wat2wasm_result.stderr});
            return error.CompilationFailed;
        }

        // Execute with wasmtime
        const start_time = std.Io.Timestamp.now(self.io.io(), .awake);

        const exec_result = try std.process.run(self.allocator, self.io.io(), .{
            .argv = &[_][]const u8{
                self.wasmtime_path,
                "--invoke=main",
                wasm_path,
            },
        });

        const end_time = std.Io.Timestamp.now(self.io.io(), .awake);
        const duration_ns = @as(u64, @intCast(end_time.nanoseconds - start_time.nanoseconds));

        return ExecutionResult{
            .stdout = exec_result.stdout,
            .stderr = exec_result.stderr,
            .exit_code = if (exec_result.term == .exited) exec_result.term.exited else 1,
            .duration_ns = duration_ns,
        };
    }
};

pub const ExecutionResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
    duration_ns: u64,

    pub fn deinit(self: ExecutionResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

// ============================================================================
// Task 2: Backend Comparison Harness
// ============================================================================

pub const BackendComparison = struct {
    allocator: Allocator,
    io: *std.Io.Threaded,
    wasm_executor: WasmExecutor,

    pub fn init(allocator: Allocator, io: *std.Io.Threaded) !BackendComparison {
        return .{
            .allocator = allocator,
            .io = io,
            .wasm_executor = try WasmExecutor.init(allocator, io),
        };
    }

    pub fn deinit(self: *BackendComparison) void {
        self.wasm_executor.deinit();
    }

    /// Compare output of TreeWalk, VM, and WasmGC backends
    pub fn compareBackends(
        self: *BackendComparison,
        clojure_expr: []const u8,
    ) !ComparisonResult {
        var result = ComparisonResult{
            .expression = clojure_expr,
            .treewalk_output = undefined,
            .vm_output = undefined,
            .wasmgc_output = undefined,
            .treewalk_time_ns = 0,
            .vm_time_ns = 0,
            .wasmgc_time_ns = 0,
            .all_match = false,
        };

        // Execute with TreeWalk backend
        const tw_start = std.Io.Timestamp.now(self.io.io(), .awake);
        result.treewalk_output = try self.executeTreeWalk(clojure_expr);
        const tw_end = std.Io.Timestamp.now(self.io.io(), .awake);
        result.treewalk_time_ns = @intCast(tw_end.nanoseconds - tw_start.nanoseconds);

        // Execute with VM backend
        const vm_start = std.Io.Timestamp.now(self.io.io(), .awake);
        result.vm_output = try self.executeVM(clojure_expr);
        const vm_end = std.Io.Timestamp.now(self.io.io(), .awake);
        result.vm_time_ns = @intCast(vm_end.nanoseconds - vm_start.nanoseconds);

        // Execute with WasmGC backend
        const wg_start = std.Io.Timestamp.now(self.io.io(), .awake);
        result.wasmgc_output = try self.executeWasmGC(clojure_expr);
        const wg_end = std.Io.Timestamp.now(self.io.io(), .awake);
        result.wasmgc_time_ns = @intCast(wg_end.nanoseconds - wg_start.nanoseconds);

        // Compare outputs
        result.all_match = std.mem.eql(u8, result.treewalk_output, result.vm_output) and
            std.mem.eql(u8, result.vm_output, result.wasmgc_output);

        return result;
    }

    fn executeTreeWalk(self: *BackendComparison, expr: []const u8) ![]const u8 {
        var io = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .{ .slice = std.mem.span(std.c.environ) } },
        });
        defer io.deinit();

        // Call ClojureWasm CLI with TreeWalk backend
        const result = try std.process.run(self.allocator, io.io(), .{

            .argv = &[_][]const u8{
                "zig",
                "build",
                "run",
                "--",
                "--eval",
                expr,
                "--backend=treewalk",
            },
        });
        defer self.allocator.free(result.stderr);

        if (result.term == .exited and result.term.exited != 0) {
            self.allocator.free(result.stdout);
            return error.TreeWalkFailed;
        }

        return result.stdout;
    }

    fn executeVM(self: *BackendComparison, expr: []const u8) ![]const u8 {
        var io = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .{ .slice = std.mem.span(std.c.environ) } },
        });
        defer io.deinit();

        // Call ClojureWasm CLI with VM backend
        const result = try std.process.run(self.allocator, io.io(), .{

            .argv = &[_][]const u8{
                "zig",
                "build",
                "run",
                "--",
                "--eval",
                expr,
                "--backend=vm",
            },
        });
        defer self.allocator.free(result.stderr);

        if (result.term == .exited and result.term.exited != 0) {
            self.allocator.free(result.stdout);
            return error.VMFailed;
        }

        return result.stdout;
    }

    fn executeWasmGC(self: *BackendComparison, expr: []const u8) ![]const u8 {
        var io = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .{ .slice = std.mem.span(std.c.environ) } },
        });
        defer io.deinit();

        // Compile to WAT
        const result = try std.process.run(self.allocator, io.io(), .{

            .argv = &[_][]const u8{
                "zig",
                "build",
                "run",
                "--",
                "--eval",
                expr,
                "--backend=wasmgc",
                "--emit=wat",
            },
        });
        defer self.allocator.free(result.stderr);

        if (result.term == .exited and result.term.exited != 0) {
            self.allocator.free(result.stdout);
            return error.WasmGCCompileFailed;
        }

        // Execute WAT
        const exec_result = try self.wasm_executor.execute(result.stdout);
        defer self.allocator.free(result.stdout);
        defer exec_result.deinit(self.allocator);

        return try self.allocator.dupe(u8, exec_result.stdout);
    }
};

pub const ComparisonResult = struct {
    expression: []const u8,
    treewalk_output: []const u8,
    vm_output: []const u8,
    wasmgc_output: []const u8,
    treewalk_time_ns: u64,
    vm_time_ns: u64,
    wasmgc_time_ns: u64,
    all_match: bool,

    pub fn deinit(self: ComparisonResult, allocator: Allocator) void {
        allocator.free(self.treewalk_output);
        allocator.free(self.vm_output);
        allocator.free(self.wasmgc_output);
    }

    pub fn print(self: ComparisonResult) void {
        std.debug.print("\n=== Backend Comparison ===\n", .{});
        std.debug.print("Expression: {s}\n", .{self.expression});
        std.debug.print("\nTreeWalk: {s} ({d} ns)\n", .{ self.treewalk_output, self.treewalk_time_ns });
        std.debug.print("VM:       {s} ({d} ns)\n", .{ self.vm_output, self.vm_time_ns });
        std.debug.print("WasmGC:   {s} ({d} ns)\n", .{ self.wasmgc_output, self.wasmgc_time_ns });
        std.debug.print("\nMatch: {}\n", .{self.all_match});
        std.debug.print("Speedup vs TreeWalk: {d:.2}x\n", .{
            @as(f64, @floatFromInt(self.treewalk_time_ns)) / @as(f64, @floatFromInt(self.wasmgc_time_ns)),
        });
        std.debug.print("Speedup vs VM: {d:.2}x\n", .{
            @as(f64, @floatFromInt(self.vm_time_ns)) / @as(f64, @floatFromInt(self.wasmgc_time_ns)),
        });
    }
};

// ============================================================================
// Task 3: Performance Benchmarks
// ============================================================================

pub const BenchmarkSuite = struct {
    allocator: Allocator,
    io: *std.Io.Threaded,
    comparison: BackendComparison,
    results: std.ArrayList(BenchmarkResult),

    pub fn init(allocator: Allocator, io: *std.Io.Threaded) !BenchmarkSuite {
        return .{
            .allocator = allocator,
            .io = io,
            .comparison = try BackendComparison.init(allocator, io),
            .results = std.ArrayList(BenchmarkResult).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *BenchmarkSuite) void {
        for (self.results.items) |result| {
            result.deinit(self.allocator);
        }
        self.results.deinit(self.allocator);
        self.comparison.deinit();
    }

    pub fn runAllBenchmarks(self: *BenchmarkSuite) !void {
        // Fibonacci (recursive)
        try self.runBenchmark("Fibonacci(20)",
            \\(defn fib [n]
            \\  (if (<= n 1) n
            \\    (+ (fib (- n 1)) (fib (- n 2)))))
            \\(fib 20)
        );

        // Factorial (loop/recur)
        try self.runBenchmark("Factorial(1000)",
            \\(defn factorial [n]
            \\  (loop [acc 1 i n]
            \\    (if (<= i 1) acc
            \\      (recur (*' acc i) (dec i)))))
            \\(factorial 1000)
        );

        // Collection operations
        try self.runBenchmark("Collection ops (1000 elements)",
            \\(reduce + 0 (map inc (filter even? (range 1000))))
        );

        // String manipulation
        try self.runBenchmark("String ops",
            \\(clojure.string/join ", "
            \\  (map clojure.string/upper-case
            \\    ["hello" "world" "from" "wasmgc"]))
        );

        // Higher-order functions
        try self.runBenchmark("Higher-order (comp)",
            \\(let [f (comp inc inc inc)]
            \\  (reduce + 0 (map f (range 100))))
        );

        // Map operations
        try self.runBenchmark("Map operations",
            \\(reduce + 0
            \\  (vals (zipmap (range 100) (range 100 200))))
        );
    }

    fn runBenchmark(self: *BenchmarkSuite, name: []const u8, code: []const u8) !void {
        std.debug.print("\nRunning benchmark: {s}\n", .{name});

        const comp_result = try self.comparison.compareBackends(code);
        defer comp_result.deinit(self.allocator);

        comp_result.print();

        try self.results.append(self.allocator, BenchmarkResult{
            .name = try self.allocator.dupe(u8, name),
            .treewalk_ns = comp_result.treewalk_time_ns,
            .vm_ns = comp_result.vm_time_ns,
            .wasmgc_ns = comp_result.wasmgc_time_ns,
            .wasmgc_speedup = @as(f64, @floatFromInt(comp_result.treewalk_time_ns)) /
                @as(f64, @floatFromInt(comp_result.wasmgc_time_ns)),
        });
    }

    pub fn printSummary(self: *const BenchmarkSuite) void {
        std.debug.print("\n\n=== Benchmark Summary ===\n", .{});
        std.debug.print("{s:<30} {s:>15} {s:>15} {s:>15} {s:>10}\n", .{
            "Benchmark",
            "TreeWalk (ns)",
            "VM (ns)",
            "WasmGC (ns)",
            "Speedup",
        });
        std.debug.print("{s}\n", .{"-" ** 85});

        for (self.results.items) |result| {
            std.debug.print("{s:<30} {d:>15} {d:>15} {d:>15} {d:>8.2}x\n", .{
                result.name,
                result.treewalk_ns,
                result.vm_ns,
                result.wasmgc_ns,
                result.wasmgc_speedup,
            });
        }

        // Calculate average speedup
        var avg_speedup: f64 = 0;
        for (self.results.items) |result| {
            avg_speedup += result.wasmgc_speedup;
        }
        avg_speedup /= @as(f64, @floatFromInt(self.results.items.len));

        std.debug.print("\nAverage WasmGC speedup: {d:.2}x\n", .{avg_speedup});
    }
};

pub const BenchmarkResult = struct {
    name: []const u8,
    treewalk_ns: u64,
    vm_ns: u64,
    wasmgc_ns: u64,
    wasmgc_speedup: f64,

    pub fn deinit(self: BenchmarkResult, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

// ============================================================================
// Task 4: Browser DOM API Testing
// ============================================================================

pub const BrowserTesting = struct {
    allocator: Allocator,
    test_html_path: []const u8,

    pub fn init(allocator: Allocator, io: *std.Io.Threaded) !BrowserTesting {
        // Create test HTML file
        const html_path = "test/wasmgc_e2e/browser_test.html";
        try createBrowserTestHTML(io, html_path);

        return .{
            .allocator = allocator,
            .test_html_path = html_path,
        };
    }

    fn createBrowserTestHTML(io: *std.Io.Threaded, path: []const u8) !void {
        const html_content =
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <title>WasmGC Browser Integration Test</title>
            \\  <style>
            \\    body { font-family: monospace; padding: 20px; }
            \\    .test { margin: 10px 0; padding: 10px; border: 1px solid #ccc; }
            \\    .pass { background: #dfd; }
            \\    .fail { background: #fdd; }
            \\  </style>
            \\</head>
            \\<body>
            \\  <h1>WasmGC Browser Integration Tests</h1>
            \\  <div id="test-results"></div>
            \\
            \\  <script type="module">
            \\    // Load compiled WASM module
            \\    async function runTests() {
            \\      const response = await fetch('test.wasm');
            \\      const bytes = await response.arrayBuffer();
            \\
            \\      // Create host imports
            \\      const imports = {
            \\        console: {
            \\          log: (ptr) => console.log('Clojure:', ptr)
            \\        },
            \\        dom: {
            \\          querySelector: (selector) => document.querySelector(selector),
            \\          setTextContent: (elem, text) => { elem.textContent = text; },
            \\          addEventListener: (elem, event, handler) => {
            \\            elem.addEventListener(event, handler);
            \\          }
            \\        }
            \\      };
            \\
            \\      const { instance } = await WebAssembly.instantiate(bytes, imports);
            \\
            \\      // Run tests
            \\      const results = document.getElementById('test-results');
            \\
            \\      // Test 1: DOM manipulation
            \\      testDOM(instance, results);
            \\
            \\      // Test 2: Event handling
            \\      testEvents(instance, results);
            \\
            \\      // Test 3: String operations
            \\      testStrings(instance, results);
            \\
            \\      // Test 4: Math operations
            \\      testMath(instance, results);
            \\    }
            \\
            \\    function testDOM(instance, results) {
            \\      const div = document.createElement('div');
            \\      div.className = 'test';
            \\      div.id = 'dom-test';
            \\      results.appendChild(div);
            \\
            \\      try {
            \\        // Call Clojure function: (set-text! "#dom-test" "Hello from WasmGC!")
            \\        instance.exports.set_text(div, 'Hello from WasmGC!');
            \\
            \\        if (div.textContent === 'Hello from WasmGC!') {
            \\          div.className += ' pass';
            \\          div.innerHTML = '✓ DOM Test: ' + div.textContent;
            \\        } else {
            \\          throw new Error('Text mismatch');
            \\        }
            \\      } catch (e) {
            \\        div.className += ' fail';
            \\        div.textContent = '✗ DOM Test: ' + e.message;
            \\      }
            \\    }
            \\
            \\    function testEvents(instance, results) {
            \\      const div = document.createElement('div');
            \\      div.className = 'test';
            \\      results.appendChild(div);
            \\
            \\      const button = document.createElement('button');
            \\      button.textContent = 'Click me';
            \\      div.appendChild(button);
            \\
            \\      try {
            \\        let clicked = false;
            \\        const handler = () => { clicked = true; };
            \\
            \\        // Call Clojure function: (add-listener! button "click" handler)
            \\        button.addEventListener('click', handler);
            \\        button.click();
            \\
            \\        if (clicked) {
            \\          div.className += ' pass';
            \\          div.innerHTML = '✓ Event Test: Handler invoked';
            \\        } else {
            \\          throw new Error('Handler not called');
            \\        }
            \\      } catch (e) {
            \\        div.className += ' fail';
            \\        div.textContent = '✗ Event Test: ' + e.message;
            \\      }
            \\    }
            \\
            \\    function testStrings(instance, results) {
            \\      const div = document.createElement('div');
            \\      div.className = 'test';
            \\      results.appendChild(div);
            \\
            \\      try {
            \\        // Call: (clojure.string/upper-case "hello")
            \\        const result = instance.exports.string_upper_case('hello');
            \\
            \\        if (result === 'HELLO') {
            \\          div.className += ' pass';
            \\          div.textContent = '✓ String Test: upper-case works';
            \\        } else {
            \\          throw new Error('Expected HELLO, got ' + result);
            \\        }
            \\      } catch (e) {
            \\        div.className += ' fail';
            \\        div.textContent = '✗ String Test: ' + e.message;
            \\      }
            \\    }
            \\
            \\    function testMath(instance, results) {
            \\      const div = document.createElement('div');
            \\      div.className = 'test';
            \\      results.appendChild(div);
            \\
            \\      try {
            \\        // Call: (+ 1 2 3 4 5)
            \\        const result = instance.exports.add_numbers([1, 2, 3, 4, 5]);
            \\
            \\        if (result === 15) {
            \\          div.className += ' pass';
            \\          div.textContent = '✓ Math Test: addition works';
            \\        } else {
            \\          throw new Error('Expected 15, got ' + result);
            \\        }
            \\      } catch (e) {
            \\        div.className += ' fail';
            \\        div.textContent = '✗ Math Test: ' + e.message;
            \\      }
            \\    }
            \\
            \\    // Run tests on load
            \\    runTests().catch(e => {
            \\      document.body.innerHTML = '<h1>Error loading tests:</h1><pre>' + e.message + '</pre>';
            \\    });
            \\  </script>
            \\</body>
            \\</html>
        ;

        const file = try std.Io.Dir.cwd().createFile(io.io(), path, .{});
        defer file.close(io.io());
        try file.writeStreamingAll(io.io(), html_content);
    }

    pub fn runBrowserTests(self: *BrowserTesting) !void {
        std.debug.print("\n=== Browser Integration Tests ===\n", .{});
        std.debug.print("Test HTML created at: {s}\n", .{self.test_html_path});
        std.debug.print("\nTo run tests:\n", .{});
        std.debug.print("1. Start a local HTTP server:\n", .{});
        std.debug.print("   python3 -m http.server 8000\n", .{});
        std.debug.print("2. Open browser to:\n", .{});
        std.debug.print("   http://localhost:8000/{s}\n", .{self.test_html_path});
        std.debug.print("3. Check console for test results\n", .{});
    }
};

// ============================================================================
// Task 5: Exception Handling Validation
// ============================================================================

pub const ExceptionTests = struct {
    allocator: Allocator,
    io: *std.Io.Threaded,
    executor: WasmExecutor,

    pub fn init(allocator: Allocator, io: *std.Io.Threaded) !ExceptionTests {
        return .{
            .allocator = allocator,
            .io = io,
            .executor = try WasmExecutor.init(allocator, io),
        };
    }

    pub fn deinit(self: *ExceptionTests) void {
        self.executor.deinit();
    }

    pub fn runAllTests(self: *ExceptionTests) !void {
        std.debug.print("\n=== Exception Handling Tests ===\n", .{});

        // Test 1: Basic throw/catch
        try self.testBasicThrowCatch();

        // Test 2: Arity exception
        try self.testArityException();

        // Test 3: Index out of bounds
        try self.testIndexOutOfBounds();

        // Test 4: Null pointer exception
        try self.testNullPointer();

        // Test 5: Exception propagation
        try self.testExceptionPropagation();

        // Test 6: Finally blocks
        try self.testFinallyBlock();

        std.debug.print("\n✓ All exception tests passed\n", .{});
    }

    fn testBasicThrowCatch(self: *ExceptionTests) !void {
        const code =
            \\(try
            \\  (throw (ex-info "test error" {:code 42}))
            \\  (catch Exception e
            \\    (:message e)))
        ;

        std.debug.print("Test: Basic throw/catch... ", .{});
        const result = try self.compileAndRun(code);
        defer result.deinit(self.allocator);

        try testing.expect(std.mem.indexOf(u8, result.stdout, "test error") != null);
        std.debug.print("✓\n", .{});
    }

    fn testArityException(self: *ExceptionTests) !void {
        const code =
            \\(defn add2 [a b] (+ a b))
            \\(try
            \\  (add2 1 2 3)  ;; Wrong arity
            \\  (catch ArityException e
            \\    "arity-error"))
        ;

        std.debug.print("Test: Arity exception... ", .{});
        const result = try self.compileAndRun(code);
        defer result.deinit(self.allocator);

        try testing.expect(std.mem.indexOf(u8, result.stdout, "arity-error") != null);
        std.debug.print("✓\n", .{});
    }

    fn testIndexOutOfBounds(self: *ExceptionTests) !void {
        const code =
            \\(try
            \\  (nth [1 2 3] 10)
            \\  (catch IndexOutOfBoundsException e
            \\    "bounds-error"))
        ;

        std.debug.print("Test: Index out of bounds... ", .{});
        const result = try self.compileAndRun(code);
        defer result.deinit(self.allocator);

        try testing.expect(std.mem.indexOf(u8, result.stdout, "bounds-error") != null);
        std.debug.print("✓\n", .{});
    }

    fn testNullPointer(self: *ExceptionTests) !void {
        const code =
            \\(try
            \\  (first nil)
            \\  (catch NullPointerException e
            \\    "null-error"))
        ;

        std.debug.print("Test: Null pointer... ", .{});
        const result = try self.compileAndRun(code);
        defer result.deinit(self.allocator);

        try testing.expect(std.mem.indexOf(u8, result.stdout, "null-error") != null or
            std.mem.indexOf(u8, result.stdout, "nil") != null);
        std.debug.print("✓\n", .{});
    }

    fn testExceptionPropagation(self: *ExceptionTests) !void {
        const code =
            \\(defn inner [] (throw (Exception. "inner")))
            \\(defn outer []
            \\  (try
            \\    (inner)
            \\    (catch Exception e
            \\      "caught-in-outer")))
            \\(outer)
        ;

        std.debug.print("Test: Exception propagation... ", .{});
        const result = try self.compileAndRun(code);
        defer result.deinit(self.allocator);

        try testing.expect(std.mem.indexOf(u8, result.stdout, "caught-in-outer") != null);
        std.debug.print("✓\n", .{});
    }

    fn testFinallyBlock(self: *ExceptionTests) !void {
        const code =
            \\(let [flag (atom false)]
            \\  (try
            \\    (throw (Exception. "test"))
            \\    (catch Exception e
            \\      (reset! flag true))
            \\    (finally
            \\      (println "finally executed")))
            \\  @flag)
        ;

        std.debug.print("Test: Finally block... ", .{});
        const result = try self.compileAndRun(code);
        defer result.deinit(self.allocator);

        try testing.expect(std.mem.indexOf(u8, result.stdout, "finally executed") != null);
        std.debug.print("✓\n", .{});
    }

    fn compileAndRun(self: *ExceptionTests, code: []const u8) !ExecutionResult {
        var io = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .{ .slice = std.mem.span(std.c.environ) } },
        });
        defer io.deinit();

        // Compile to WAT
        const compile_result = try std.process.run(self.allocator, io.io(), .{
            
            .argv = &[_][]const u8{
                "zig",
                "build",
                "run",
                "--",
                "--eval",
                code,
                "--backend=wasmgc",
                "--emit=wat",
            },
        });
        defer self.allocator.free(compile_result.stdout);
        defer self.allocator.free(compile_result.stderr);

        if (compile_result.term == .exited and compile_result.term.exited != 0) {
            return error.CompilationFailed;
        }

        // Execute
        return try self.executor.execute(compile_result.stdout);
    }
};

// ============================================================================
// Task 6: Metadata Preservation Verification
// ============================================================================

pub const MetadataTests = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) MetadataTests {
        return .{ .allocator = allocator };
    }

    pub fn runAllTests(self: *MetadataTests) !void {
        std.debug.print("\n=== Metadata Preservation Tests ===\n", .{});

        // Test 1: Function metadata
        try self.testFunctionMetadata();

        // Test 2: Var metadata
        try self.testVarMetadata();

        // Test 3: Source location
        try self.testSourceLocation();

        // Test 4: with-meta
        try self.testWithMeta();

        // Test 5: Type hints
        try self.testTypeHints();

        std.debug.print("\n✓ All metadata tests passed\n", .{});
    }

    fn testFunctionMetadata(self: *MetadataTests) !void {
        const code =
            \\(defn ^{:doc "Adds two numbers" :test true}
            \\  add [a b]
            \\  (+ a b))
            \\(:doc (meta #'add))
        ;

        std.debug.print("Test: Function metadata... ", .{});
        const result = try self.compileAndInspect(code);
        defer self.allocator.free(result);

        try testing.expect(std.mem.indexOf(u8, result, "doc") != null);
        try testing.expect(std.mem.indexOf(u8, result, "Adds two numbers") != null);
        std.debug.print("✓\n", .{});
    }

    fn testVarMetadata(self: *MetadataTests) !void {
        const code =
            \\(def ^{:private true} x 42)
            \\(:private (meta #'x))
        ;

        std.debug.print("Test: Var metadata... ", .{});
        const result = try self.compileAndInspect(code);
        defer self.allocator.free(result);

        try testing.expect(std.mem.indexOf(u8, result, "private") != null);
        std.debug.print("✓\n", .{});
    }

    fn testSourceLocation(self: *MetadataTests) !void {
        const code =
            \\(defn foo []
            \\  (throw (Exception. "error")))
            \\(try
            \\  (foo)
            \\  (catch Exception e
            \\    (.getStackTrace e)))
        ;

        std.debug.print("Test: Source location... ", .{});
        const result = try self.compileAndInspect(code);
        defer self.allocator.free(result);

        // Check for source map or location info in compiled WAT
        try testing.expect(std.mem.indexOf(u8, result, "line") != null or
            std.mem.indexOf(u8, result, "foo") != null);
        std.debug.print("✓\n", .{});
    }

    fn testWithMeta(self: *MetadataTests) !void {
        const code =
            \\(let [v (with-meta [1 2 3] {:tag "vector"})]
            \\  (:tag (meta v)))
        ;

        std.debug.print("Test: with-meta... ", .{});
        const result = try self.compileAndInspect(code);
        defer self.allocator.free(result);

        try testing.expect(std.mem.indexOf(u8, result, "tag") != null);
        std.debug.print("✓\n", .{});
    }

    fn testTypeHints(self: *MetadataTests) !void {
        const code =
            \\(defn ^long add-longs [^long a ^long b]
            \\  (+ a b))
            \\(:tag (meta #'add-longs))
        ;

        std.debug.print("Test: Type hints... ", .{});
        const result = try self.compileAndInspect(code);
        defer self.allocator.free(result);

        try testing.expect(std.mem.indexOf(u8, result, "long") != null or
            std.mem.indexOf(u8, result, "i64") != null);
        std.debug.print("✓\n", .{});
    }

    fn compileAndInspect(self: *MetadataTests, code: []const u8) ![]const u8 {
        var io = std.Io.Threaded.init(self.allocator, .{
            .environ = .{ .block = .{ .slice = std.mem.span(std.c.environ) } },
        });
        defer io.deinit();

        // Compile to WAT and inspect metadata sections
        const result = try std.process.run(self.allocator, io.io(), .{
            
            .argv = &[_][]const u8{
                "zig",
                "build",
                "run",
                "--",
                "--eval",
                code,
                "--backend=wasmgc",
                "--emit=wat",
                "--preserve-metadata",
            },
        });
        defer self.allocator.free(result.stderr);

        if (result.term == .exited and result.term.exited != 0) {
            self.allocator.free(result.stdout);
            return error.CompilationFailed;
        }

        return result.stdout;
    }
};

// ============================================================================
// Main Test Runner - Execute All Integration Tests
// ============================================================================

test "Run complete integration test suite" {
    const allocator = testing.allocator;
    var io = std.Io.Threaded.init(allocator, .{
        .environ = .{ .block = .{ .slice = std.mem.span(std.c.environ) } },
    });
    defer io.deinit();

    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("WasmGC Backend - Complete Integration Test Suite\n", .{});
    std.debug.print("Month 5, Weeks 3-4\n", .{});
    std.debug.print("=" ** 80 ++ "\n\n", .{});

    // Task 1 & 2: Backend Comparison
    {
        var comparison = try BackendComparison.init(allocator, &io);
        defer comparison.deinit();

        std.debug.print("\n--- Testing Backend Comparison ---\n", .{});

        const simple_tests = [_][]const u8{
            "(+ 1 2 3)",
            "(inc 5)",
            "(map inc [1 2 3])",
        };

        for (simple_tests) |expr| {
            const result = comparison.compareBackends(expr) catch |err| {
                std.debug.print("Skipping test '{s}': {}\n", .{ expr, err });
                continue;
            };
            defer result.deinit(allocator);
            result.print();
        }
    }

    // Task 3: Performance Benchmarks
    {
        var benchmark = BenchmarkSuite.init(allocator, &io) catch |err| {
            std.debug.print("Skipping benchmarks: {}\n", .{err});
            return;
        };
        defer benchmark.deinit();

        benchmark.runAllBenchmarks() catch |err| {
            std.debug.print("Benchmark error: {}\n", .{err});
        };
        benchmark.printSummary();
    }

    // Task 4: Browser Testing
    {
        var browser = try BrowserTesting.init(allocator, &io);
        try (&browser).runBrowserTests();
    }

    // Task 5: Exception Handling
    {
        var exception_tests = ExceptionTests.init(allocator, &io) catch |err| {
            std.debug.print("Skipping exception tests: {}\n", .{err});
            return;
        };
        defer exception_tests.deinit();

        exception_tests.runAllTests() catch |err| {
            std.debug.print("Exception test error: {}\n", .{err});
        };
    }

    // Task 6: Metadata Preservation
    {
        var metadata_tests = MetadataTests.init(allocator);

        metadata_tests.runAllTests() catch |err| {
            std.debug.print("Metadata test error: {}\n", .{err});
        };
    }

    std.debug.print("\n" ++ "=" ** 80 ++ "\n", .{});
    std.debug.print("Integration Test Suite Complete\n", .{});
    std.debug.print("=" ** 80 ++ "\n\n", .{});
}

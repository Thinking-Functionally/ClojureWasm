// host_interop.zig - JavaScript/Host platform interop for WasmGC backend
//
// Provides:
// - JS function imports (console.log, DOM APIs, custom host functions)
// - Value ↔ JS type conversion
// - DOM manipulation proof-of-concept
// - Export functions for host environment
//
// Month 4, Week 1-2 deliverable

const std = @import("std");
const Allocator = std.mem.Allocator;

/// JavaScript type representation for interop
pub const JSType = enum {
    undefined,
    null_value,
    boolean,
    number,
    string,
    object,
    function,
    array,
};

/// JavaScript value wrapper for conversion
pub const JSValue = struct {
    js_type: JSType,
    data: union {
        boolean: bool,
        number: f64,
        string: []const u8,
        object_ref: u32, // Opaque reference to JS object
    },
};

/// WAT code generator for JS imports
pub const HostImports = struct {
    allocator: Allocator,
    imported_functions: std.ArrayList(ImportedFunction),

    pub const ImportedFunction = struct {
        module_name: []const u8, // e.g., "env", "console", "dom"
        function_name: []const u8, // e.g., "log", "alert", "querySelector"
        params: []ParamType,
        result: ?ParamType,
    };

    pub const ParamType = enum {
        i32,
        i64,
        f32,
        f64,
        externref, // For JS objects
        funcref, // For JS functions
    };

    pub fn init(allocator: Allocator) HostImports {
        return .{
            .allocator = allocator,
            .imported_functions = std.ArrayList(ImportedFunction).init(allocator),
        };
    }

    pub fn deinit(self: *HostImports) void {
        for (self.imported_functions.items) |func| {
            self.allocator.free(func.module_name);
            self.allocator.free(func.function_name);
            self.allocator.free(func.params);
        }
        self.imported_functions.deinit();
    }

    /// Add a standard console.log import
    pub fn addConsoleLog(self: *HostImports) !void {
        const params = try self.allocator.alloc(ParamType, 1);
        params[0] = .externref;

        try self.imported_functions.append(self.allocator, .{
            .module_name = try self.allocator.dupe(u8, "console"),
            .function_name = try self.allocator.dupe(u8, "log"),
            .params = params,
            .result = null,
        });
    }

    /// Add a DOM manipulation import (e.g., document.querySelector)
    pub fn addDOMQuery(self: *HostImports) !void {
        const params = try self.allocator.alloc(ParamType, 1);
        params[0] = .externref; // selector string

        try self.imported_functions.append(self.allocator, .{
            .module_name = try self.allocator.dupe(u8, "dom"),
            .function_name = try self.allocator.dupe(u8, "querySelector"),
            .params = params,
            .result = .externref, // Returns DOM element reference
        });
    }

    /// Add a custom host function import
    pub fn addCustomImport(
        self: *HostImports,
        module_name: []const u8,
        function_name: []const u8,
        params: []const ParamType,
        result: ?ParamType,
    ) !void {
        const params_copy = try self.allocator.dupe(ParamType, params);

        try self.imported_functions.append(self.allocator, .{
            .module_name = try self.allocator.dupe(u8, module_name),
            .function_name = try self.allocator.dupe(u8, function_name),
            .params = params_copy,
            .result = result,
        });
    }

    /// Generate WAT import declarations
    pub fn emitWAT(self: *const HostImports, writer: anytype) !void {
        for (self.imported_functions.items) |func| {
            try writer.writeAll("  (import \"");
            try writer.writeAll(func.module_name);
            try writer.writeAll("\" \"");
            try writer.writeAll(func.function_name);
            try writer.writeAll("\" (func $");
            try writer.writeAll(func.module_name);
            try writer.writeAll("_");
            try writer.writeAll(func.function_name);

            // Parameters
            for (func.params) |param| {
                try writer.writeAll(" (param ");
                try writer.writeAll(@tagName(param));
                try writer.writeAll(")");
            }

            // Result
            if (func.result) |result| {
                try writer.writeAll(" (result ");
                try writer.writeAll(@tagName(result));
                try writer.writeAll(")");
            }

            try writer.writeAll("))\n");
        }
    }
};

/// Value converter: Clojure Value → JS Value
pub const ValueConverter = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ValueConverter {
        return .{ .allocator = allocator };
    }

    /// Convert Clojure value to JS-compatible representation
    /// Generates WAT code for runtime conversion
    pub fn emitClojureToJS(
        self: *const ValueConverter,
        writer: anytype,
        value_tag: u8,
    ) !void {
        _ = self;

        try writer.writeAll("  ;; Clojure → JS conversion\n");
        try writer.writeAll("  (block $convert_to_js\n");
        try writer.writeAll("    (local.get $value_tag)\n");

        // Switch on type tag
        try writer.writeAll("    (block $case_nil\n");
        try writer.writeAll("    (block $case_boolean\n");
        try writer.writeAll("    (block $case_long\n");
        try writer.writeAll("    (block $case_double\n");
        try writer.writeAll("    (block $case_string\n");
        try writer.writeAll("      (br_table $case_nil $case_boolean $case_long $case_double $case_string)\n");
        try writer.writeAll("    )\n"); // case_string

        // String: extract bytes, convert to JS string
        try writer.writeAll("      ;; String → JS string (externref)\n");
        try writer.writeAll("      (local.get $value_data)\n");
        try writer.writeAll("      (struct.get $String $bytes)\n");
        try writer.writeAll("      (call $host_string_from_utf8)\n");
        try writer.writeAll("      (br $convert_to_js)\n");

        try writer.writeAll("    )\n"); // case_double
        try writer.writeAll("      ;; Double → JS number\n");
        try writer.writeAll("      (local.get $value_data)\n");
        try writer.writeAll("      (struct.get $Double $value)\n");
        try writer.writeAll("      (br $convert_to_js)\n");

        try writer.writeAll("    )\n"); // case_long
        try writer.writeAll("      ;; Long → JS number (with precision loss warning)\n");
        try writer.writeAll("      (local.get $value_data)\n");
        try writer.writeAll("      (struct.get $Long $value)\n");
        try writer.writeAll("      (f64.convert_i64_s)\n");
        try writer.writeAll("      (br $convert_to_js)\n");

        try writer.writeAll("    )\n"); // case_boolean
        try writer.writeAll("      ;; Boolean → JS boolean\n");
        try writer.writeAll("      (local.get $value_data)\n");
        try writer.writeAll("      (struct.get $Boolean $value)\n");
        try writer.writeAll("      (br $convert_to_js)\n");

        try writer.writeAll("    )\n"); // case_nil
        try writer.writeAll("      ;; nil → JS null\n");
        try writer.writeAll("      (ref.null extern)\n");

        try writer.writeAll("  )\n"); // convert_to_js
        _ = value_tag; // Suppress unused warning
    }

    /// Convert JS value to Clojure Value
    /// Generates WAT code for runtime conversion
    pub fn emitJSToClojure(
        self: *const ValueConverter,
        writer: anytype,
    ) !void {
        _ = self;

        try writer.writeAll("  ;; JS → Clojure conversion\n");
        try writer.writeAll("  (func $js_to_clojure (param $js_val externref) (result (ref $Value))\n");
        try writer.writeAll("    ;; Check JS type (via host function)\n");
        try writer.writeAll("    (local $js_type i32)\n");
        try writer.writeAll("    (local.set $js_type (call $host_typeof (local.get $js_val)))\n");
        try writer.writeAll("\n");

        try writer.writeAll("    ;; Switch on JS type\n");
        try writer.writeAll("    (block $js_null\n");
        try writer.writeAll("    (block $js_boolean\n");
        try writer.writeAll("    (block $js_number\n");
        try writer.writeAll("    (block $js_string\n");
        try writer.writeAll("      (local.get $js_type)\n");
        try writer.writeAll("      (br_table $js_null $js_boolean $js_number $js_string)\n");
        try writer.writeAll("    )\n"); // js_string

        try writer.writeAll("      ;; JS string → Clojure string\n");
        try writer.writeAll("      (return (call $make_string_from_js (local.get $js_val)))\n");

        try writer.writeAll("    )\n"); // js_number
        try writer.writeAll("      ;; JS number → Clojure double\n");
        try writer.writeAll("      (return (call $make_double\n");
        try writer.writeAll("        (call $host_number_value (local.get $js_val))))\n");

        try writer.writeAll("    )\n"); // js_boolean
        try writer.writeAll("      ;; JS boolean → Clojure boolean\n");
        try writer.writeAll("      (return (call $make_boolean\n");
        try writer.writeAll("        (call $host_boolean_value (local.get $js_val))))\n");

        try writer.writeAll("    )\n"); // js_null
        try writer.writeAll("      ;; JS null/undefined → Clojure nil\n");
        try writer.writeAll("      (return (global.get $nil))\n");

        try writer.writeAll("  )\n"); // js_to_clojure
    }
};

/// DOM manipulation helpers
pub const DOMHelpers = struct {
    /// Generate WAT code for a basic DOM manipulation example
    pub fn emitDOMExample(writer: anytype) !void {
        try writer.writeAll("\n  ;; DOM Manipulation Proof-of-Concept\n");
        try writer.writeAll("  ;; Example: (dom-set-text \"#app\" \"Hello from ClojureWasm!\")\n");
        try writer.writeAll("  (func $dom_set_text (export \"dom_set_text\")\n");
        try writer.writeAll("    (param $selector (ref $Value)) (param $text (ref $Value))\n");
        try writer.writeAll("    (result (ref $Value))\n");
        try writer.writeAll("\n");

        try writer.writeAll("    ;; Convert selector to JS string\n");
        try writer.writeAll("    (local $js_selector externref)\n");
        try writer.writeAll("    (local.set $js_selector\n");
        try writer.writeAll("      (call $clojure_string_to_js (local.get $selector)))\n");
        try writer.writeAll("\n");

        try writer.writeAll("    ;; Query DOM element\n");
        try writer.writeAll("    (local $element externref)\n");
        try writer.writeAll("    (local.set $element\n");
        try writer.writeAll("      (call $dom_querySelector (local.get $js_selector)))\n");
        try writer.writeAll("\n");

        try writer.writeAll("    ;; Convert text to JS string\n");
        try writer.writeAll("    (local $js_text externref)\n");
        try writer.writeAll("    (local.set $js_text\n");
        try writer.writeAll("      (call $clojure_string_to_js (local.get $text)))\n");
        try writer.writeAll("\n");

        try writer.writeAll("    ;; Set element textContent\n");
        try writer.writeAll("    (call $dom_setTextContent\n");
        try writer.writeAll("      (local.get $element)\n");
        try writer.writeAll("      (local.get $js_text))\n");
        try writer.writeAll("\n");

        try writer.writeAll("    ;; Return nil\n");
        try writer.writeAll("    (global.get $nil)\n");
        try writer.writeAll("  )\n");
    }

    /// Generate host function imports needed for DOM operations
    pub fn addDOMImports(host_imports: *HostImports) !void {
        // querySelector
        try host_imports.addCustomImport(
            "dom",
            "querySelector",
            &[_]HostImports.ParamType{.externref},
            .externref,
        );

        // setTextContent
        try host_imports.addCustomImport(
            "dom",
            "setTextContent",
            &[_]HostImports.ParamType{ .externref, .externref },
            null,
        );

        // addEventListener
        try host_imports.addCustomImport(
            "dom",
            "addEventListener",
            &[_]HostImports.ParamType{ .externref, .externref, .funcref },
            null,
        );
    }
};

/// Export configuration for host environment
pub const ExportConfig = struct {
    allocator: Allocator,
    exported_functions: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator) ExportConfig {
        return .{
            .allocator = allocator,
            .exported_functions = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ExportConfig) void {
        for (self.exported_functions.items) |name| {
            self.allocator.free(name);
        }
        self.exported_functions.deinit();
    }

    /// Mark a function for export to host environment
    pub fn addExport(self: *ExportConfig, function_name: []const u8) !void {
        try self.exported_functions.append(self.allocator, try self.allocator.dupe(u8, function_name));
    }

    /// Generate WAT export declarations
    pub fn emitWAT(self: *const ExportConfig, writer: anytype) !void {
        for (self.exported_functions.items) |name| {
            try writer.print("  (export \"{s}\" (func ${s}))\n", .{ name, name });
        }
    }
};

// Helper types for host function signatures
pub const HostFunction = struct {
    name: []const u8,
    params: []const HostImports.ParamType,
    result: ?HostImports.ParamType,
};

/// Standard host function library
pub const stdlib = struct {
    /// Standard host functions needed for interop
    pub const host_functions = [_]HostFunction{
        .{ .name = "typeof", .params = &[_]HostImports.ParamType{.externref}, .result = .i32 },
        .{ .name = "string_from_utf8", .params = &[_]HostImports.ParamType{.externref}, .result = .externref },
        .{ .name = "number_value", .params = &[_]HostImports.ParamType{.externref}, .result = .f64 },
        .{ .name = "boolean_value", .params = &[_]HostImports.ParamType{.externref}, .result = .i32 },
    };
};

test "HostImports basic" {
    const testing = std.testing;
    var host_imports = HostImports.init(testing.allocator);
    defer host_imports.deinit();

    try host_imports.addConsoleLog();
    try testing.expectEqual(@as(usize, 1), host_imports.imported_functions.items.len);
}

test "ValueConverter" {
    const testing = std.testing;
    const converter = ValueConverter.init(testing.allocator);

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try converter.emitClojureToJS(buffer.writer(), 0);
    try testing.expect(buffer.items.len > 0);
}

// ============================================================================
// Exception Handling Support
// ============================================================================

/// Exception tag definitions for Clojure exceptions
pub const ExceptionTags = struct {
    allocator: Allocator,
    tags: std.ArrayList(ExceptionTag),

    pub const ExceptionTag = struct {
        name: []const u8,
        param_types: []const ParamType,
    };

    pub const ParamType = enum {
        i32,
        i64,
        f32,
        f64,
        externref,
        funcref,

        pub fn toWAT(self: ParamType) []const u8 {
            return switch (self) {
                .i32 => "i32",
                .i64 => "i64",
                .f32 => "f32",
                .f64 => "f64",
                .externref => "externref",
                .funcref => "funcref",
            };
        }
    };

    pub fn init(allocator: Allocator) ExceptionTags {
        return .{
            .allocator = allocator,
            .tags = std.ArrayList(ExceptionTag).init(allocator),
        };
    }

    pub fn deinit(self: *ExceptionTags) void {
        self.tags.deinit();
    }

    /// Add standard Clojure exception tag
    pub fn addExceptionTag(self: *ExceptionTags, name: []const u8, param_types: []const ParamType) !void {
        try self.tags.append(.{
            .name = name,
            .param_types = param_types,
        });
    }

    /// Emit all exception tags as WAT
    pub fn emit(self: *const ExceptionTags, writer: anytype) !void {
        try writer.writeAll(";; Exception Tags\n");

        for (self.tags.items) |tag| {
            try writer.writeAll("(tag $");
            try writer.writeAll(tag.name);

            if (tag.param_types.len > 0) {
                try writer.writeAll(" (param");
                for (tag.param_types) |param_type| {
                    try writer.writeAll(" ");
                    try writer.writeAll(param_type.toWAT());
                }
                try writer.writeAll(")");
            }

            try writer.writeAll(")\n");
        }
        try writer.writeAll("\n");
    }

    /// Add standard Clojure exception tags
    pub fn addStandardTags(self: *ExceptionTags) !void {
        // Generic exception with Value payload
        try self.addExceptionTag("clojure_exception", &[_]ParamType{.externref});

        // Specific exception types
        try self.addExceptionTag("arity_exception", &[_]ParamType{.i32}); // expected arity
        try self.addExceptionTag("null_pointer_exception", &[_]ParamType{});
        try self.addExceptionTag("index_out_of_bounds", &[_]ParamType{ .i32, .i32 }); // index, size
        try self.addExceptionTag("illegal_argument", &[_]ParamType{.externref}); // message
        try self.addExceptionTag("illegal_state", &[_]ParamType{.externref}); // message
    }
};

/// Exception handler code generation
pub const ExceptionHandlers = struct {
    /// Emit try-catch wrapper for a function call
    pub fn emitTryCatch(
        writer: anytype,
        try_body: []const u8,
        catch_tag: []const u8,
        catch_body: []const u8,
    ) !void {
        try writer.writeAll("  (try (result (ref $Value))\n");
        try writer.writeAll("    (do\n");
        try writer.writeAll("      ");
        try writer.writeAll(try_body);
        try writer.writeAll("\n    )\n");
        try writer.writeAll("    (catch $");
        try writer.writeAll(catch_tag);
        try writer.writeAll("\n");
        try writer.writeAll("      ");
        try writer.writeAll(catch_body);
        try writer.writeAll("\n    )\n");
        try writer.writeAll("  )\n");
    }

    /// Emit throw instruction
    pub fn emitThrow(
        writer: anytype,
        tag_name: []const u8,
        args: []const []const u8,
    ) !void {
        try writer.writeAll("  (throw $");
        try writer.writeAll(tag_name);
        for (args) |arg| {
            try writer.writeAll(" ");
            try writer.writeAll(arg);
        }
        try writer.writeAll(")\n");
    }

    /// Emit exception value constructor
    pub fn emitMakeException(writer: anytype, message: []const u8) !void {
        try writer.writeAll("(func $make_exception (param $msg (ref $String)) (result (ref $Value))\n");
        try writer.writeAll("  ;; Create exception map with :message key\n");
        try writer.writeAll("  (local $map (ref $Map))\n");
        try writer.writeAll("  (local.set $map (call $rt_make_map_empty))\n");
        try writer.writeAll("  \n");
        try writer.writeAll("  ;; Add :message key\n");
        try writer.writeAll("  (local $msg_key (ref $Value))\n");
        try writer.writeAll("  (local.set $msg_key (call $rt_make_keyword\n");
        try writer.writeAll("    (ref.null $String)\n");
        try writer.writeAll("    (call $rt_make_string_from_cstr \"message\")))\n");
        try writer.writeAll("  \n");
        try writer.writeAll("  (call $rt_map_assoc\n");
        try writer.writeAll("    (struct.new $Value (i32.const 9) (local.get $map))  ;; TAG_MAP\n");
        try writer.writeAll("    (local.get $msg_key)\n");
        try writer.writeAll("    (struct.new $Value (i32.const 1) (local.get $msg)))  ;; TAG_STRING\n");
        try writer.writeAll("  )\n");
        try writer.writeAll(")\n\n");
    }
};

// ============================================================================
// Metadata Support
// ============================================================================

/// Metadata manager for Clojure values
pub const MetadataSupport = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) MetadataSupport {
        return .{ .allocator = allocator };
    }

    /// Emit metadata type definition
    pub fn emitMetadataType(writer: anytype) !void {
        try writer.writeAll(";; Metadata Type\n");
        try writer.writeAll("(type $Metadata (struct\n");
        try writer.writeAll("  (field $data (ref $Map))        ;; Metadata map\n");
        try writer.writeAll("  (field $line (mut i32))         ;; Source line number\n");
        try writer.writeAll("  (field $column (mut i32))       ;; Source column number\n");
        try writer.writeAll("  (field $file (ref null $String)) ;; Source file name\n");
        try writer.writeAll("))\n\n");
    }

    /// Emit metadata constructor
    pub fn emitMetadataConstructor(writer: anytype) !void {
        try writer.writeAll("(func $make_metadata (param $map (ref $Map)) (result (ref $Metadata))\n");
        try writer.writeAll("  (struct.new $Metadata\n");
        try writer.writeAll("    (local.get $map)\n");
        try writer.writeAll("    (i32.const 0)  ;; line\n");
        try writer.writeAll("    (i32.const 0)  ;; column\n");
        try writer.writeAll("    (ref.null $String)  ;; file\n");
        try writer.writeAll("  )\n");
        try writer.writeAll(")\n\n");

        try writer.writeAll("(func $make_metadata_with_location\n");
        try writer.writeAll("    (param $map (ref $Map))\n");
        try writer.writeAll("    (param $file (ref null $String))\n");
        try writer.writeAll("    (param $line i32)\n");
        try writer.writeAll("    (param $column i32)\n");
        try writer.writeAll("    (result (ref $Metadata))\n");
        try writer.writeAll("  (struct.new $Metadata\n");
        try writer.writeAll("    (local.get $map)\n");
        try writer.writeAll("    (local.get $line)\n");
        try writer.writeAll("    (local.get $column)\n");
        try writer.writeAll("    (local.get $file)\n");
        try writer.writeAll("  )\n");
        try writer.writeAll(")\n\n");
    }

    /// Emit metadata accessor functions
    pub fn emitMetadataAccessors(writer: anytype) !void {
        // Get metadata from value
        try writer.writeAll("(func $get_meta (param $value (ref $Value)) (result (ref null $Metadata))\n");
        try writer.writeAll("  ;; Return metadata attached to value (if any)\n");
        try writer.writeAll("  ;; For now, return null - metadata will be stored in extended Value type\n");
        try writer.writeAll("  (ref.null $Metadata)\n");
        try writer.writeAll(")\n\n");

        // Get metadata value from map
        try writer.writeAll("(func $meta_get (param $meta (ref $Metadata)) (param $key (ref $Value)) (result (ref $Value))\n");
        try writer.writeAll("  (call $rt_map_get\n");
        try writer.writeAll("    (struct.new $Value\n");
        try writer.writeAll("      (i32.const 9)  ;; TAG_MAP\n");
        try writer.writeAll("      (struct.get $Metadata $data (local.get $meta)))\n");
        try writer.writeAll("    (local.get $key))\n");
        try writer.writeAll(")\n\n");

        // Get source location
        try writer.writeAll("(func $meta_get_line (param $meta (ref $Metadata)) (result i32)\n");
        try writer.writeAll("  (struct.get $Metadata $line (local.get $meta))\n");
        try writer.writeAll(")\n\n");

        try writer.writeAll("(func $meta_get_column (param $meta (ref $Metadata)) (result i32)\n");
        try writer.writeAll("  (struct.get $Metadata $column (local.get $meta))\n");
        try writer.writeAll(")\n\n");

        try writer.writeAll("(func $meta_get_file (param $meta (ref $Metadata)) (result (ref null $String))\n");
        try writer.writeAll("  (struct.get $Metadata $file (local.get $meta))\n");
        try writer.writeAll(")\n\n");
    }

    /// Emit with-meta function
    pub fn emitWithMeta(writer: anytype) !void {
        try writer.writeAll("(func $with_meta\n");
        try writer.writeAll("    (param $value (ref $Value))\n");
        try writer.writeAll("    (param $meta_map (ref $Value))\n");
        try writer.writeAll("    (result (ref $Value))\n");
        try writer.writeAll("  ;; TODO: Implement metadata attachment to values\n");
        try writer.writeAll("  ;; Requires extended Value type with metadata field\n");
        try writer.writeAll("  ;; For now, return value unchanged\n");
        try writer.writeAll("  (local.get $value)\n");
        try writer.writeAll(")\n\n");
    }

    /// Emit all metadata support functions
    pub fn emitAll(self: *const MetadataSupport, writer: anytype) !void {
        _ = self;
        try writer.writeAll(";; =============================================================================\n");
        try writer.writeAll(";; Metadata Support\n");
        try writer.writeAll(";; =============================================================================\n\n");

        try emitMetadataType(writer);
        try emitMetadataConstructor(writer);
        try emitMetadataAccessors(writer);
        try emitWithMeta(writer);
    }
};

// ============================================================================
// Integration Tests
// ============================================================================

test "ExceptionTags" {
    const testing = std.testing;
    var tags = ExceptionTags.init(testing.allocator);
    defer tags.deinit();

    try tags.addStandardTags();
    try testing.expectEqual(@as(usize, 5), tags.tags.items.len);

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try tags.emit(buffer.writer());
    try testing.expect(buffer.items.len > 0);
}

test "MetadataSupport" {
    const testing = std.testing;
    const meta = MetadataSupport.init(testing.allocator);

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try meta.emitAll(buffer.writer());
    try testing.expect(buffer.items.len > 0);
}


const std = @import("std");

// WASM bytecode generation from IR
// Reference: https://webassembly.github.io/spec/core/binary/index.html

pub const WasmError = error{
    InvalidIR,
    UnsupportedOperation,
    OutOfMemory,
};

// WASM value types
pub const ValType = enum(u8) {
    i32 = 0x7F,
    i64 = 0x7E,
    f32 = 0x7D,
    f64 = 0x7C,
};

// WASM opcodes
pub const Opcode = enum(u8) {
    // Control flow
    unreachable_op = 0x00,
    nop = 0x01,
    block = 0x02,
    loop = 0x03,
    if_op = 0x04,
    else_op = 0x05,
    end = 0x0B,
    br = 0x0C,
    br_if = 0x0D,
    return_op = 0x0F,
    call = 0x10,

    // Parametric
    drop = 0x1A,
    select = 0x1B,

    // Variable access
    local_get = 0x20,
    local_set = 0x21,
    local_tee = 0x22,

    // Numeric (f64)
    f64_const = 0x44,
    f64_eq = 0x61,
    f64_ne = 0x62,
    f64_lt = 0x63,
    f64_gt = 0x64,
    f64_le = 0x65,
    f64_ge = 0x66,
    f64_abs = 0x99,
    f64_neg = 0x9A,
    f64_add = 0xA0,
    f64_sub = 0xA1,
    f64_mul = 0xA2,
    f64_div = 0xA3,

    // Conversion
    i32_eqz = 0x45,
    i32_trunc_f64_s = 0xAA,
    f64_convert_i32_s = 0xB7,
};

pub const WasmModule = struct {
    allocator: std.mem.Allocator,
    code: std.ArrayList(u8),
    num_params: u32,
    num_locals: u32,

    pub fn init(allocator: std.mem.Allocator) WasmModule {
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).empty,
            .num_params = 0,
            .num_locals = 0,
        };
    }

    pub fn deinit(self: *WasmModule) void {
        self.code.deinit(self.allocator);
    }

    /// Write WASM module to bytes
    pub fn toBytes(self: *WasmModule) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);

        // WASM magic number: 0x00 0x61 0x73 0x6D
        try result.append(self.allocator, 0x00);
        try result.append(self.allocator, 0x61);
        try result.append(self.allocator, 0x73);
        try result.append(self.allocator, 0x6D);

        // WASM version: 1
        try result.append(self.allocator, 0x01);
        try result.append(self.allocator, 0x00);
        try result.append(self.allocator, 0x00);
        try result.append(self.allocator, 0x00);

        // Type section (function signatures)
        try result.append(self.allocator, 0x01); // Section ID: Type
        const type_section_start = result.items.len;
        try result.append(self.allocator, 0x00); // Placeholder for section size

        try self.writeTypeSection(&result);

        // Update type section size
        const type_section_size = result.items.len - type_section_start - 1;
        result.items[type_section_start] = @intCast(type_section_size);

        // Function section
        try result.append(self.allocator, 0x03); // Section ID: Function
        const func_section_start = result.items.len;
        try result.append(self.allocator, 0x00); // Placeholder for section size

        try self.writeFunctionSection(&result);

        const func_section_size = result.items.len - func_section_start - 1;
        result.items[func_section_start] = @intCast(func_section_size);

        // Export section
        try result.append(self.allocator, 0x07); // Section ID: Export
        const export_section_start = result.items.len;
        try result.append(self.allocator, 0x00); // Placeholder

        try self.writeExportSection(&result);

        const export_section_size = result.items.len - export_section_start - 1;
        result.items[export_section_start] = @intCast(export_section_size);

        // Code section (function bodies)
        try result.append(self.allocator, 0x0A); // Section ID: Code
        const code_section_start = result.items.len;
        try result.append(self.allocator, 0x00); // Placeholder

        try self.writeCodeSection(&result);

        const code_section_size = result.items.len - code_section_start - 1;
        result.items[code_section_start] = @intCast(code_section_size);

        return result.toOwnedSlice(self.allocator);
    }

    fn writeTypeSection(self: *WasmModule, buf: *std.ArrayList(u8)) !void {
        // Number of types
        try buf.append(self.allocator, 0x01); // 1 type

        // Type 0: (params...) -> f64
        try buf.append(self.allocator, 0x60); // func type
        try buf.append(self.allocator, @intCast(self.num_params)); // param count
        // Write each param type
        var i: u32 = 0;
        while (i < self.num_params) : (i += 1) {
            try buf.append(self.allocator, @intFromEnum(ValType.f64));
        }
        try buf.append(self.allocator, 0x01); // 1 result
        try buf.append(self.allocator, @intFromEnum(ValType.f64));
    }

    fn writeFunctionSection(self: *WasmModule, buf: *std.ArrayList(u8)) !void {
        // Number of functions
        try buf.append(self.allocator, 0x01); // 1 function

        // Function 0 uses type 0
        try buf.append(self.allocator, 0x00);
    }

    fn writeExportSection(self: *WasmModule, buf: *std.ArrayList(u8)) !void {
        // Number of exports
        try buf.append(self.allocator, 0x01); // 1 export

        // Export name: "main"
        try buf.append(self.allocator, 0x04); // name length
        try buf.appendSlice(self.allocator, "main");

        // Export kind: function
        try buf.append(self.allocator, 0x00);

        // Export index: function 0
        try buf.append(self.allocator, 0x00);
    }

    fn writeCodeSection(self: *WasmModule, buf: *std.ArrayList(u8)) !void {
        // Number of function bodies
        try buf.append(self.allocator, 0x01); // 1 function

        // Function body
        const body_start = buf.items.len;
        try buf.append(self.allocator, 0x00); // Placeholder for body size

        // Locals declaration (number of local groups)
        if (self.num_locals > 0) {
            try buf.append(self.allocator, 0x01); // 1 local group
            try self.emitU32ToBuffer(buf, self.num_locals); // count
            try buf.append(self.allocator, @intFromEnum(ValType.f64)); // type
        } else {
            try buf.append(self.allocator, 0x00); // no locals
        }

        // Function body code
        try buf.appendSlice(self.allocator, self.code.items);

        // End of function
        try buf.append(self.allocator, @intFromEnum(Opcode.end));

        // Update body size
        const body_size = buf.items.len - body_start - 1;
        buf.items[body_start] = @intCast(body_size);
    }

    /// Emit an opcode
    pub fn emit(self: *WasmModule, op: Opcode) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
    }

    /// Emit a raw byte
    pub fn emitU8(self: *WasmModule, byte: u8) !void {
        try self.code.append(self.allocator, byte);
    }

    /// Emit f64 constant
    pub fn emitF64Const(self: *WasmModule, value: f64) !void {
        try self.emit(.f64_const);
        const bytes = std.mem.toBytes(value);
        try self.code.appendSlice(self.allocator, &bytes);
    }

    /// Emit local.get (access parameter or local)
    pub fn emitLocalGet(self: *WasmModule, index: u32) !void {
        try self.emit(.local_get);
        try self.emitU32(index);
    }

    /// Emit local.set
    pub fn emitLocalSet(self: *WasmModule, index: u32) !void {
        try self.emit(.local_set);
        try self.emitU32(index);
    }

    /// Emit call (function call)
    pub fn emitCall(self: *WasmModule, func_index: u32) !void {
        try self.emit(.call);
        try self.emitU32(func_index);
    }

    /// Emit unsigned LEB128
    fn emitU32(self: *WasmModule, value: u32) !void {
        var v = value;
        while (true) {
            var byte: u8 = @intCast(v & 0x7F);
            v >>= 7;
            if (v != 0) {
                byte |= 0x80;
            }
            try self.code.append(self.allocator, byte);
            if (v == 0) break;
        }
    }

    /// Emit unsigned LEB128 to external buffer
    fn emitU32ToBuffer(self: *WasmModule, buf: *std.ArrayList(u8), value: u32) !void {
        var v = value;
        while (true) {
            var byte: u8 = @intCast(v & 0x7F);
            v >>= 7;
            if (v != 0) {
                byte |= 0x80;
            }
            try buf.append(self.allocator, byte);
            if (v == 0) break;
        }
    }
};

// SPDX-License-Identifier: EPL-2.0
//! Wasm Control Flow Translator
//!
//! 將 VM 嘅非結構化跳轉 (op_jump, op_jump_if_false, op_recur) 翻譯成
//! Wasm 嘅結構化控制流 (block, loop, if, br, br_if)。
//!
//! 策略：兩遍掃描
//! 1. 第一遍：掃描所有跳轉目標，建立 IP → block label 映射
//! 2. 第二遍：生成 Wasm 代碼，在跳轉目標處插入 block

const std = @import("std");
const opcode_mod = @import("../vm/opcode.zig");

const BytecodeChunk = opcode_mod.BytecodeChunk;
const Instruction = opcode_mod.Instruction;
const Opcode = opcode_mod.Opcode;

pub const ControlFlowError = error{
    InvalidJumpTarget,
    TooManyBlocks,
    UnmatchedBlock,
} || std.mem.Allocator.Error;

/// 控制流分析結果
pub const ControlFlowAnalysis = struct {
    /// IP → block depth 映射
    jump_targets: std.AutoHashMap(usize, u32),

    /// 循環起點 (recur 目標)
    loop_starts: std.AutoHashMap(usize, u32),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ControlFlowAnalysis {
        return .{
            .jump_targets = std.AutoHashMap(usize, u32).init(allocator),
            .loop_starts = std.AutoHashMap(usize, u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ControlFlowAnalysis) void {
        self.jump_targets.deinit();
        self.loop_starts.deinit();
    }

    /// 第一遍：掃描 bytecode，建立跳轉目標映射
    pub fn analyze(self: *ControlFlowAnalysis, chunk: BytecodeChunk) ControlFlowError!void {
        for (chunk.instructions, 0..) |instr, ip| {
            switch (instr.opcode) {
                // 無條件跳轉：記錄目標 IP
                .op_jump => {
                    const target = try self.computeJumpTarget(ip, instr.operand);
                    try self.jump_targets.put(target, 0); // label 稍後分配
                },

                // 條件跳轉：記錄目標 IP
                .op_jump_if_false => {
                    const target = try self.computeJumpTarget(ip, instr.operand);
                    try self.jump_targets.put(target, 0);
                },

                // 尾遞迴：記錄循環起點
                // VM compiler 嘅 recur 係跳到最近嘅 loop binding 起點
                // 我哋需要揾出 loop 嘅開始位置
                .op_recur => {
                    // recur operand = arg count
                    // 我哋需要向後掃描揾 loop 開始
                    // 簡化實現：假設 recur 跳到函數開始 (IP 0)
                    // TODO: 正確實現需要追蹤 loop binding scope
                    try self.loop_starts.put(0, 0);
                },

                else => {},
            }
        }
    }

    pub fn computeJumpTarget(self: *ControlFlowAnalysis, ip: usize, operand: u16) ControlFlowError!usize {
        _ = self;
        const offset: i16 = @bitCast(operand);
        if (offset >= 0) {
            return ip + @as(usize, @intCast(offset));
        } else {
            const abs_offset: usize = @intCast(-offset);
            if (abs_offset > ip) {
                return ControlFlowError.InvalidJumpTarget;
            }
            return ip - abs_offset;
        }
    }
};

/// Block 種類
pub const BlockKind = enum {
    block, // 普通 block (用於 forward jump)
    loop, // loop (用於 recur)
    if_then, // if 嘅 then 分支
    if_else, // if 嘅 else 分支
};

/// Block 信息
pub const BlockInfo = struct {
    kind: BlockKind,
    label: u32,
    start_ip: usize,
};

/// Block 棧：追蹤當前嘅 Wasm block 深度
pub const BlockStack = struct {
    stack: std.ArrayList(BlockInfo),
    allocator: std.mem.Allocator,
    next_label: u32,

    pub fn init(allocator: std.mem.Allocator) BlockStack {
        return .{
            .stack = .empty,
            .allocator = allocator,
            .next_label = 0,
        };
    }

    pub fn deinit(self: *BlockStack) void {
        self.stack.deinit(self.allocator);
    }

    pub fn push(self: *BlockStack, kind: BlockKind, start_ip: usize) !u32 {
        const label = self.next_label;
        self.next_label += 1;
        try self.stack.append(self.allocator, .{
            .kind = kind,
            .label = label,
            .start_ip = start_ip,
        });
        return label;
    }

    pub fn pop(self: *BlockStack) ?BlockInfo {
        if (self.stack.items.len == 0) return null;
        return self.stack.pop();
    }

    pub fn depth(self: *BlockStack) u32 {
        return @intCast(self.stack.items.len);
    }

    /// 計算跳轉深度：從當前深度到目標 label 嘅距離
    pub fn computeBranchDepth(self: *BlockStack, target_label: u32) ?u32 {
        var i: usize = self.stack.items.len;
        while (i > 0) {
            i -= 1;
            if (self.stack.items[i].label == target_label) {
                const current_depth = self.stack.items.len;
                const target_depth = i + 1;
                return @intCast(current_depth - target_depth);
            }
        }
        return null;
    }

    /// 揾最近嘅 loop block (用於 recur)
    pub fn findNearestLoop(self: *BlockStack) ?u32 {
        var i: usize = self.stack.items.len;
        while (i > 0) {
            i -= 1;
            if (self.stack.items[i].kind == .loop) {
                return self.stack.items[i].label;
            }
        }
        return null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ControlFlowAnalysis: scan forward jump" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 構造簡單嘅 jump: IP 0 → IP 5
    var instructions: std.ArrayList(opcode_mod.WireInstr) = .empty;
    defer instructions.deinit(allocator);

    // IP 0: jump +5
    try instructions.append(allocator, .{ .opcode = .op_jump, .operand = 5 });
    // IP 1-4: nop
    try instructions.append(allocator, .{ .opcode = .op_pop, .operand = 0 });
    try instructions.append(allocator, .{ .opcode = .op_pop, .operand = 0 });
    try instructions.append(allocator, .{ .opcode = .op_pop, .operand = 0 });
    try instructions.append(allocator, .{ .opcode = .op_pop, .operand = 0 });
    // IP 5: target
    try instructions.append(allocator, .{ .opcode = .op_ret, .operand = 0 });

    const chunk = BytecodeChunk{
        .instructions = try instructions.toOwnedSlice(allocator),
        .constants = &[_]@import("../../../runtime/value/value.zig").Value{},
        .call_sites = &[_]opcode_mod.CallSiteEntry{},
        .libspecs = &[_]opcode_mod.LibspecEntry{},
        .ns_filters = &[_]opcode_mod.NsFilterEntry{},
        .ctor_sites = &[_]opcode_mod.CtorEntry{},
        .import_sites = &[_]opcode_mod.ImportPair{},
        .source_file = "",
    };
    defer allocator.free(chunk.instructions);

    var analysis = ControlFlowAnalysis.init(allocator);
    defer analysis.deinit();

    try analysis.analyze(chunk);

    // 驗證 IP 5 被記錄為跳轉目標
    try testing.expect(analysis.jump_targets.contains(5));
}

test "BlockStack: push/pop blocks" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = BlockStack.init(allocator);
    defer stack.deinit();

    // Push 一個 block
    const label1 = try stack.push(.block, 0);
    try testing.expectEqual(@as(u32, 0), label1);
    try testing.expectEqual(@as(u32, 1), stack.depth());

    // Push 另一個 block
    const label2 = try stack.push(.loop, 5);
    try testing.expectEqual(@as(u32, 1), label2);
    try testing.expectEqual(@as(u32, 2), stack.depth());

    // Pop
    const info2 = stack.pop();
    try testing.expect(info2 != null);
    try testing.expectEqual(BlockKind.loop, info2.?.kind);
    try testing.expectEqual(@as(u32, 1), info2.?.label);

    const info1 = stack.pop();
    try testing.expect(info1 != null);
    try testing.expectEqual(BlockKind.block, info1.?.kind);
}

test "BlockStack: computeBranchDepth" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = BlockStack.init(allocator);
    defer stack.deinit();

    const l0 = try stack.push(.block, 0); // depth 0
    const l1 = try stack.push(.block, 1); // depth 1
    const l2 = try stack.push(.loop, 2); // depth 2

    // 從 depth 2 跳到 l0 (depth 0): br 深度 = 2
    const d0 = stack.computeBranchDepth(l0);
    try testing.expectEqual(@as(u32, 2), d0.?);

    // 從 depth 2 跳到 l1 (depth 1): br 深度 = 1
    const d1 = stack.computeBranchDepth(l1);
    try testing.expectEqual(@as(u32, 1), d1.?);

    // 從 depth 2 跳到 l2 (depth 2): br 深度 = 0
    const d2 = stack.computeBranchDepth(l2);
    try testing.expectEqual(@as(u32, 0), d2.?);
}

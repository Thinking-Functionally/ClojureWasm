// SPDX-License-Identifier: EPL-2.0
//! EDN subset parser for ClojureWasm IR - Zig 0.16/0.17 compatible version

const std = @import("std");

pub const EDNValue = union(enum) {
    nil,
    boolean: bool,
    number: f64,
    string: []const u8,
    keyword: []const u8,
    vector: []EDNValue,
    map: std.StringHashMap(EDNValue),

    pub fn deinit(self: *EDNValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .keyword => |k| allocator.free(k),
            .vector => |v| {
                for (v) |*item| {
                    item.deinit(allocator);
                }
                allocator.free(v);
            },
            .map => |*m| {
                var it = m.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                m.deinit();
            },
            else => {},
        }
    }
};

pub const ParseError = error{
    UnexpectedChar,
    UnexpectedEOF,
    InvalidNumber,
    InvalidKeyword,
    InvalidString,
    UnclosedVector,
    UnclosedMap,
    OutOfMemory,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return .{
            .allocator = allocator,
            .source = source,
            .pos = 0,
        };
    }

    pub fn parseValue(self: *Parser) ParseError!EDNValue {
        self.skipWhitespace();

        if (self.isEOF()) {
            return ParseError.UnexpectedEOF;
        }

        const ch = self.peek();
        return switch (ch) {
            '{' => try self.parseMap(),
            '[' => try self.parseVector(),
            ':' => try self.parseKeyword(),
            '"' => try self.parseString(),
            't', 'f' => try self.parseBoolean(),
            'n' => try self.parseNil(),
            '-', '0'...'9' => try self.parseNumber(),
            else => ParseError.UnexpectedChar,
        };
    }

    fn parseMap(self: *Parser) ParseError!EDNValue {
        self.consume(); // '{'
        self.skipWhitespace();

        var map = std.StringHashMap(EDNValue).init(self.allocator);
        errdefer {
            var it = map.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            map.deinit();
        }

        while (!self.isEOF() and self.peek() != '}') {
            const key_val = try self.parseValue();
            if (key_val != .keyword) {
                return ParseError.UnexpectedChar;
            }
            const key = key_val.keyword;

            self.skipWhitespace();

            var value = try self.parseValue();
            errdefer value.deinit(self.allocator);

            try map.put(key, value);

            self.skipWhitespace();
        }

        if (self.isEOF() or self.peek() != '}') {
            return ParseError.UnclosedMap;
        }
        self.consume(); // '}'

        return EDNValue{ .map = map };
    }

    fn parseVector(self: *Parser) ParseError!EDNValue {
        self.consume(); // '['
        self.skipWhitespace();

        var list: std.ArrayList(EDNValue) = .empty;
        errdefer {
            for (list.items) |*item| {
                item.deinit(self.allocator);
            }
            list.deinit(self.allocator);
        }

        while (!self.isEOF() and self.peek() != ']') {
            const elem = try self.parseValue();
            try list.append(self.allocator, elem);
            self.skipWhitespace();
        }

        if (self.isEOF() or self.peek() != ']') {
            return ParseError.UnclosedVector;
        }
        self.consume(); // ']'

        return EDNValue{ .vector = try list.toOwnedSlice(self.allocator) };
    }

    fn parseKeyword(self: *Parser) ParseError!EDNValue {
        self.consume(); // ':'

        const start = self.pos;
        while (!self.isEOF() and isKeywordChar(self.peek())) {
            self.consume();
        }

        if (self.pos == start) {
            return ParseError.InvalidKeyword;
        }

        const keyword = try self.allocator.dupe(u8, self.source[start..self.pos]);
        return EDNValue{ .keyword = keyword };
    }

    fn parseString(self: *Parser) ParseError!EDNValue {
        self.consume(); // '"'

        const start = self.pos;
        while (!self.isEOF() and self.peek() != '"') {
            if (self.peek() == '\\') {
                self.consume();
                if (!self.isEOF()) {
                    self.consume();
                }
            } else {
                self.consume();
            }
        }

        if (self.isEOF()) {
            return ParseError.InvalidString;
        }

        const string = try self.allocator.dupe(u8, self.source[start..self.pos]);
        self.consume(); // '"'

        return EDNValue{ .string = string };
    }

    fn parseNumber(self: *Parser) ParseError!EDNValue {
        const start = self.pos;

        if (self.peek() == '-') {
            self.consume();
        }

        while (!self.isEOF() and (std.ascii.isDigit(self.peek()) or self.peek() == '.')) {
            self.consume();
        }

        const num_str = self.source[start..self.pos];
        const num = std.fmt.parseFloat(f64, num_str) catch {
            return ParseError.InvalidNumber;
        };

        return EDNValue{ .number = num };
    }

    fn parseBoolean(self: *Parser) ParseError!EDNValue {
        if (self.matchWord("true")) {
            return EDNValue{ .boolean = true };
        } else if (self.matchWord("false")) {
            return EDNValue{ .boolean = false };
        } else {
            return ParseError.UnexpectedChar;
        }
    }

    fn parseNil(self: *Parser) ParseError!EDNValue {
        if (self.matchWord("nil")) {
            return EDNValue{ .nil = {} };
        } else {
            return ParseError.UnexpectedChar;
        }
    }

    fn skipWhitespace(self: *Parser) void {
        while (!self.isEOF()) {
            const ch = self.peek();
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == ',') {
                self.consume();
            } else {
                break;
            }
        }
    }

    fn isKeywordChar(ch: u8) bool {
        return std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '/' or ch == '.' or ch == '+' or ch == '*' or ch == '!' or ch == '?' or ch == '<' or ch == '>' or ch == '=';
    }

    fn matchWord(self: *Parser, word: []const u8) bool {
        if (self.pos + word.len > self.source.len) {
            return false;
        }

        if (!std.mem.eql(u8, self.source[self.pos .. self.pos + word.len], word)) {
            return false;
        }

        if (self.pos + word.len < self.source.len) {
            const next = self.source[self.pos + word.len];
            if (std.ascii.isAlphanumeric(next)) {
                return false;
            }
        }

        self.pos += word.len;
        return true;
    }

    fn peek(self: *Parser) u8 {
        return self.source[self.pos];
    }

    fn consume(self: *Parser) void {
        self.pos += 1;
    }

    fn isEOF(self: *Parser) bool {
        return self.pos >= self.source.len;
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!EDNValue {
    var parser = Parser.init(allocator, source);
    return try parser.parseValue();
}

pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !EDNValue {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    return try parse(allocator, content);
}

// ========== Tests ==========

test "parse simple keyword" {
    const source = ":hello";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .keyword);
    try std.testing.expectEqualStrings("hello", value.keyword);
}

test "parse number" {
    const source = "42";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .number);
    try std.testing.expectEqual(@as(f64, 42.0), value.number);
}

test "parse negative number" {
    const source = "-42.5";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .number);
    try std.testing.expectApproxEqAbs(@as(f64, -42.5), value.number, 0.001);
}

test "parse string" {
    const source = "\"hello world\"";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .string);
    try std.testing.expectEqualStrings("hello world", value.string);
}

test "parse boolean true" {
    const source = "true";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .boolean);
    try std.testing.expectEqual(true, value.boolean);
}

test "parse boolean false" {
    const source = "false";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .boolean);
    try std.testing.expectEqual(false, value.boolean);
}

test "parse nil" {
    const source = "nil";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .nil);
}

test "parse empty vector" {
    const source = "[]";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .vector);
    try std.testing.expectEqual(@as(usize, 0), value.vector.len);
}

test "parse vector with elements" {
    const source = "[:a :b :c]";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .vector);
    try std.testing.expectEqual(@as(usize, 3), value.vector.len);
}

test "parse empty map" {
    const source = "{}";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .map);
    try std.testing.expectEqual(@as(u32, 0), value.map.count());
}

test "parse map with entries" {
    const source = "{:a 1 :b 2}";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .map);
    try std.testing.expectEqual(@as(u32, 2), value.map.count());
}

test "parse nested structure" {
    const source = "{:block-defs {:block/entry {:instructions [{:op :const}]}}}";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .map);
}

test "error on unclosed map" {
    const source = "{:a 1 :b 2";
    const result = parse(std.testing.allocator, source);
    try std.testing.expectError(error.UnclosedMap, result);
}

test "error on unclosed vector" {
    const source = "[:a :b :c";
    const result = parse(std.testing.allocator, source);
    try std.testing.expectError(error.UnclosedVector, result);
}

test "parse whitespace and commas" {
    const source = "{:a 1, :b 2,\n :c 3}";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    try std.testing.expect(value == .map);
    try std.testing.expectEqual(@as(u32, 3), value.map.count());
}

test "parse keyword with special chars" {
    const source = "{:op :builtin/add}";
    var value = try parse(std.testing.allocator, source);
    defer value.deinit(std.testing.allocator);

    const op = value.map.get("op").?;
    try std.testing.expect(op == .keyword);
    try std.testing.expectEqualStrings("builtin/add", op.keyword);
}

test "error on invalid keyword" {
    const source = "{:}";
    const result = parse(std.testing.allocator, source);
    try std.testing.expectError(error.InvalidKeyword, result);
}


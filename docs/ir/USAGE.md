# IR Backend Usage Guide

## Overview

The IR (Intermediate Representation) backend compiles Clojure source code to an intermediate EDN format without evaluation. This enables:

- Static analysis of Clojure programs
- Cross-backend verification (TreeWalk vs VM vs IR)
- Future optimization passes on the IR layer
- Debugging and introspection of compilation stages

## Phase 1 Status

**Supported Node types (11/24):**

- `constant` — literals (integers, strings, keywords, symbols)
- `local_ref` — local variable references from let bindings
- `var_ref` — resolved Var references (e.g. `clojure.core/+`)
- `def_node` — top-level `def` forms
- `if_node` — conditional expressions
- `let_node` — local bindings
- `call_node` — function calls
- `loop_node` — loop/recur constructs
- `recur_node` — recur targets
- `try_node` — exception handling
- `throw_node` — exception throwing

**Not yet supported:**

- `fn_node` — anonymous functions (Phase 1.5)
- `do_node`, `quote_node`, `set_node`, etc.

## Usage

### Command-line tool: `cljw-ir`

```sh
# Compile expression to IR
./zig-out/bin/cljw-ir -e '(+ 1 2)'

# Compile file to IR
./zig-out/bin/cljw-ir source.clj
```

**Output format:**

```
;; IR Backend Phase 1
:val/3
```

The output is an IR value ID (`:val/N` where N is a unique integer). Phase 1 prints only the top-level value ID; future phases will emit full EDN IR with function bodies and control flow.

### Building `cljw-ir`

```sh
# Use pinned Zig 0.16.0
/opt/homebrew/opt/zig@0.16/bin/zig build

# Or via Nix shell (recommended)
nix develop
zig build
```

The `cljw-ir` binary is installed to `zig-out/bin/cljw-ir`.

## Architecture

### Compilation Pipeline

```
Source text
    ↓
Reader (src/eval/reader.zig)
    ↓
Form (src/eval/form.zig)
    ↓
Analyzer (src/eval/analyzer/analyzer.zig)
    ↓
Node (src/eval/node.zig)
    ↓
IR Codegen (src/ir/codegen.zig)
    ↓
IRValueID + FunctionIR
```

**Key types:**

- `Form` — s-expression AST (reader output)
- `Node` — analyzed/typed AST with resolved symbols
- `IRValueID` — opaque reference to an IR value (`:val/N`)
- `FunctionIR` — function metadata + IR instruction blocks

### IR Value IDs

Phase 1 IR uses opaque value IDs as placeholders:

```zig
pub const IRValueID = union(enum) {
    val: u32,           // :val/3
    local: []const u8,  // :local/x
    param: []const u8,  // :param/a
};
```

Example IR values:
- `:val/0` — result of `(+ 1 2)` compilation
- `:local/x` — reference to let-bound `x`
- `:param/a` — reference to function parameter `a`

### Memory Management

`cljw-ir` uses arena allocation:

```zig
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const arena_alloc = arena.allocator();

// All Reader/Analyzer/Codegen allocations use arena_alloc
var reader = Reader.init(arena_alloc, source);
const node = try Analyzer.analyze(arena_alloc, &rt, &env, null, form, &macro_table);
const ir_value = try ir_codegen.compileNode(&ctx, node);

// Bulk free at end via arena.deinit()
```

No manual `free()` calls required — the arena owns all transient compilation state.

## Examples

### Basic Arithmetic

```clojure
(+ 1 2)
```

**Output:** `:val/3`

**Compilation steps:**

1. Reader parses `(+ 1 2)` → `Form` list with 3 elements
2. Analyzer resolves `+` to `clojure.core/+` → `Node.call_node`
3. IR codegen emits `:call` instruction with operator `:val/0` (the `+` var) and args `[:val/1 :val/2]`

### Let Binding

```clojure
(let [x 10] x)
```

**Output:** `:val/2`

**IR structure (conceptual):**

```edn
{:op :let
 :bindings [{:name :local/x :init :val/0}]  ; :val/0 = constant 10
 :body :local/x}                             ; reference to bound x
```

### Conditional

```clojure
(if true 1 2)
```

**Output:** `:val/3`

**IR structure:**

```edn
{:op :if
 :test :val/0      ; constant true
 :then :val/1      ; constant 1
 :else :val/2}     ; constant 2
```

## Differential Testing

Compare IR compilation against TreeWalk evaluation:

```sh
# TreeWalk backend (evaluate)
./zig-out/bin/cljw -e '(+ 1 2)'
# → 3

# IR backend (compile only)
./zig-out/bin/cljw-ir -e '(+ 1 2)'
# → :val/3
```

Phase 1 does NOT evaluate — it only compiles to IR. Future phases will add an IR interpreter to verify IR semantics match TreeWalk/VM.

## Known Limitations

### Phase 1 Scope

- No function bodies (`:fn-node` planned for Phase 1.5)
- No macro expansion (macros are expanded by Analyzer; IR sees post-expansion Nodes)
- No full EDN output (only top-level value ID)
- No pretty-printing of IR structures

### Bootstrap Conflict

`cljw-ir` is a **standalone tool** separate from `cljw` to avoid bootstrap dependency issues:

- `cljw` requires `clojure.core` bootstrap (451 KB of `.clj` sources + bytecode)
- `cljw-ir` uses minimal symbol resolution (no bootstrap needed)

This keeps IR compilation fast and independent of the runtime's bootstrap state.

## Future Phases

**Phase 1.5 — Function IR:**

- Compile `fn*` forms to `FunctionIR`
- Emit full EDN with `:params`, `:body`, `:captures`

**Phase 2 — IR Interpreter:**

- Evaluate IR directly (IR → Value)
- Differential oracle: TreeWalk/VM/IR must agree

**Phase 3 — Optimization Passes:**

- Constant folding
- Dead code elimination
- Inline expansion

**Phase 4 — Wasm Codegen:**

- IR → Wasm bytecode (via zwasm v2 embedding)
- Direct Clojure → Wasm compilation path

## Related Files

- [src/ir/codegen.zig](../../src/ir/codegen.zig) — IR compilation entry point
- [src/ir/function.zig](../../src/ir/function.zig) — `FunctionIR` structure
- [src/cljw_ir.zig](../../src/cljw_ir.zig) — standalone tool main()
- [build.zig](../../build.zig#L166-L184) — `cljw-ir` build target

## Contributing

When adding new Node type support:

1. Add case to `compileNode` switch in [src/ir/codegen.zig](../../src/ir/codegen.zig#L237-256)
2. Implement `compile<NodeType>` function
3. Update Phase 1 status in this guide
4. Add test case to [src/ir/test_codegen.zig](../../src/ir/test_codegen.zig)

Follow Zig 0.16 idioms per [.claude/rules/zig_tips.md](../../.claude/rules/zig_tips.md).

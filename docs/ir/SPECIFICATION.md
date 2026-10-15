# ClojureWasm IR (Intermediate Representation) Specification

**Version**: 0.1.0-draft  
**Status**: Experimental Design Phase  
**Last Updated**: 2026-10-15

## Overview

This document specifies the Intermediate Representation (IR) for ClojureWasm, a layer between the Clojure AST and WASM bytecode generation. The IR provides a stable interface that decouples the frontend (Clojure parsing and analysis) from the backend (WASM code generation).

## Goals

1. **Separation of Concerns**: Decouple Clojure semantics from WASM generation
2. **Optimization Layer**: Provide a stable structure for compiler optimizations
3. **Multiple Backends**: Enable future targets beyond WASM (JVM bytecode, native, etc.)
4. **Tooling**: Make compiler internals inspectable and testable
5. **Incremental Compilation**: Support separate compilation units

## Non-Goals

- **Runtime Representation**: IR is compile-time only, not a runtime format
- **Human Authoring**: IR is generated, not hand-written
- **Backward Compatibility**: During experimental phase, breaking changes are expected

## Design Principles

### 1. Explicit over Implicit

All semantics must be explicit in the IR:
- Lexical scoping structure
- Variable lifetimes
- Type information (when available)
- Control flow edges

### 2. SSA-like Form

The IR uses a Static Single Assignment (SSA) inspired form:
- Each value has a unique binding
- Control flow is explicit via blocks and jumps
- No mutation (functional form)

### 3. Serializable

The IR must be:
- Serializable to persistent storage (EDN/JSON)
- Readable for debugging
- Reproducible (same input → same IR)

### 4. Flat Structure

Avoid deep nesting:
- Use references instead of inline nesting
- Explicit binding IDs
- Separate symbol table

## IR Format Choice: EDN

**Decision**: Use EDN (Extensible Data Notation) as the IR format.

**Rationale**:
- Native Clojure format (no parsing overhead)
- Rich data types (keywords, symbols, sets, etc.)
- Better debugging (readable by Clojure developers)
- Extensible with metadata
- Can be read/written by both Clojure and Zig (via EDN parser)

**Trade-off**: Less universally supported than JSON, but given that:
1. The frontend will be Clojure-based
2. The project is ClojureWasm (Clojure ecosystem)
3. EDN parsers exist for many languages including C/C++/Zig

The benefits outweigh the ecosystem limitation.

## Core IR Structure

### Top-Level Program

```edn
{:ir-version "0.1.0"
 :modules [{:name "user"
            :namespace "user"
            :functions [...]}
           {:name "clojure.core"
            :namespace "clojure.core"
            :functions [...]}]
 :entry-point {:module "user"
               :function "main"}}
```

### Function Definition

```edn
{:id :fn/user-add-123
 :name "add"
 :namespace "user"
 :arity {:fixed 2}  ; or {:variadic 1} for (fn [x & xs])
 :params [:param/x :param/y]
 :blocks [:block/entry :block/return]
 :entry-block :block/entry}
```

### Basic Block

A basic block is a sequence of instructions with:
- A unique ID
- A list of instructions
- A terminator (return, branch, etc.)

```edn
{:id :block/entry
 :instructions [{:op :const :result :val/1 :value 10}
                {:op :const :result :val/2 :value 20}
                {:op :call :result :val/3
                 :fn :builtin/add
                 :args [:val/1 :val/2]}]
 :terminator {:op :return :value :val/3}}
```

### Instructions

Each instruction has:
- `:op` - operation type (keyword)
- `:result` - binding ID for the result (keyword, `:val/NNN`)
- Additional operation-specific fields

#### Constants

```edn
{:op :const :result :val/1 :value 42}
{:op :const :result :val/2 :value "hello"}
{:op :const :result :val/3 :value true}
{:op :const :result :val/4 :value nil}
```

#### Variable Reference

```edn
{:op :var-ref :result :val/5 :var :param/x}
```

#### Function Call

```edn
{:op :call
 :result :val/6
 :fn :fn/user-add-123
 :args [:val/1 :val/2]}
```

#### Primitive Operations

```edn
{:op :prim-add :result :val/7 :args [:val/1 :val/2]}
{:op :prim-sub :result :val/8 :args [:val/3 :val/4]}
{:op :prim-eq :result :val/9 :args [:val/5 :val/6]}
```

#### Conditional

```edn
{:op :if
 :condition :val/9
 :then-block :block/then
 :else-block :block/else}
```

#### Local Binding (let)

```edn
{:op :let
 :bindings [{:name :local/x :value :val/1}
            {:name :local/y :value :val/2}]
 :body :block/let-body}
```

#### Closure Creation

```edn
{:op :make-closure
 :result :val/10
 :fn :fn/inner-123
 :captures [:local/x :local/y]}
```

### Control Flow Terminators

Each block must end with exactly one terminator:

#### Return

```edn
{:op :return :value :val/3}
```

#### Branch

```edn
{:op :branch
 :condition :val/9
 :true-target :block/then
 :false-target :block/else}
```

#### Jump

```edn
{:op :jump :target :block/next}
```

#### Unreachable

```edn
{:op :unreachable}
```

## Value IDs

All values in the IR are referred to by unique IDs (keywords):

- `:val/NNN` - Computed values (SSA)
- `:param/name` - Function parameters
- `:local/name` - Local bindings
- `:fn/namespace-name-NNN` - Function definitions
- `:block/name` - Basic blocks

## Type Annotations (Optional)

The IR supports optional type annotations for optimization:

```edn
{:op :const
 :result :val/1
 :value 42
 :type {:tag :i64}}
```

```edn
{:op :call
 :result :val/6
 :fn :fn/user-add-123
 :args [:val/1 :val/2]
 :result-type {:tag :i64}}
```

## Metadata

IR nodes can carry metadata for debugging and optimization:

```edn
{:op :call
 :result :val/6
 :fn :fn/user-add-123
 :args [:val/1 :val/2]
 :meta {:source-location {:file "user.clj" :line 10 :column 5}
        :inline-candidate true}}
```

## Example: Simple Function

### Clojure Source

```clojure
(defn add [x y]
  (+ x y))
```

### IR Representation

```edn
{:id :fn/user-add-1
 :name "add"
 :namespace "user"
 :arity {:fixed 2}
 :params [:param/x :param/y]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:id :block/entry
   :instructions [{:op :var-ref :result :val/1 :var :param/x}
                  {:op :var-ref :result :val/2 :var :param/y}
                  {:op :call
                   :result :val/3
                   :fn :builtin/add
                   :args [:val/1 :val/2]}]
   :terminator {:op :return :value :val/3}}}}
```

## Example: Conditional

### Clojure Source

```clojure
(defn abs [x]
  (if (< x 0)
    (- x)
    x))
```

### IR Representation

```edn
{:id :fn/user-abs-2
 :name "abs"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/x]
 :blocks [:block/entry :block/then :block/else :block/merge]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:id :block/entry
   :instructions [{:op :var-ref :result :val/1 :var :param/x}
                  {:op :const :result :val/2 :value 0}
                  {:op :prim-lt :result :val/3 :args [:val/1 :val/2]}]
   :terminator {:op :branch
                :condition :val/3
                :true-target :block/then
                :false-target :block/else}}
  
  :block/then
  {:id :block/then
   :instructions [{:op :var-ref :result :val/4 :var :param/x}
                  {:op :prim-neg :result :val/5 :args [:val/4]}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/else
  {:id :block/else
   :instructions [{:op :var-ref :result :val/6 :var :param/x}]
   :terminator {:op :jump :target :block/merge}}
  
  :block/merge
  {:id :block/merge
   :instructions [{:op :phi
                   :result :val/7
                   :sources [{:block :block/then :value :val/5}
                            {:block :block/else :value :val/6}]}]
   :terminator {:op :return :value :val/7}}}}
```

## Example: Closure

### Clojure Source

```clojure
(defn make-adder [n]
  (fn [x]
    (+ x n)))
```

### IR Representation

```edn
{:id :fn/user-make-adder-3
 :name "make-adder"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/n]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:id :block/entry
   :instructions [{:op :var-ref :result :val/1 :var :param/n}
                  {:op :make-closure
                   :result :val/2
                   :fn :fn/user-make-adder-inner-4
                   :captures [:val/1]}]
   :terminator {:op :return :value :val/2}}}}

{:id :fn/user-make-adder-inner-4
 :name "make-adder$inner"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/x]
 :captures [:capture/n]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs
 {:block/entry
  {:id :block/entry
   :instructions [{:op :var-ref :result :val/1 :var :param/x}
                  {:op :capture-ref :result :val/2 :capture :capture/n}
                  {:op :call
                   :result :val/3
                   :fn :builtin/add
                   :args [:val/1 :val/2]}]
   :terminator {:op :return :value :val/3}}}}
```

## Operations Reference

### Primitive Operations

| Operation | Args | Result | Description |
|-----------|------|--------|-------------|
| `:const` | value | val | Load constant |
| `:var-ref` | var | val | Reference parameter/local |
| `:capture-ref` | capture | val | Reference captured value |
| `:prim-add` | [val val] | val | Integer/float addition |
| `:prim-sub` | [val val] | val | Subtraction |
| `:prim-mul` | [val val] | val | Multiplication |
| `:prim-div` | [val val] | val | Division |
| `:prim-eq` | [val val] | bool | Equality check |
| `:prim-lt` | [val val] | bool | Less than |
| `:prim-gt` | [val val] | bool | Greater than |
| `:prim-neg` | [val] | val | Negation |

### High-Level Operations

| Operation | Description |
|-----------|-------------|
| `:call` | Function call |
| `:make-closure` | Create closure |
| `:make-vector` | Create vector |
| `:make-map` | Create map |
| `:vector-get` | Vector element access |
| `:map-get` | Map value access |
| `:if` | Conditional expression |
| `:let` | Local binding |
| `:loop` | Loop with recur point |
| `:recur` | Tail recursion |

### Terminators

| Terminator | Description |
|------------|-------------|
| `:return` | Return from function |
| `:branch` | Conditional branch |
| `:jump` | Unconditional jump |
| `:unreachable` | Unreachable code marker |

## Verification Rules

An IR program is valid if:

1. **Unique IDs**: All value/block/function IDs are unique
2. **Defined Before Use**: All referenced IDs are defined before use
3. **Block Structure**: Each block has exactly one terminator
4. **Type Consistency**: Operations have compatible argument types (when typed)
5. **Control Flow**: All blocks are reachable from entry block
6. **SSA Property**: Each value is defined exactly once

## Future Extensions

### Planned for v0.2.0

- [ ] Exception handling (try/catch/finally)
- [ ] Multi-arity functions
- [ ] Variadic functions
- [ ] Record/protocol support
- [ ] Macro expansion tracking

### Under Consideration

- [ ] WASM-specific annotations (memory layout, imports/exports)
- [ ] Optimization hints (inline, tail-call, etc.)
- [ ] Debug information (source maps, variable names)
- [ ] Profile-guided optimization data

## References

- [LLVM IR Language Reference](https://llvm.org/docs/LangRef.html)
- [GraalVM Truffle Framework](https://www.graalvm.org/latest/graalvm-as-a-platform/language-implementation-framework/)
- [Cranelift IR](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/docs/ir.md)
- [ClojureScript Compiler Internals](https://clojurescript.org/about/compiler-internals)

## Changelog

### 2026-10-15 - v0.1.0-draft

- Initial specification
- Core IR structure defined
- Basic operations and examples
- EDN format chosen

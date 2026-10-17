# Function IR Specification

## Overview

Function IR represents compiled `fn*` forms as structured EDN data containing:
- Parameter list
- Function body (IR instruction sequence)
- Captured variables (for closures)
- Arity information (fixed vs variadic)

## EDN Format

```edn
{:op :fn
 :id "fn/42"
 :name "my-func"              ; optional, for named fns
 :arity {:fixed 2}            ; or {:variadic {:required 1}}
 :params [:param/x :param/y]
 :captures [:local/outer]     ; variables captured from enclosing scope
 :body :val/5}                ; IR value ID of function body result
```

## Field Descriptions

### `:op`
Always `:fn` for function IR.

### `:id`
Unique identifier for this function, format `fn/N` where N is monotonically increasing.

### `:name`
Optional string name for the function. Present for:
- Named functions defined with `def`
- Functions with `:name` metadata

Absent for anonymous lambda expressions.

### `:arity`
Describes function parameter structure:

**Fixed arity:**
```edn
{:fixed 2}  ; exactly 2 parameters
```

**Variadic arity:**
```edn
{:variadic {:required 1}}  ; 1+ parameters, rest collected in final param
```

### `:params`
Vector of parameter IR value IDs in declaration order:
```edn
[:param/x :param/y]
[:param/x :param/rest]  ; variadic: rest is collection of remaining args
```

Parameter IDs use `:param/NAME` format (distinct from `:local/NAME` for let bindings).

### `:captures`
Vector of IR value IDs for variables captured from enclosing lexical scope (closures only):
```edn
[:local/outer-x :local/outer-y]
```

Empty vector `[]` for non-closure functions.

### `:body`
IR value ID representing the function body's return value. The body is a compiled expression (which may be a `:do` sequence in later phases).

## Examples

### Simple Function
```clojure
(fn* [x] (* x 2))
```

IR:
```edn
{:op :fn
 :id "fn/1"
 :arity {:fixed 1}
 :params [:param/x]
 :captures []
 :body :val/3}  ; (* x 2) compiled to :call instruction
```

### Closure
```clojure
(let [multiplier 10]
  (fn* [x] (* x multiplier)))
```

IR:
```edn
{:op :fn
 :id "fn/2"
 :arity {:fixed 1}
 :params [:param/x]
 :captures [:local/multiplier]
 :body :val/8}
```

### Variadic Function
```clojure
(fn* [x & rest] (cons x rest))
```

IR:
```edn
{:op :fn
 :id "fn/3"
 :arity {:variadic {:required 1}}
 :params [:param/x :param/rest]
 :captures []
 :body :val/12}
```

### Named Function
```clojure
(def add (fn* [a b] (+ a b)))
```

IR (from the `fn*` compilation):
```edn
{:op :fn
 :id "fn/4"
 :name "add"
 :arity {:fixed 2}
 :params [:param/a :param/b]
 :captures []
 :body :val/15}
```

## Compilation Strategy

### Parameter Binding
Parameters shadow outer scope:
```clojure
(let [x 1]
  (fn* [x] x))  ; parameter x shadows let-bound x
```

Inside the function body, `x` resolves to `:param/x`, not `:local/x`.

### Closure Analysis
The IR codegen walks the function body AST and records any `:local_ref` nodes whose binding site is outside the function scope → those become captures.

### Multi-Arity Functions
Phase 1.5 compiles **single-arity functions only**. Multi-arity dispatch (e.g., `(fn ([x] ...) ([x y] ...))`) is deferred to Phase 1.6 or Phase 2.

Each arity would become a separate `FunctionIR` entry with the same `:name` but different `:arity` and `:params`.

## Integration with Existing IR

Function IR values are first-class:
```clojure
(let [f (fn* [x] x)]
  (f 42))
```

IR:
```edn
{:op :let
 :bindings [{:name :local/f
             :init {:op :fn
                    :id "fn/5"
                    :arity {:fixed 1}
                    :params [:param/x]
                    :captures []
                    :body :param/x}}]
 :body {:op :call
        :fn :local/f
        :args [:val/42]}}
```

The function IR is nested as the `:init` value of the let binding.

## Relation to TreeWalk/VM

- **TreeWalk**: `eval(fn_node)` → `Value.function` (runtime closure object)
- **VM**: `fn*` → bytecode with MAKE_CLOSURE opcode
- **IR**: `fn*` → structured FunctionIR EDN (compilation-time representation)

IR does NOT create runtime closures in Phase 1.5 — it emits the structure. Phase 2 (IR Interpreter) will interpret FunctionIR to create runtime function values.

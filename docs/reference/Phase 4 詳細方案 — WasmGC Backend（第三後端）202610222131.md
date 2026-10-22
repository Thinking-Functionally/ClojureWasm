# Phase 4 詳細方案 — WasmGC Backend（第三後端）

## 架構定位

WasmGC 係 ClojureWasm 嘅**第三個後端選項**，同現有嘅 TreeWalk 同 VM 並列：

```
Clojure 源碼
    ↓
Reader → Analyzer (生成 AST)
    ↓
    ├─→ TreeWalk (src/eval/backend/tree_walk.zig)
    │   直接解釋 AST，適合 debug
    │
    ├─→ VM (src/eval/backend/vm.zig + vm/*)
    │   編譯成字節碼執行，平衡效能
    │
    └─→ WasmGC (src/eval/backend/wasmgc/)  ← 新增
        編譯成 WebAssembly，目標瀏覽器/邊緣部署
```

**共用 Layer 0-1 基建**：
- `src/runtime/` — Value 類型定義、集合介面（TreeWalk/VM 重用，WasmGC 參考）
- `src/eval/reader.zig`、`src/eval/analyzer/` — 所有後端共用
- `src/eval/backend/intrinsic.zig` 等共用設施

**WasmGC 獨立實現**：
- 從 Analyzer 輸出嘅 AST 開始
- 生成 WebAssembly Text (WAT) 格式
- 使用 WasmGC 原生類型（struct/array/ref）
- Host-managed GC（唔係手動 arena）

---

## 目錄結構

遵循現有模式：`src/eval/backend/wasmgc/`

```
src/eval/backend/wasmgc/
├── compiler.zig       # AST → WAT 編譯器主邏輯
├── codegen.zig        # WAT 文本生成
├── value_types.zig    # Clojure 類型 → WasmGC 類型映射
├── runtime.zig        # WasmGC 運行時支援（核心函數）
├── collections.zig    # 持久化數據結構（Vector/Map/Set）
├── host_interop.zig   # JavaScript/Web 平台整合
└── emit.zig           # WAT 格式化輸出
```

初期可能只有 `wasmgc.zig` 單一檔案，等複雜咗先展開做目錄。

---

## WasmGC 類型映射

### 核心 Value 表示（原生模式，Option B）

WasmGC 後端**唔重用** `src/runtime/Value` 嘅 NaN-boxing 表示，改用 WasmGC 原生類型：

```wasm
;; 基礎 tagged union
(type $Value (struct
  (field $tag i32)        ;; 類型標籤：0=nil, 1=boolean, 2=long, 3=double, 4=string, 5=symbol, 6=keyword, 7=list, 8=vector, 9=map, 10=set
  (field $data (ref null $ValueData))
))

;; Union payload
(type $ValueData (union
  (struct)                     ;; nil (no data)
  (struct (field i32))         ;; boolean (0=false, 1=true)
  (struct (field i64))         ;; long
  (struct (field f64))         ;; double
  (struct (field (ref $String)))
  (struct (field (ref $Symbol)))
  (struct (field (ref $Keyword)))
  (struct (field (ref $List)))
  (struct (field (ref $Vector)))
  (struct (field (ref $Map)))
  (struct (field (ref $Set)))
))

;; 字串類型
(type $String (struct
  (field $bytes (array (mut i8)))
  (field $hash i32)
))

;; 符號類型
(type $Symbol (struct
  (field $ns (ref null $String))
  (field $name (ref $String))
  (field $hash i32)
))

;; 關鍵字類型
(type $Keyword (struct
  (field $ns (ref null $String))
  (field $name (ref $String))
  (field $hash i32)
))
```

**類型標籤映射**：
- `0` = nil
- `1` = boolean
- `2` = long (i64)
- `3` = double (f64)
- `4` = string
- `5` = symbol
- `6` = keyword
- `7` = list
- `8` = vector
- `9` = map
- `10` = set

### 持久化數據結構

使用 WasmGC 原生結構實現 Clojure 持久化集合：

```wasm
;; PersistentVector (簡化嘅 RRB-Tree)
(type $Vector (struct
  (field $count i32)
  (field $shift i32)              ;; 層級位移
  (field $root (ref $VectorNode))
  (field $tail (array (mut (ref $Value))))
))

(type $VectorNode (struct
  (field (array (mut (ref null anyref))))  ;; 可以係 Value 或者 VectorNode
))

;; PersistentHashMap (HAMT)
(type $Map (struct
  (field $count i32)
  (field $root (ref $MapNode))
))

(type $MapNode (struct
  (field $bitmap i32)                      ;; 32-bit bitmap
  (field $array (array (mut (ref null anyref))))  ;; 交替存 key, value, 或者 子節點
))

;; PersistentHashSet (包裝 Map)
(type $Set (struct
  (field $impl (ref $Map))  ;; 重用 Map，value 永遠係 true
))

;; List (單向連結串列)
(type $List (struct
  (field $first (ref $Value))
  (field $rest (ref null $List))
  (field $count i32)
))
```

---

## 編譯流程

### AST → WAT 編譯器

```
Analyzer 輸出 (AST)
    ↓
WasmGC Compiler (src/eval/backend/wasmgc/compiler.zig)
    ├─ 特殊形式 (if/let/fn*/loop*/recur 等)
    ├─ 函數呼叫
    ├─ 字面值 (literals)
    └─ 變數引用
    ↓
WAT 文本 (codegen.zig)
    ↓
wasm-tools (WAT → WASM)
    ↓
.wasm 模組
```

### 特殊形式編譯策略

| Clojure 形式 | WasmGC 實現                                  |
|--------------|----------------------------------------------|
| `if`         | `if` (WasmGC 原生)                           |
| `do`         | 序列執行，返回最後一個表達式                 |
| `let`        | `local` 變數                                 |
| `fn*`        | `(func ...)` + 閉包環境 struct               |
| `loop*`      | `(loop ...)` + `local` 變數                  |
| `recur`      | `br` (跳轉到 `loop` 開始)                    |
| `def`        | 全域 `(global ...)` 或者 namespace map 插入 |
| `quote`      | 編譯期展開成字面值                           |

### 運行時函數

核心運行時函數用 WAT 手寫 (`src/eval/backend/wasmgc/runtime.zig` 生成)：

```wasm
;; 核心運行時函數
(func $clojure.core/conj (param $coll (ref $Value)) (param $item (ref $Value)) (result (ref $Value)))
(func $clojure.core/assoc (param $map (ref $Value)) (param $key (ref $Value)) (param $val (ref $Value)) (result (ref $Value)))
(func $clojure.core/get (param $coll (ref $Value)) (param $key (ref $Value)) (result (ref $Value)))
(func $clojure.core/first (param $coll (ref $Value)) (result (ref $Value)))
(func $clojure.core/rest (param $coll (ref $Value)) (result (ref $Value)))
(func $clojure.core/count (param $coll (ref $Value)) (result i32))
(func $clojure.core/nth (param $coll (ref $Value)) (param $idx i32) (result (ref $Value)))
;; ... 更多核心函數
```

---

## 建構整合

### build.zig 延伸

```zig
// src/eval/backend/wasmgc.zig 編譯入主程式
const wasmgc = b.addModule("wasmgc", .{
    .root_source_file = b.path("src/eval/backend/wasmgc.zig"),
});

// 新增 wasmgc 編譯步驟
const wasmgc_step = b.step("wasmgc", "Compile Clojure to WasmGC");
const wasmgc_exe = b.addExecutable(.{
    .name = "cljw-wasmgc",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});
wasmgc_exe.root_module.addImport("wasmgc", wasmgc);
wasmgc_step.dependOn(&b.addInstallArtifact(wasmgc_exe, .{}).step);
```

### CLI 入口

```bash
# 編譯 Clojure 源碼到 .wasm
cljw wasmgc -i core.clj -o core.wasm

# 執行 .wasm (用 wasmtime 或者瀏覽器)
wasmtime core.wasm
```

---

## 實施時間表

### Month 1: 基礎建設 + 類型設計

**Week 1-2: WasmGC 規格研究**
- 閱讀 [WasmGC proposal](https://github.com/WebAssembly/gc)
- 研究現有實現 (wasm-tools, binaryen)
- 設計 Value 類型表示 (tagged union vs alternatives)
- **交付物**: `docs/reference/wasmgc-value-design.md`

**Week 3-4: 類型原型**
- 實現 `value_types.zig`: 基礎 WAT 類型生成
- 實現簡單字面值編譯 (nil, boolean, long, double, string)
- 編寫測試: WAT 輸出驗證
- **交付物**: `src/eval/backend/wasmgc/value_types.zig` + 測試

### Month 2: 核心運行時 + 簡單求值器

**Week 1-2: 持久化數據結構**
- 實現 PersistentVector (簡化版本，固定 tail size)
- 實現 PersistentHashMap (HAMT，bitmap 節點)
- 實現 PersistentHashSet (包裝 Map)
- 實現 List (單向連結串列)
- **交付物**: `collections.zig` + 集合操作函數 (conj, assoc, get, count)

**Week 3-4: 基礎求值器**
- 實現 AST → WAT 編譯器框架 (`compiler.zig`)
- 支援特殊形式: `do`, `if`, `let`
- 支援函數呼叫 (直接呼叫，未有閉包)
- 編寫 e2e 測試: `(if true 1 2)` → WAT → wasm-tools → wasmtime
- **交付物**: `compiler.zig` + 簡單表達式編譯測試

### Month 3: 函數 + 閉包 + recur

**Week 1-2: 函數實現**
- 支援 `fn*` (匿名函數)
- 支援閉包 (環境 struct)
- 支援 `loop*` + `recur`
- **交付物**: 遞迴函數測試 (fibonacci, factorial)

**Week 3-4: namespace + def**
- 實現 namespace map (全域符號表)
- 支援 `def` (全域定義)
- 支援 `defn` (透過宏展開 → `def` + `fn*`)
- **交付物**: 多函數模組編譯測試

### Month 4: Host Interop + 整合測試

**Week 1-2: JavaScript 互操作**
- 實現 JS 函數匯入 (`import "js" "console.log"`)
- 實現 Value ↔ JS 類型轉換
- 支援 DOM 操作 (proof-of-concept)
- **交付物**: `host_interop.zig` + 瀏覽器範例

**Week 3: 整合測試**
- 執行 `clojure.core` 子集 (取 30-50 個核心函數)
- 對比 TreeWalk / VM 輸出 (差異掃描)
- 性能基準測試 (vs TreeWalk baseline)
- **交付物**: `test/wasmgc_e2e/` 測試套件

**Week 4: 文檔 + 交付**
- 撰寫使用文檔 (`docs/wasmgc-backend.md`)
- 撰寫 ADR (架構決策記錄)
- 更新 ROADMAP
- **交付物**: 可用嘅 WasmGC 後端 (alpha 質量)

---

## 驗證標準

### 功能完整性

**Tier 1 (必須)：**
- ✅ 基礎類型: nil, boolean, long, double, string, symbol, keyword
- ✅ 集合類型: list, vector, map, set
- ✅ 特殊形式: if, do, let, fn*, loop*, recur, def
- ✅ 函數呼叫 + 閉包
- ✅ 核心函數: conj, assoc, get, first, rest, count, nth (20-30 個)

**Tier 2 (應該)：**
- ✅ namespace 管理
- ✅ 宏展開 (依賴 Analyzer，WasmGC 只編譯展開後嘅 AST)
- ✅ JS 互操作 (基礎匯入/匯出)
- ✅ 錯誤處理 (throw/try/catch 映射到 WasmGC exception handling)

**Tier 3 (延後)：**
- ⏸ Metadata (需要 Value 結構擴展)
- ⏸ 多方法 (multimethods，需要運行時動態調度)
- ⏸ 協議 (protocols，需要 vtable 生成)
- ⏸ 並發原語 (atom, ref, agent — WasmGC 單線程，需要設計)

### 正確性測試

對每個實現嘅 Clojure 函數，執行差異掃描：

```bash
# 同樣表達式，TreeWalk vs WasmGC 輸出對比
bash scripts/clj_diff_sweep.sh test/wasmgc_exprs.txt --backends tree_walk,wasmgc
```

目標：**零差異** (除咗已接受嘅發散，見 `.dev/accepted_divergences.yaml`)。

### 性能基準

- **Baseline**: TreeWalk (解釋器)
- **Target**: WasmGC 應該快 2-5x (JIT 編譯 + 原生 struct)
- **測試用例**:
  - Fibonacci (遞迴)
  - Vector 操作 (conj 1000 次)
  - Map 操作 (assoc/get 1000 次)
  - 宏展開密集測試

---

## 相依工具

### 必須安裝

1. **wasm-tools** (Rust)
   ```bash
   cargo install wasm-tools
   ```
   用途: WAT ↔ WASM 轉換, 模組驗證

2. **wasmtime** (Rust)
   ```bash
   cargo install wasmtime-cli
   ```
   用途: 本地執行 .wasm 模組

### 可選 (開發期)

3. **wasm-objdump** (WABT)
   ```bash
   brew install wabt  # macOS
   ```
   用途: 除錯 .wasm 二進制

4. **binaryen** (wasm-opt)
   ```bash
   brew install binaryen
   ```
   用途: .wasm 優化 (size/speed)

---

## 風險 + 緩解

### 風險 1: WasmGC 瀏覽器支援

**風險描述**: 舊版瀏覽器唔支援 WasmGC (Chrome 119+, Firefox 120+, Safari 未確定)。

**緩解策略**:
- 初期目標: Chrome/Firefox 最新版 + wasmtime (本地測試)
- 延後: 提供 polyfill 或者降級到 Phase 3 (手動 GC) 如果需要

### 風險 2: 持久化數據結構效能

**風險描述**: WasmGC struct 操作可能比原生 Zig 慢，影響 Vector/Map 效能。

**緩解策略**:
- Month 2 Week 1-2 做性能測試，如果唔符合預期 (< 2x TreeWalk)，考慮:
  - 簡化數據結構 (例如放棄完整 RRB-Tree，用固定 tail)
  - 部分操作用 host 函數 (Zig 實現，WASM 匯入)

### 風險 3: 閉包環境複雜度

**風險描述**: Clojure 閉包可以捕獲任意數量變數，WasmGC struct 需要動態大小管理。

**緩解策略**:
- 編譯期分析閉包捕獲變數，生成固定大小 struct
- 如果捕獲數量超過閾值 (例如 10)，降級到 `(array (ref $Value))`

---

## 同現有後端嘅關係

### 共用組件

- ✅ `src/eval/reader.zig` — 所有後端共用
- ✅ `src/eval/analyzer/` — 所有後端共用
- ✅ `src/runtime/Value.zig` 定義 — WasmGC **參考** (唔直接重用結構)
- ✅ `src/runtime/collections/*.zig` 介面 — WasmGC 實現相同語義

### 獨立組件

- ❌ WasmGC 唔用 `src/runtime/gc/` (host-managed GC)
- ❌ WasmGC 唔用 `src/runtime/thread.zig` (單線程)
- ❌ WasmGC 唔用 `src/eval/backend/vm/` 字節碼

### CLI 入口

```bash
cljw <backend> [options]

# 現有
cljw tree-walk -e '(+ 1 2)'  # TreeWalk 後端
cljw vm -e '(+ 1 2)'          # VM 後端

# 新增
cljw wasmgc -i core.clj -o core.wasm  # WasmGC 後端 (編譯)
wasmtime core.wasm                     # 執行編譯好嘅 .wasm
```

---

## Zone 依賴合規

WasmGC 後端位於 **Layer 1** (`src/eval/backend/wasmgc/`)。

### 允許 import

```zig
// Layer 0 (runtime) — 允許
const Value = @import("../../runtime/Value.zig");
const Env = @import("../../runtime/Env.zig");
const Runtime = @import("../../runtime/Runtime.zig");

// Layer 1 (eval) 同級 — 允許
const Analyzer = @import("../analyzer.zig");
const AST = @import("../ast.zig");
```

### 禁止 import

```zig
// Layer 2 (lang) — 禁止
const Primitives = @import("../../lang/primitives.zig");  // ❌

// Layer 3 (app) — 禁止
const REPL = @import("../../app/repl.zig");  // ❌
```

### Vtable 模式 (如果需要)

如果 WasmGC 運行時需要回調 higher layer (例如宏展開)，使用 vtable：

```zig
// src/runtime/Runtime.zig (Layer 0)
pub const WasmGCVTable = struct {
    expandMacro: *const fn(*Runtime, *Env, Value) anyerror!Value,
};

// src/eval/backend/wasmgc/compiler.zig (Layer 1)
// 啟動時注入
runtime.wasmgc_vtable = .{
    .expandMacro = analyzer.expandMacro,
};
```

---

## 開始實施前嘅問題

1. **係咪批准呢個 Phase 4 方案？**
2. **時間表 (4 個月) 係咪合理？**
3. **有冇其他架構疑問需要討論？**

如果批准，下一步：
1. 創建目錄結構 `src/eval/backend/wasmgc/`
2. 撰寫 ADR (架構決策記錄)
3. 開始 Month 1 Week 1: WasmGC 規格研究 + Value 類型設計原型

# ClojureWasm IR v1.0 規格（精簡版）

**版本**: 1.0.0  
**日期**: 2026-10-15  
**狀態**: PoC Ready

---

## 設計哲學

> **Clojure 做抽象（高層語義），Zig 做執行（底層生成），EDN 作橋樑（數據交換）**

### 三大核心價值

1. **維護性** — EDN 可讀、可調試、可用工具分析
2. **版本隔離** — zwasm 升級只改 Zig adapter 層，IR 格式不變
3. **語言優勢** — Clojure 擅長抽象，Zig 擅長執行，各司其職

---

## IR 結構概覽

### 1. 頂層程序

```edn
{:ir-version "1.0.0"
 :modules [{:name "user" :functions [...]}]
 :entry-point {:module "user" :function "main"}}
```

### 2. 函數定義

```edn
{:id :fn/user-add-1
 :name "add"
 :namespace "user"
 :arity {:fixed 2}                    ; 或 {:variadic {...}}
 :params [:param/x :param/y]
 :blocks [:block/entry]
 :entry-block :block/entry
 :block-defs {...}}                   ; 塊定義 map
```

### 3. 基本塊

```edn
{:id :block/entry
 :instructions [{:op :const ...} {:op :call ...}]
 :terminator {:op :return :value :val/3}}
```

每個塊：**指令序列 + 恰好一個終止符**

---

## 核心操作（15 種）

### 常量 & 引用

| 操作 | 示例 |
|------|------|
| `:const` | `{:op :const :result :val/1 :value 42}` |
| `:var-ref` | `{:op :var-ref :result :val/2 :var :param/x}` |
| `:capture-ref` | `{:op :capture-ref :result :val/3 :capture :capture/n}` |

### 原語操作

| 操作 | 說明 |
|------|------|
| `:prim-add` / `:prim-sub` / `:prim-mul` | 算術 |
| `:prim-eq` / `:prim-lt` / `:prim-gt` | 比較 |

### 高層操作

| 操作 | 說明 |
|------|------|
| `:call` | 函數調用 |
| `:make-closure` | 創建閉包 |
| `:make-vector` | 創建向量 |
| `:make-map` | 創建映射 |

### 控制流

| 操作 | 說明 |
|------|------|
| `:phi` | SSA 合併節點 |
| `:bind` | Let 綁定 |

---

## 終止符（4 種）

| 終止符 | 示例 |
|--------|------|
| `:return` | `{:op :return :value :val/3}` |
| `:branch` | `{:op :branch :condition :val/1 :true-target :block/then :false-target :block/else}` |
| `:jump` | `{:op :jump :target :block/next}` |
| `:unreachable` | `{:op :unreachable}` |

---

## 完整示例

### Clojure 源碼

```clojure
(defn add [x y]
  (+ x y))
```

### IR 表示

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
   :instructions
   [{:op :var-ref :result :val/1 :var :param/x}
    {:op :var-ref :result :val/2 :var :param/y}
    {:op :call :result :val/3 :fn :builtin/add :args [:val/1 :val/2]}]
   :terminator
   {:op :return :value :val/3}}}}
```

---

## PoC MVP 範圍

### ✅ Phase 1 支持

```clojure
(defn add [x y] (+ x y))           ; 函數、參數、算術
(if (> x 0) x (- x))               ; 條件分支
(let [x 10] (* x 2))               ; Let 綁定
```

### ❌ Phase 2 延後

- 閉包 `(fn [x] (+ x n))`
- 遞歸 `(defn fact [n] ...)`
- 數據結構 `[1 2 3]` / `{:a 1}`
- 高階函數 `(map inc xs)`

---

## 值 ID 命名規則

| 前綴 | 用途 | 示例 |
|------|------|------|
| `:val/NNN` | SSA 計算值 | `:val/1`, `:val/42` |
| `:param/name` | 函數參數 | `:param/x` |
| `:local/name` | Let 綁定 | `:local/tmp` |
| `:fn/...` | 函數定義 | `:fn/user-add-1` |
| `:block/...` | 基本塊 | `:block/entry` |
| `:capture/name` | 閉包捕獲 | `:capture/n` |

---

## 驗證規則

有效 IR 必須滿足：

1. **唯一 ID** — 所有值/塊/函數 ID 唯一
2. **定義先於使用** — 引用的 ID 必須已定義
3. **塊結構** — 每個塊恰好一個終止符
4. **SSA 屬性** — 每個值恰好定義一次
5. **控制流** — 所有塊從入口塊可達

---

## 工具鏈

### IR Inspector

```bash
cljw ir-inspect output.ir.edn --function add
# 輸出：高亮 IR、數據流
```

### IR Visualizer

```bash
cljw ir-viz output.ir.edn --output cfg.dot
dot -Tpng cfg.dot -o cfg.png
# 生成控制流圖
```

### IR Diff

```bash
cljw ir-diff before.ir.edn after.ir.edn
# 顯示優化前後差異
```

---

## 實施路線圖

### Phase 0.5：EDN 解析驗證（2-3 天）

**目標**：證明 Zig 能快速解析 EDN

```bash
cd experimental/ir-rewrite/poc-edn-parser
echo '{:op :const :result :val/1 :value 42}' > test.edn
./edn_test test.edn
# 預期：< 1ms 解析成功
```

**交付物**：
- `src/ir/edn_parser.zig` — EDN 子集解析器（~500 行）
- 單元測試全綠
- 性能報告（< 10ms 解析 100 節點）

### Phase 1：最小 PoC（2-3 週）

**前端**（Clojure）：
```clojure
;; src/ir/minimal_frontend.clj
(defn compile-to-ir [source]
  (-> source parse ast->ir validate to-edn))
```

**後端**（Zig）：
```zig
// src/ir/minimal_backend.zig
pub fn compileIR(allocator: Allocator, ir_file: []const u8) ![]u8 {
    const ir = try edn.parseFile(allocator, ir_file);
    return try codegen.generate(allocator, ir);
}
```

**成功標準**：
- `(defn add [x y] (+ x y))` 能編譯並執行
- 編譯時間 < 3x 當前（PoC 允許較慢）

### Phase 2：完整實現（2-3 月）

- 覆蓋 90% Clojure 特性
- 編譯時間 < 2x 當前
- 優化層（常量折疊、死代碼消除、內聯）

---

## 決策點

### ✅ 在 Phase 0.5 後評估

1. EDN 解析性能可接受？
2. IR 結構清晰易懂？
3. 繼續 Phase 1？

### ✅ 在 Phase 1 後評估

1. 編譯時間 < 3x？
2. 生成的 WASM 正確？
3. 繼續 Phase 2？

---

## 參考文檔

| 文檔 | 用途 |
|------|------|
| `SPECIFICATION.md` | 完整規格（~600 行） |
| `DESIGN_RATIONALE.md` | 設計決策（~500 行） |
| `EXAMPLES.md` | 範例集（~700 行） |
| `REVIEW.md` | 技術審查（~760 行） |

---

**下一步**：開始 Phase 0.5 EDN 解析驗證

**狀態**：📋 Ready for PoC

# ClojureWasm IR 設計全面審查報告

**審查日期**: 2026-10-15  
**審查者**: Claude Opus 4.6  
**設計版本**: v0.1.0-draft  
**文檔覆蓋**: SPECIFICATION.md, DESIGN_RATIONALE.md, EXAMPLES.md, README.md

---

## 執行摘要

### 總體評價：⭐⭐⭐⭐☆ (4.5/5)

ClojureWasm IR 設計**架構清晰、目標明確、文檔完整**，為項目帶來顯著的長期價值。設計採用了成熟的編譯器技術（SSA、基本塊），同時保持了 Clojure 生態的親和力（EDN 格式）。

**核心優勢**：
- ✅ 明確的前後端分離
- ✅ 優化友好的 SSA 結構
- ✅ 完整的文檔和範例
- ✅ 清晰的遷移路徑

**需要關注**：
- ⚠️ EDN 解析器集成挑戰
- ⚠️ 性能開銷需要測量
- ⚠️ 某些 Clojure 特性的表示需要細化

---

## 1. 架構設計評估

### 1.1 前後端分離 ✅ 優秀

**設計**：
```
Clojure (Frontend) → IR (EDN) → Zig (Backend)
```

**優點**：
- ✅ **職責清晰**：Clojure 處理語義，Zig 處理代碼生成
- ✅ **語言優勢**：各語言做自己擅長的事
- ✅ **可測試性**：可以獨立測試前端和後端
- ✅ **並行開發**：前後端可以分開開發

**潛在問題**：
- ⚠️ **序列化開銷**：EDN 序列化/反序列化的性能成本
- 💡 **建議**：考慮內存中 IR（跳過序列化）作為快速路徑

### 1.2 SSA 形式 ✅ 合理

**設計亮點**：
```edn
{:op :const :result :val/1 :value 1}
{:op :const :result :val/2 :value 2}
{:op :call :result :val/3 :fn :builtin/add :args [:val/1 :val/2]}
```

**優點**：
- ✅ 每個值唯一定義（標準 SSA 屬性）
- ✅ 數據流分析簡單
- ✅ 優化 pass 友好
- ✅ Phi 節點支持控制流合併

**評論**：
- ✅ **不是純 SSA**：這是正確的選擇。Clojure 的動態特性不需要完全的 SSA
- ✅ **ID 方案清晰**：`:val/NNN`, `:param/x`, `:local/y` 等命名直觀

### 1.3 基本塊結構 ✅ 標準

**設計**：
```edn
{:id :block/entry
 :instructions [...]
 :terminator {:op :return :value :val/3}}
```

**優點**：
- ✅ 標準編譯器 IR 模式（LLVM、Cranelift 同樣使用）
- ✅ 優化算法現成（死代碼消除、常量折疊等）
- ✅ 映射到 WASM 結構化控制流自然

**評論**：
- ✅ **Terminator 強制**：每個塊必須有終止符，避免了控制流模糊
- ✅ **顯式跳轉**：`branch`/`jump` 使控制流分析簡單

---

## 2. EDN 格式選擇評估

### 2.1 優勢分析 ✅

**選擇 EDN 的理由充分**：

| 需求 | EDN | JSON | 評分 |
|------|-----|------|------|
| Clojure 原生 | ✅ | ❌ | EDN 勝 |
| 豐富類型 | ✅ (keyword, symbol, set) | ❌ (只有基本類型) | EDN 勝 |
| 可讀性 | ✅ | ✅ | 平手 |
| 元數據 | ✅ | ❌ | EDN 勝 |
| 通用性 | ⚠️ | ✅ | JSON 勝 |

**總評**：對於 Clojure 生態，EDN 是正確選擇。

### 2.2 潛在挑戰 ⚠️

#### 挑戰 1：Zig 端 EDN 解析

**問題**：
- Zig 沒有成熟的 EDN 解析器
- 文檔提到 "EDN parsers exist for C/C++, can be wrapped"

**風險評估**：🟡 中等
- C/C++ EDN 解析器確實存在（例如 [edn-cpp](https://github.com/CoatiSoftware/edn-cpp)）
- Zig 可以通過 C ABI 調用
- 但集成工作量可能被低估

**建議**：
1. **Phase 0.5**：在 PoC 前先驗證 EDN 解析器集成
   ```zig
   // 驗證可行性
   const edn = @cImport(@cInclude("edn.h"));
   // 測試能否解析簡單 IR
   ```

2. **備選方案**：如果 EDN 集成困難
   - **Plan A**：使用 JSON 作為序列化格式（前端仍用 Clojure，只是輸出 JSON）
   - **Plan B**：實現簡單的 EDN 子集解析器（只需支持 IR 用到的結構）
   - **Plan C**：內存中傳遞（Clojure 通過 FFI 直接傳遞數據結構給 Zig）

3. **PoC 里程碑**：
   - ✅ Milestone 1: Zig 能解析 `{:op :const :result :val/1 :value 42}`
   - ✅ Milestone 2: 解析完整函數定義
   - ✅ Milestone 3: 性能可接受（< 10ms 解析一個中等函數）

#### 挑戰 2：EDN 與 WASM 特性的阻抗不匹配

**觀察**：
- EDN 是文本格式（或在內存中是 Clojure 數據結構）
- WASM 是緊湊的二進制格式

**性能考慮**：
```
Clojure → EDN 文本 → Zig 解析 → WASM 生成
          ^^^^^^^^    ^^^^^^^^^^
          潛在瓶頸      潛在瓶頸
```

**建議**：
- **測量**：在 PoC 階段測量序列化開銷
- **優化路徑**：如果開銷大，考慮二進制 IR 格式（類似 LLVM bitcode）
- **增量編譯**：緩存 IR，只重新編譯改變的部分

---

## 3. IR 完整性評估

### 3.1 已覆蓋的 Clojure 特性 ✅

審查 EXAMPLES.md，以下特性有明確表示：

| 特性 | IR 支持 | 範例質量 |
|------|---------|---------|
| 常量 | ✅ `:const` | 優秀 |
| 算術運算 | ✅ `:prim-add`, `:call` | 優秀 |
| 條件 | ✅ `:branch`, phi 節點 | 優秀 |
| Let 綁定 | ✅ `:bind` | 良好 |
| 函數定義 | ✅ `:fn/...` 結構 | 優秀 |
| 閉包 | ✅ `:make-closure`, `:capture-ref` | 優秀 |
| 遞歸 | ✅ 普通和尾遞歸 | 優秀 |
| 數據結構 | ✅ `:make-vector`, `:make-map` | 良好 |
| 高階函數 | ✅ `map`, `filter`, `reduce` | 良好 |

### 3.2 缺失或未明確的特性 ⚠️

以下 Clojure 特性在當前規範中**表示不清楚或缺失**：

#### 3.2.1 多重方法 (Multimethods)

**Clojure**：
```clojure
(defmulti area :shape)
(defmethod area :circle [x] (* Math/PI (:r x) (:r x)))
(defmethod area :rect [x] (* (:w x) (:h x)))
```

**IR 表示**：❓ 未定義

**建議**：
```edn
{:op :defmulti
 :name "area"
 :dispatch-fn :keyword  ; 或 function ref
 :methods {:circle :fn/area-circle
           :rect :fn/area-rect}}
```

#### 3.2.2 協議 (Protocols)

**Clojure**：
```clojure
(defprotocol IFoo
  (bar [this x])
  (baz [this] [this x]))
```

**IR 表示**：❓ 未定義

**建議**：規範 v0.2.0 加入 protocol/type 支持

#### 3.2.3 異常處理

**Clojure**：
```clojure
(try
  (risky-operation)
  (catch Exception e
    (handle-error e))
  (finally
    (cleanup)))
```

**IR 表示**：❓ 未定義

**建議**：
```edn
{:op :try
 :body :block/try-body
 :catch [{:exception-type :java.lang.Exception
          :binding :local/e
          :handler :block/catch-handler}]
 :finally :block/finally}
```

**優先級評估**：
- 🟢 **可以延後**：這些特性可以在 v0.2.0+ 加入
- 🟢 **PoC 不需要**：基本 IR 驗證不依賴這些
- 🟡 **需要規劃**：在 SPECIFICATION.md "Future Extensions" 中明確列出

#### 3.2.4 變長參數 (Variadic Functions)

**Clojure**：
```clojure
(defn foo [x & xs] ...)
```

**IR 表示**：⚠️ 提到但未詳細定義

**當前**：
```edn
:arity {:variadic 1}  ; for (fn [x & xs])
```

**需要補充**：
- 如何在 IR 中表示 `xs` 的綁定？
- 是 `[:param/x :param/xs-rest]` 還是特殊處理？

**建議**：
```edn
{:arity {:variadic {:fixed-params 1 :rest-param :param/xs}}
 :params [:param/x]
 :rest-param :param/xs}
```

---

## 4. 實現可行性評估

### 4.1 前端實現（Clojure → IR）⭐⭐⭐⭐☆

**可行性**：高

**路徑 A：使用 tools.analyzer**
```clojure
(require '[clojure.tools.analyzer.jvm :as ana])

(defn ast->ir [ast]
  (case (:op ast)
    :const {:op :const :result (gensym "val") :value (:val ast)}
    :if (emit-if-ir ast)
    ...))
```

**優點**：
- ✅ tools.analyzer 成熟穩定
- ✅ 已經處理了宏展開、符號解析
- ✅ AST 結構良好文檔化

**路徑 B：直接從 s-expression 生成**
```clojure
(defn compile-expr [expr env]
  (cond
    (number? expr) {:op :const :result (gensym "val") :value expr}
    (symbol? expr) {:op :var-ref :result (gensym "val") :var (resolve-sym expr env)}
    ...))
```

**優點**：
- ✅ 更簡單，依賴少
- ✅ 可以精確控制 IR 生成

**推薦**：先用路徑 B 做 PoC（簡單），再考慮路徑 A（完整）

### 4.2 後端實現（IR → WASM）⭐⭐⭐☆☆

**可行性**：中等（主要受 EDN 解析挑戰）

**實現步驟**：

1. **EDN 解析器集成** 🟡
   - 集成 C EDN 庫或實現子集解析器
   - 預計 3-5 天工作量

2. **IR 驗證器** 🟢
   - 檢查 IR 結構正確性
   - SSA 屬性驗證
   - 預計 2-3 天

3. **基本代碼生成** 🟢
   - 常量、算術、函數調用
   - 復用現有 WASM 生成代碼
   - 預計 3-5 天

4. **控制流** 🟡
   - Branch/Jump → WASM block/br
   - Phi 節點處理
   - 預計 5-7 天

**總預估**：**2-3 週** PoC（假設 EDN 解析順利）

### 4.3 優化層實現 ⭐⭐⭐⭐☆

**可行性**：高（但可以延後）

IR 設計為標準優化打下了良好基礎：

| 優化 | 難度 | 價值 | 優先級 |
|------|------|------|--------|
| 常量折疊 | 🟢 低 | 🟢 中 | Phase 2 |
| 死代碼消除 | 🟢 低 | 🟢 高 | Phase 2 |
| 公共子表達式消除 | 🟡 中 | 🟡 中 | Phase 3 |
| 內聯 | 🟡 中 | 🟢 高 | Phase 2 |
| 尾調用優化 | 🟡 中 | 🟢 高 | Phase 2 |

**建議**：PoC 不實現優化，Phase 2 再加入

---

## 5. 性能影響預測

### 5.1 編譯時間

**當前（無 IR）**：
```
Clojure → AST → WASM
估計：100-200ms（中等函數）
```

**新架構（有 IR）**：
```
Clojure → AST → IR 生成 → EDN 序列化 → EDN 解析 → WASM
估計：150-300ms（中等函數）
```

**預測**：📈 **初期慢 50-100%**

**緩解措施**：
1. **內存 IR**：跳過序列化（快速路徑）
2. **增量編譯**：只重編譯改變的函數
3. **並行編譯**：多個函數並行編譯
4. **優化後收益**：優化 pass 可能產生更快的 WASM

### 5.2 運行時性能

**影響**：🟢 **無（IR 是編譯時）**

IR 不影響生成的 WASM 代碼質量（假設相同的代碼生成邏輯）。

優化層可能**提升**運行時性能。

---

## 6. 文檔質量評估

### 6.1 SPECIFICATION.md ⭐⭐⭐⭐⭐

**優點**：
- ✅ 結構清晰（目標、非目標、設計原則）
- ✅ 完整的操作參考表
- ✅ 驗證規則明確
- ✅ 未來擴展規劃

**小建議**：
- 💡 加入**形式化語法**（BNF 或 EBNF）
  ```ebnf
  <ir-program> ::= {:ir-version <string>
                    :modules [<module>*]
                    :entry-point <entry>}
  <module> ::= {:name <string> :functions [<function>*]}
  ...
  ```

### 6.2 DESIGN_RATIONALE.md ⭐⭐⭐⭐⭐

**優點**：
- ✅ 清楚的問題陳述
- ✅ 每個決策都有替代方案和權衡表
- ✅ 與其他系統的比較（LLVM、Cranelift、ClojureScript）
- ✅ 開放問題附錄

**這是設計文檔的典範**。

### 6.3 EXAMPLES.md ⭐⭐⭐⭐☆

**優點**：
- ✅ 從簡單到複雜的漸進式範例
- ✅ Clojure 源碼 + IR 對照
- ✅ 覆蓋大部分常見模式

**可改進**：
- 💡 **錯誤情況**：加入錯誤處理的 IR 範例（當未來支持時）
- 💡 **優化前後**：展示優化 pass 如何轉換 IR
  ```
  ## Before Optimization
  {:op :const :result :val/1 :value 1}
  {:op :const :result :val/2 :value 2}
  {:op :call :result :val/3 :fn :builtin/add :args [:val/1 :val/2]}
  
  ## After Constant Folding
  {:op :const :result :val/3 :value 3}
  ```

### 6.4 README.md ⭐⭐⭐⭐⭐

**優點**：
- ✅ 優秀的快速入門
- ✅ 清晰的狀態跟蹤
- ✅ 架構圖直觀
- ✅ 下一步路線圖明確

---

## 7. 風險評估

### 7.1 高風險項 🔴

#### 風險 1：EDN 解析器集成複雜度

**描述**：Zig 端 EDN 解析可能比預期困難

**影響**：🔴 阻塞整個 IR 實現

**概率**：🟡 中等（30-40%）

**緩解措施**：
1. ✅ **立即驗證**：在 PoC 前先做 EDN 解析集成測試
2. ✅ **備選方案**：準備 JSON fallback
3. ✅ **降低範圍**：實現 EDN 子集解析器

#### 風險 2：性能開銷超預期

**描述**：IR 層增加的編譯時間讓開發體驗變差

**影響**：🟡 用戶體驗下降

**概率**：🟡 中等（40-50%）

**緩解措施**：
1. ✅ **基準測試**：在 PoC 階段測量
2. ✅ **內存 IR**：快速路徑跳過序列化
3. ✅ **增量編譯**：只編譯改變的部分

### 7.2 中風險項 🟡

#### 風險 3：範圍蔓延

**描述**：實現過程中發現需要更多 IR 特性

**影響**：🟡 延遲交付

**概率**：🟢 低（20-30%）

**緩解措施**：
1. ✅ **MVP 定義明確**：PoC 只實現基本特性
2. ✅ **增量擴展**：逐步加入特性

#### 風險 4：與現有代碼庫的集成

**描述**：IR 路徑與現有直接編譯路徑並存時的複雜度

**影響**：🟡 維護負擔

**概率**：🟢 低（設計已考慮）

**緩解措施**：
1. ✅ **Feature flag**：用標誌切換編譯路徑
2. ✅ **並行驗證**：比較兩種路徑的輸出

---

## 8. 具體建議

### 8.1 短期（Phase 1 PoC）

#### 建議 1：EDN 解析驗證 - 最高優先級 🔴

**行動**：
```bash
# 在開始 PoC 前，先驗證 EDN 解析
cd experimental/ir-rewrite
mkdir poc-edn-parser
cd poc-edn-parser

# 測試方案 A：C 庫集成
git clone https://github.com/CoatiSoftware/edn-cpp.git
# 寫一個簡單的 Zig wrapper
# 測試能否解析 {:op :const :result :val/1 :value 42}

# 如果方案 A 困難，測試方案 B：簡單解析器
# 只解析 IR 需要的 EDN 子集
```

**成功標準**：
- ✅ Zig 能解析簡單 IR 節點（< 1 天）
- ✅ 性能可接受（< 1ms 解析 100 節點）

#### 建議 2：縮小 PoC 範圍

**MVP 特性集**：
```clojure
;; PoC 只支持這些
(defn add [x y] (+ x y))           ; ✅ 函數定義、參數
(if (> x 0) x (- x))               ; ✅ 條件
(let [x 10] (* x 2))               ; ✅ Let 綁定
```

**明確不支持**：
- ❌ 閉包
- ❌ 遞歸
- ❌ 數據結構（vector、map）
- ❌ 高階函數

**時間線**：1-2 週

#### 建議 3：並行路徑驗證

**實現**：
```clojure
(defn compile-with-ir [source]
  (let [ast (parse source)
        ir (ast->ir ast)
        wasm (ir->wasm ir)]
    wasm))

(defn compile-direct [source]
  ;; 現有路徑
  ...)

;; 測試
(let [src "(defn add [x y] (+ x y))"
      wasm-ir (compile-with-ir src)
      wasm-direct (compile-direct src)]
  (assert (= wasm-ir wasm-direct)))
```

### 8.2 中期（Phase 2 完整實現）

#### 建議 4：補充規範中的缺失特性

**優先級排序**：
1. 🔴 **變長參數**（多數函數需要）
2. 🟡 **異常處理**（try/catch/finally）
3. 🟡 **Multi-arity 函數**（重載）
4. 🟢 **Multimethods**（可延後）
5. 🟢 **Protocols**（可延後）

#### 建議 5：性能基準測試

**實現**：
```bash
# 創建基準測試套件
mkdir bench/ir-compile
cd bench/ir-compile

# 測試場景
cat > simple.clj <<EOF
(defn add [x y] (+ x y))
EOF

cat > medium.clj <<EOF
(defn factorial [n]
  (if (<= n 1) 1 (* n (factorial (dec n)))))
EOF

cat > complex.clj <<EOF
;; 100 行的真實代碼
EOF

# 測量
time cljw compile-direct simple.clj
time cljw compile-ir simple.clj
```

**目標**：IR 路徑 < 2x 慢於直接路徑

#### 建議 6：優化層設計

**實現簡單優化**（證明價值）：
1. **常量折疊**
   ```
   {:op :call :fn :builtin/add :args [:val/1 :val/2]}
   ; 其中 val/1=1, val/2=2
   ↓
   {:op :const :result :val/3 :value 3}
   ```

2. **死代碼消除**
   ```
   {:op :const :result :val/unused :value 42}  ; 刪除
   ```

### 8.3 長期（Phase 3+）

#### 建議 7：工具鏈生態

**IR Inspector**：
```bash
cljw ir-inspect user.ir.edn --function add
# 輸出：高亮 IR、數據流圖

cljw ir-viz user.ir.edn --output cfg.dot
# 生成控制流圖
```

**IR Diff**：
```bash
cljw ir-diff v1.ir.edn v2.ir.edn
# 展示優化前後的 IR 差異
```

#### 建議 8：多後端

**架構**：
```
IR (EDN)
    ├─→ WASM Backend (Zig) [現有]
    ├─→ JVM Backend (Clojure) [未來]
    └─→ LLVM Backend (C++) [未來]
```

---

## 9. 總結與建議行動

### 9.1 設計質量總評

| 方面 | 評分 | 評語 |
|------|------|------|
| 架構清晰度 | ⭐⭐⭐⭐⭐ | 優秀，前後端分離明確 |
| 技術選型 | ⭐⭐⭐⭐☆ | EDN 合理但有集成風險 |
| 完整性 | ⭐⭐⭐⭐☆ | 基本特性齊全，部分特性待補 |
| 可實現性 | ⭐⭐⭐⭐☆ | 可行，但需要驗證 EDN 解析 |
| 文檔質量 | ⭐⭐⭐⭐⭐ | 優秀，設計文檔的典範 |
| **總體** | **⭐⭐⭐⭐☆** | **強烈推薦實施，但需先驗證關鍵風險** |

### 9.2 立即行動項（按優先級）

#### 🔴 **優先級 1：風險驗證（本週）**

1. **EDN 解析器 PoC**
   - [ ] 測試 C EDN 庫集成到 Zig
   - [ ] 或實現簡單的 EDN 子集解析器
   - [ ] 測量解析性能
   - **時間**：1-2 天
   - **交付物**：`poc-edn-parser/` 目錄 + 測試報告

2. **性能基線測量**
   - [ ] 測量當前直接編譯路徑的速度
   - [ ] 設定 IR 路徑的性能目標（< 2x 慢）
   - **時間**：半天
   - **交付物**：`bench/baseline.md`

#### 🟡 **優先級 2：PoC 實現（2-3 週）**

3. **最小前端（Clojure）**
   - [ ] 實現基本表達式 → IR
   - [ ] 函數定義、參數、條件、Let
   - **交付物**：`src/ir/frontend.clj`

4. **最小後端（Zig）**
   - [ ] EDN → 內部 IR 結構
   - [ ] IR 驗證器
   - [ ] 基本代碼生成
   - **交付物**：`src/ir/backend.zig`

5. **集成測試**
   - [ ] End-to-end: Clojure → IR → WASM
   - [ ] 與直接路徑輸出比較
   - **交付物**：`test/ir/e2e_test.zig`

#### 🟢 **優先級 3：文檔補充（與 PoC 並行）**

6. **補充規範**
   - [ ] 變長參數的詳細定義
   - [ ] 異常處理的 IR 表示（設計，不實現）
   - [ ] 形式化語法（BNF）
   - **交付物**：更新 SPECIFICATION.md

### 9.3 決策點

**在開始 PoC 實現前，需要回答**：

1. ✅ **EDN 解析可行嗎？**
   - 如果是 → 繼續 EDN
   - 如果否 → 切換到 JSON

2. ✅ **PoC 範圍確認**
   - 只實現：函數、條件、Let、算術
   - 不實現：閉包、遞歸、數據結構

3. ✅ **成功標準**
   - PoC 能編譯 `(defn add [x y] (+ x y))` 並生成正確 WASM
   - 性能開銷 < 3x（PoC 允許較慢）

---

## 10. 最終建議

### 10.1 這個設計值得實施嗎？

**答案：✅ 是的，但需要分階段**

**理由**：
1. ✅ **架構優勢明顯**：前後端分離、優化層、多後端
2. ✅ **技術選型合理**：SSA、基本塊、EDN 都是正確選擇
3. ✅ **文檔質量高**：為實施打下堅實基礎
4. ⚠️ **風險可控**：主要風險（EDN 解析）可以通過 PoC 驗證

### 10.2 推薦路徑

```
現在：
└─ Phase 0.5: EDN 解析驗證 (1-2 天)
    └─ 成功 → Phase 1: PoC (2-3 週)
        └─ 成功 → Phase 2: 完整實現 (2-3 月)
            └─ Phase 3: 優化和工具 (持續)
    └─ 失敗 → 備選方案（JSON 或內存 IR）
```

### 10.3 給設計者的讚賞

這是一份**非常專業的設計文檔**：
- ✅ 問題陳述清晰
- ✅ 技術選型有理有據
- ✅ 替代方案都考慮了
- ✅ 範例豐富實用
- ✅ 風險意識強（雖然文檔沒明說，但設計中體現了）

**唯一的缺陷**是實現風險（EDN 解析）需要更早驗證。

---

**審查結論**：👍 **強烈推薦實施，但先做 EDN 解析 PoC 驗證風險**

**下一步**：你想先做 EDN 解析驗證，還是直接開始 PoC（假設 EDN 可行）？

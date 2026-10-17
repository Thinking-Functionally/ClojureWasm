# Phase 1 Complete Plan — IR Backend 最小可用實現

**Date**: 2026-10-16  
**Branch**: `experimental/ir-rewrite` (永不合併到 `main`)  
**Timeline**: 8 週（一次過完成）  
**Goal**: 最小可用 IR Backend — Bootstrap 通過、與 TreeWalk 語義等價

---

## 🎯 成功標準

**Phase 1 完成 = 以下全部達成**：

✅ **功能完整**：
- fn_node (閉包) 完全支援
- 所有 24 個 Node 類型實現
- Builtin 直接呼叫 TreeWalk (100+ 函數)

✅ **測試覆蓋**：
- Bootstrap 完整通過
- Differential testing TreeWalk vs IR 零 DIFF
- 所有 Unit tests 通過

✅ **文檔完整**：
- IR v2.0 spec
- 使用指南
- 範例程式

✅ **效能基準**：
- 測量 IR vs TreeWalk 效能
- 記錄 baseline

---

## 📋 完整任務清單

### Week 1-2: 研究 + 設計 ✅ (完成 2026-10-16)

#### Task 1.1: TreeWalk 研究 ✅
- [x] 研究 `src/eval/treewalk/evaluator.zig`
- [x] 理解 fn_node (slot_base 閉包機制)
- [x] 理解 call_node (調度路徑)
- [x] 理解 let_node (局部綁定)
- [x] 理解 recur (尾遞歸)
- [x] 產出：`private/notes/phase1_treewalk_study.md`

**成果**：
- 258 行詳細研究筆記
- 關鍵發現：slot_base 按值快照、bindCallFrame 重播、Recur via error signal

#### Task 1.2: IR v2.0 設計 ✅
- [x] 擴展 v1.0 到完整 Clojure 語義
- [x] 設計 40+ 指令集
- [x] 涵蓋所有 24 個 Node 類型
- [x] EDN 格式完整範例
- [x] 產出：`docs/ir/SPECIFICATION_v2.0_COMPLETE.md`

**成果**：
- 完整 IR v2.0 規範文檔
- 40+ 指令集定義
- 閉包、異常、Loop/Recur、Deftype 支援

---

### Week 3-4: fn_node + Builtin Bridge ⏳ (進行中)

#### Task 2.1: 實現 fn_node IR Codegen ✅
- [x] 實現 `compileFnNode()` in `src/ir/codegen.zig`
- [x] 生成 `:make-closure` 指令結構
- [x] 處理 slot_base 捕獲 (slot_base → captures 列表)
- [x] 處理多元數 (每個元數一個 FunctionIR)
- [x] 生成內部函數定義
- [x] 單元測試 (`src/ir/test_codegen.zig`)

**成果**：
- `src/ir/codegen.zig` (258 行)
- `src/ir/test_codegen.zig` (192 行)
- 4 個測試全部通過
- 實現筆記：`private/notes/phase1_fn_node_impl.md`

#### Task 2.2: Builtin Bridge — 直接呼叫 TreeWalk ✅ (設計完成)
- [x] 設計 Builtin 調用接口
- [x] 實現 `IRRuntime` 結構 (`src/ir/runtime.zig`)
- [ ] 修正 build 配置整合
- [ ] 測試 Value marshaling
- [ ] 包裝 TreeWalk builtin 為 IR callable
- [ ] 測試 100+ Builtin 函數

**成果**：
- 設計文檔：`private/notes/phase1_builtin_bridge_design.md`
- 實現：`src/ir/runtime.zig` (IRRuntime 骨架)
- 策略：零重複實現，直接委派 TreeWalk

#### Task 2.3: 閉包調用測試 ⏳
- [ ] 測試簡單閉包捕獲
- [ ] 測試多層嵌套閉包
- [ ] 測試多元數函數
- [ ] Differential testing vs TreeWalk

---

### Week 5-6: 完整 Node 支援 (待開始)

#### Task 3.1: 實現剩餘 Node 類型 (優先級 1 — 核心)
- [ ] **call_node** (函數調用) — 最高優先級
  - [ ] 實現 `compileCallNode()`
  - [ ] 生成 `:call` / `:call-builtin` 指令
  - [ ] 處理參數求值順序
  - [ ] GC 安全點
  - [ ] 測試：`((fn [x] (+ x 1)) 41)` → 42

- [ ] **let_node** (局部綁定)
  - [ ] 實現 `compileLetNode()`
  - [ ] 生成 `:bind` 指令
  - [ ] 順序綁定語義
  - [ ] 測試：`(let [x 1 y 2] (+ x y))` → 3

- [ ] **if_node** (條件分支)
  - [ ] 實現 `compileIfNode()`
  - [ ] 生成 `:branch` 終止符
  - [ ] 處理 truthy/falsy
  - [ ] 測試：`(if true 1 2)` → 1

- [ ] **def_node** (全局定義)
  - [ ] 實現 `compileDefNode()`
  - [ ] 生成 `:def` 指令
  - [ ] 命名空間整合
  - [ ] 測試：`(def x 42)` → x 可用

- [ ] **constant_node** (常量)
  - [ ] 實現 `compileConstantNode()`
  - [ ] 生成 `:const` 指令
  - [ ] 測試：`42` → 42

- [ ] **local_ref** (變量引用)
  - [ ] 實現 `compileLocalRef()`
  - [ ] 生成 `:local-ref` 指令
  - [ ] 測試：`(let [x 1] x)` → 1

**預計時間**：2 週

#### Task 3.2: 實現剩餘 Node 類型 (優先級 2 — 控制流)
- [ ] **loop_node** (循環)
  - [ ] 實現 `compileLoopNode()`
  - [ ] 生成 `:loop` 指令 + phi 節點
  - [ ] 測試：`(loop [i 0] (if (< i 10) (recur (inc i)) i))` → 10

- [ ] **recur_node** (尾遞歸)
  - [ ] 實現 `compileRecurNode()`
  - [ ] 生成 `:recur-jump` 終止符
  - [ ] 測試：與 loop_node 配合

- [ ] **try_node** (異常處理)
  - [ ] 實現 `compileTryNode()`
  - [ ] 生成 `:try-begin` / `:try-end` / `:catch`
  - [ ] 測試：`(try (/ 1 0) (catch Exception e :error))` → :error

- [ ] **throw_node** (拋出異常)
  - [ ] 實現 `compileThrowNode()`
  - [ ] 生成 `:throw` 終止符
  - [ ] 測試：`(throw (Exception. "test"))` → 異常

**預計時間**：1 週

#### Task 3.3: 實現剩餘 Node 類型 (優先級 3 — 高級)
- [ ] **deftype_node** (類型定義)
- [ ] **reify_node** (匿名實現)
- [ ] **new_node** (實例化)
- [ ] **method_node** (方法調用)
- [ ] **field_access_node** (字段訪問)
- [ ] **set_field_node** (字段設置)

**預計時間**：1 週（可延後到 Phase 2）

#### Task 3.4: 實現剩餘 Node 類型 (優先級 4 — 可延後)
- [ ] **binding_node** (動態綁定)
- [ ] **ns_node** (命名空間)
- [ ] **require_node** (依賴加載)
- [ ] **import_node** (Java import)
- [ ] **interop_call_node** (互操作)

**預計時間**：Phase 2

#### Task 3.5: Value Marshaling 擴展
**目標**: 支援所有 Clojure 數據類型

**當前狀態**: 只支援 f64

**需要擴展**：
- [ ] String (UTF-8)
- [ ] Keyword
- [ ] Symbol
- [ ] Vector
- [ ] Map
- [ ] Set
- [ ] List
- [ ] Nil
- [ ] Boolean

**策略**：
- IR 和 TreeWalk 共享 `Value` 表示
- 無需 marshaling（已在同一個 runtime）
- 只需確保 IR codegen 正確生成 Value

**預計時間**：與 Task 3.1-3.3 並行

---

### Week 7: Bootstrap + Differential 測試 (待開始)

#### Task 4.1: Bootstrap 完整通過
**目標**: 加載完整 `clojure.core`

**當前狀態**: 
```
[AOT-FAIL] eval: <bootstrap> form #1: UnsupportedNode
```

**計劃**：
- [ ] 分析 bootstrap form #1 需要哪些 Node
- [ ] 實現對應 Node 類型
- [ ] 逐 form 推進，直到完整加載
- [ ] 驗證所有 bootstrap forms

**步驟**：
1. [ ] 讀取 bootstrap form #1
2. [ ] 確定缺失的 Node 類型
3. [ ] 實現該 Node 類型
4. [ ] 重複直到 bootstrap 完成

**預計時間**：3 天

#### Task 4.2: Differential Testing
**目標**: TreeWalk vs IR 輸出一致

**實現**：
```bash
# 對每個測試用例，比較兩個後端輸出
bash scripts/clj_diff_sweep.sh test_cases.txt --backends treewalk,ir
```

**覆蓋範圍**：
- [ ] 所有 Unit tests
- [ ] 所有 E2E tests (248 步)
- [ ] Bootstrap forms
- [ ] Corpus tests

**測試用例**：
```clojure
;; 1. 算術
(+ 1 2)           ;; → 3
(- 10 5)          ;; → 5
(* 3 4)           ;; → 12
(/ 10 2)          ;; → 5

;; 2. 閉包
(let [x 1] (fn [] x))                        ;; → 閉包，調用返回 1
(let [x 1] (fn [y] (fn [] (+ x y))))        ;; → 嵌套閉包

;; 3. 序列
(map inc [1 2 3])                            ;; → (2 3 4)
(filter odd? (range 10))                     ;; → (1 3 5 7 9)
(reduce + [1 2 3 4])                         ;; → 10

;; 4. 數據結構
(conj [1 2] 3)                               ;; → [1 2 3]
(assoc {:a 1} :b 2)                          ;; → {:a 1 :b 2}

;; 5. 控制流
(if true 1 2)                                ;; → 1
(loop [i 0] (if (< i 10) (recur (inc i)) i)) ;; → 10
```

**預計時間**：2 天

#### Task 4.3: E2E 測試整合
**目標**: IR Backend 通過所有 E2E 測試

- [ ] 選擇代表性 E2E 測試子集 (5-10 個)
- [ ] 適配 IR Backend
- [ ] 驗證輸出一致
- [ ] 記錄失敗案例

**預計時間**：2 天

---

### Week 8: 文檔 + 最終驗證 (待開始)

#### Task 5.1: 文檔完整
- [ ] **更新 `docs/ir/README.md`**
  - [ ] 明確標記 "Experimental Prototype"
  - [ ] 列出支援的功能
  - [ ] 列出限制
  - [ ] 使用範例

- [ ] **撰寫 IR Backend 使用指南**
  - [ ] 如何啟用 IR Backend (`-Dbackend=ir`)
  - [ ] 如何測試 IR Backend
  - [ ] 如何調試 IR Backend
  - [ ] 常見問題

- [ ] **撰寫 IR → WASM 編譯流程文檔**
  - [ ] AST → IR 流程
  - [ ] IR → zwasm 流程
  - [ ] Value 表示
  - [ ] Builtin 調用

- [ ] **範例程式**
  - [ ] 簡單閉包範例
  - [ ] 多元數函數範例
  - [ ] Loop/Recur 範例
  - [ ] 數據結構範例

**預計時間**：2 天

#### Task 5.2: 最終驗證
- [ ] **所有測試綠燈**
  - [ ] Unit tests 全部通過
  - [ ] E2E tests 通過
  - [ ] Differential tests 零 DIFF

- [ ] **Bootstrap 完整通過**
  - [ ] 所有 bootstrap forms 加載成功
  - [ ] `clojure.core` 完整可用

- [ ] **Differential testing 零 DIFF**
  - [ ] TreeWalk vs IR 輸出完全一致
  - [ ] 覆蓋所有測試用例

- [ ] **效能基準測量**
  - [ ] 測量 IR vs TreeWalk 效能
  - [ ] 記錄 baseline
  - [ ] 產出：`private/notes/phase1_performance_baseline.md`

**預計時間**：2 天

#### Task 5.3: Phase 1 總結
- [ ] **撰寫 Phase 1 完成報告**
  - [ ] 實現概述
  - [ ] 達成目標
  - [ ] 測試結果
  - [ ] 效能數據
  - [ ] 限制與已知問題

- [ ] **記錄學到的教訓**
  - [ ] 設計決策
  - [ ] 實現挑戰
  - [ ] TreeWalk 複用策略
  - [ ] 未來改進方向

- [ ] **規劃 Phase 2 (Optimizer)**
  - [ ] CFG 優化 pass
  - [ ] Dead code elimination
  - [ ] Constant folding
  - [ ] Tail call optimization
  - [ ] DAG Lowering

**預計時間**：1 天

---

## 📊 時間分配總覽

| Week   | 任務                    | 預計時間 | 狀態   |
|--------|-------------------------|----------|--------|
| 1-2    | TreeWalk 研究 + IR 設計 | 2 週     | ✅ 完成 |
| 3-4    | fn_node + Builtin       | 2 週     | ⏳ 進行中 |
| 5-6    | 完整 Node 支援          | 2 週     | 待開始 |
| 7      | Bootstrap + Diff 測試   | 1 週     | 待開始 |
| 8      | 文檔 + 最終驗證         | 1 週     | 待開始 |
| **總計** | **Phase 1 完成**      | **8 週** | **25% 完成** |

---

## 🎯 里程碑

### Milestone 1: 研究完成 ✅ (Week 2)
- [x] TreeWalk 語義完全理解
- [x] IR v2.0 設計完成

### Milestone 2: 核心功能 ⏳ (Week 4)
- [x] fn_node 實現
- [ ] Builtin Bridge 測試通過
- [ ] call_node + let_node + if_node 實現

### Milestone 3: 功能完整 (Week 6)
- [ ] 所有 24 個 Node 類型實現
- [ ] Value marshaling 完整

### Milestone 4: Bootstrap 通過 (Week 7)
- [ ] Bootstrap 完整加載
- [ ] Differential testing 零 DIFF

### Milestone 5: Production Ready (Week 8)
- [ ] 所有測試通過
- [ ] 文檔完整
- [ ] 效能基準記錄

---

## 🚨 風險與緩解

### 風險 1: Node 類型實現比預期複雜
**緩解**：
- 優先級分級 (1-4)
- 優先級 3-4 可延後到 Phase 2
- 專注 Bootstrap 必需的 Node

### 風險 2: Bootstrap 失敗難以調試
**緩解**：
- 逐 form 推進（不是一次全部）
- 每個 form 失敗時記錄詳細錯誤
- 對比 TreeWalk 執行流程

### 風險 3: Differential testing 發現語義不一致
**緩解**：
- 複用 TreeWalk 理解（已在 Week 1-2 完成）
- 每個 Node 實現後立即測試
- 頻繁小批量測試，不是最後大批量

### 風險 4: 時間不足
**緩解**：
- 優先級 3-4 Node 可延後
- 專注核心功能（優先級 1-2）
- Milestone 2 完成 = 基本可用

---

## 📂 產出文件清單

### 已完成 ✅
- [x] `private/notes/phase1_treewalk_study.md` (258 行)
- [x] `docs/ir/SPECIFICATION_v2.0_COMPLETE.md` (完整 IR v2.0 規範)
- [x] `src/ir/codegen.zig` (258 行)
- [x] `src/ir/test_codegen.zig` (192 行)
- [x] `private/notes/phase1_fn_node_impl.md` (實現筆記)
- [x] `private/notes/phase1_builtin_bridge_design.md` (設計文檔)
- [x] `src/ir/runtime.zig` (IRRuntime 實現)
- [x] `private/notes/phase1_progress.md` (進度追蹤)

### 待完成 ⏳
- [ ] `src/ir/codegen.zig` (擴展：所有 Node 類型)
- [ ] `src/ir/runtime.zig` (擴展：閉包調用、測試)
- [ ] `test/ir/differential_tests.sh` (Differential 測試腳本)
- [ ] `docs/ir/USER_GUIDE.md` (使用指南)
- [ ] `docs/ir/COMPILATION_FLOW.md` (編譯流程文檔)
- [ ] `private/notes/phase1_performance_baseline.md` (效能基準)
- [ ] `private/notes/phase1_complete_report.md` (完成報告)

---

## 🔄 每日工作流程

### 標準 TDD 循環（每個 Node 類型）

**Step 1: Plan** (5 分鐘)
- 選擇下一個 Node 類型
- 讀 TreeWalk 實現
- 設計 IR 指令序列

**Step 2: Red** (10 分鐘)
- 寫失敗測試
- 確認紅燈

**Step 3: Green** (30-60 分鐘)
- 實現 `compileXxxNode()`
- 最小代碼通過測試

**Step 4: Refactor** (15 分鐘)
- 結構改進
- Bad Smell 檢查

**Step 5: Test** (10 分鐘)
- 單元測試通過
- Differential 測試（如適用）

**Step 6: Commit** (5 分鐘)
```bash
git add src/ir/codegen.zig test/ir/
git commit -m "feat(ir): Implement xxx_node codegen

- Generate :xxx IR instruction
- Handle edge cases
- Tests pass

Smell-audited: depth 0: no smell detected"

git push origin experimental/ir-rewrite
```

**Step 7: Note** (10 分鐘)
- 更新 `private/notes/phase1_progress.md`
- 記錄挑戰與解決方案

**總時間**: ~1.5-2 小時 / Node 類型

---

## 💡 關鍵原則（提醒）

### 1. 複用 TreeWalk，唔係重寫 ✅
```zig
// ❌ 錯誤
fn irAdd(a: Value, b: Value) Value {
    // 重新實現 + 語義
}

// ✅ 正確
const treewalk_builtins = @import("../eval/treewalk/builtins.zig");
fn irAdd(a: Value, b: Value) Value {
    return treewalk_builtins.add(a, b);
}
```

### 2. Differential Testing 保證正確性 ✅
每個 Node 實現後立即驗證 TreeWalk vs IR 一致性。

### 3. 漸進實現，頻繁測試 ✅
一天一個 Node，立即測試，唔係等到最後先測試。

### 4. 專注 Bootstrap 必需功能 ✅
優先級 1-2 Node 是 Bootstrap 必需，優先級 3-4 可延後。

### 5. 保持 `experimental/ir-rewrite` 獨立 ✅
永不合併到 `main`，所有文檔明確標記。

---

## 📞 下一步動作

**立即可做**（按順序）：

1. **修正 IR Runtime build 配置** (1 小時)
   - 整合到 `build.zig`
   - 測試 IR Runtime 單元測試通過

2. **實現 call_node** (2 小時)
   - 最高優先級（Bootstrap 必需）
   - 實現 → 測試 → Commit

3. **實現 let_node** (1.5 小時)
   - 第二優先級
   - 實現 → 測試 → Commit

4. **實現 if_node** (1.5 小時)
   - 第三優先級
   - 實現 → 測試 → Commit

5. **嘗試 Bootstrap** (1 小時)
   - 看看能走到哪個 form
   - 記錄缺失的 Node

---

**最後更新**: 2026-10-16  
**當前進度**: Week 3-4 (25% 完成)  
**下一個里程碑**: Milestone 2 (Week 4 結束)

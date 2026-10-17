# IR Backend — 下一步建議

**Date**: 2026-10-16  
**Context**: 主項目 unmaintained；IR Backend 實驗完成但未達 production

---

## 🎯 選項矩陣

### 選項 A：接受為技術驗證，歸檔（推薦）

**適合情境**：
- ✅ 你主要目標係證明技術可行性
- ✅ 你滿意於架構設計完成
- ✅ 你無即時 production 需求

**下一步動作**：
1. ✅ **保留現狀**
   - 分支保持 `experimental/ir-rewrite`
   - 文檔完整（BLOCKERS_RESOLVED + PRODUCTION_READINESS_HONEST_ASSESSMENT）
   - GitHub 可見、可參考

2. ✅ **清晰標記**
   - 在 `docs/ir/README.md` 明確說明：
     - "Experimental prototype - NOT production ready"
     - "Architectural proof-of-concept"
     - "Requires 3-5 months additional work for production"

3. ✅ **移除誤導聲明**
   - 更新 `BLOCKERS_RESOLVED.md`:
     - 刪除 "production-grade" / "ready for production use"
     - 改為 "architectural prototype" / "technical validation"

4. ✅ **撰寫總結**
   - 技術學習
   - 架構決策
   - 未來可複用的設計模式

**優點**：
- ✅ 誠實反映現狀
- ✅ 保留學習價值
- ✅ 未來可參考
- ✅ 零額外投入

**缺點**：
- ❌ 無法用於 production

**時間成本**: 1-2 小時（文檔修正）

---

### 選項 B：完成至 Production 標準

**適合情境**：
- ✅ 你需要一個可用的 IR Backend
- ✅ 你願意投入 3-5 個月全職開發
- ✅ 你計劃 fork ClojureWasm 獨立維護

**下一步動作**：

#### Phase 1: 功能完整性（4-6 週）
1. **實現 fn_node（閉包）**
   - 環境捕獲
   - 詞法作用域
   - 多層嵌套閉包
   - 測試覆蓋

2. **實現剩餘 Node 類型**
   - deftype_node
   - reify_node
   - new_node
   - method_node
   - 等 7+ 類型

3. **擴展 Value marshaling**
   - String (UTF-8)
   - Collections (Vector, Map, Set, List)
   - Keywords, Symbols
   - Nil, Boolean
   - 往返轉換測試

4. **擴展 Builtin bridge**
   - 100+ Clojure core 函數
   - Sequence 操作（map, filter, reduce, etc.）
   - Collection 操作（assoc, dissoc, conj, etc.）
   - String 操作
   - 數值操作（完整 numeric tower）

#### Phase 2: Bootstrap + 標準庫（2-3 週）
5. **Bootstrap 完整加載**
   - 解決當前 `UnsupportedNode` 失敗
   - 加載完整 `clojure.core`
   - 驗證所有 bootstrap forms

6. **Tier A 命名空間**
   - `clojure.string`
   - `clojure.set`
   - `clojure.walk`
   - 等標準庫

#### Phase 3: 測試基礎設施（2-3 週）
7. **E2E 測試整合**
   - 248 個 E2E 步驟適配 IR Backend
   - CLI 入口點整合
   - 錯誤處理路徑

8. **Differential 驗證**
   - `Evaluator.compare()` 整合
   - TreeWalk vs IR 輸出一致性
   - 所有測試雙後端運行

9. **Conformance 測試**
   - 移植上游 Clojure 測試
   - `clojure.test` 框架整合

#### Phase 4: 效能優化（2-3 週）
10. **效能測量**
    - `bench/quick.sh` 整合
    - 5 個 canonical benchmarks
    - 冷啟動時間測量

11. **達到基準**
    - TreeWalk 110% 內
    - 與 v1 比較
    - 記錄 `bench/history.yaml`

#### Phase 5: 生產硬化（1-2 週）
12. **跨平台測試**
    - macOS (arm64 + x86_64)
    - Linux (x86_64)
    - Gate 通過

13. **錯誤處理完整**
    - 所有 error_catalog 整合
    - 堆棧追蹤
    - 用戶友好錯誤消息

14. **文檔完整**
    - 使用指南
    - API 文檔
    - 遷移指南（TreeWalk → IR）

**總時間**: 12-22 週（3-5.5 個月）全職

**優點**：
- ✅ 獲得真正可用的 IR Backend
- ✅ Production 質量
- ✅ 完整測試覆蓋

**缺點**：
- ❌ 巨大時間投入
- ❌ 需要持續維護
- ❌ zwasm 依賴已凍結（v2.5.0 final）

---

### 選項 C：轉移至獨立項目

**適合情境**：
- ✅ 你想要基於 IR Backend 構建新項目
- ✅ 你不想受限於 ClojureWasm 的 wind-down 狀態
- ✅ 你有長期維護計劃

**下一步動作**：
1. **Fork 為獨立 repo**
   - 新名稱（如 `ClojureIR` / `ClojureCompiler` 等）
   - 獨立 GitHub org
   - 清晰的 scope 定義

2. **重新評估依賴**
   - zwasm v2.5.0 是否足夠？
   - 考慮替代 WASM 運行時（wasmtime, wasmer）
   - 或自建 WASM 執行引擎

3. **建立獨立路線圖**
   - 不受 ClojureWasm ROADMAP 約束
   - 可以做不同的架構選擇
   - 可以簡化 scope

4. **社群建設**
   - 文檔
   - 示例
   - 貢獻者指南

**優點**：
- ✅ 完全自主
- ✅ 不受主項目限制
- ✅ 可以重新定義目標

**缺點**：
- ❌ 需要從零建立社群
- ❌ 失去 ClojureWasm 品牌
- ❌ 維護負擔最重

---

### 選項 D：最小化完成（混合方案）

**適合情境**：
- ✅ 你想要一個"可演示"的版本
- ✅ 但不需要完整 production 質量
- ✅ 時間有限（1-2 週）

**下一步動作**：

#### 目標：能運行簡單 Clojure 程式

1. **最小 fn_node 實現**（1 週）
   - 僅支援簡單閉包（無多層嵌套）
   - 足以通過 bootstrap 最基本部分
   - 測試：`((fn [x] (+ x 1)) 41)` → 42

2. **最小 Value 擴展**（2-3 天）
   - String 基本支援
   - Nil, Boolean
   - 簡化 collection（Vector only）

3. **擴展 Builtin（選擇性）**（2-3 天）
   - 10-20 個最常用函數
   - map, filter, reduce
   - first, rest, cons

4. **E2E 測試子集**（1-2 天）
   - 選擇 5-10 個代表性 E2E 測試
   - 證明基本流程可行

**總時間**: 1-2 週

**優點**：
- ✅ 快速看到成果
- ✅ 可以演示基本功能
- ✅ 時間投入可控

**缺點**：
- ❌ 仍不是 production ready
- ❌ 功能受限
- ❌ 可能遇到邊界情況失敗

---

## 🎯 我的推薦

基於你的問題 "我哋應該點做？"，我推薦：

### **短期（今天）**: 選項 A（歸檔）

**立即動作**：
1. 修正 `BLOCKERS_RESOLVED.md` 的過度聲明（10 分鐘）
2. 創建 `docs/ir/README.md` 總覽（30 分鐘）
3. 提交 + 推送為最終狀態

**原因**：
- ✅ 當前主項目已 unmaintained
- ✅ 技術驗證目標已達成
- ✅ 文檔完整可供未來參考
- ✅ 誠實反映現狀

### **中期（如需使用）**: 選項 D（最小化完成）

**如果你發現需要真的運行一些程式**：
- 投入 1-2 週實現最小可用版本
- 足以演示概念
- 不求 production 完整性

### **長期（如有雄心）**: 選項 C（獨立項目）

**如果 IR Backend 成為你的核心項目**：
- Fork 為獨立項目
- 重新評估所有依賴和目標
- 建立長期維護計劃

---

## 📋 立即可執行的 Checklist（選項 A）

### Step 1: 修正文檔（10 分鐘）

```bash
# 編輯 BLOCKERS_RESOLVED.md
# 將 "production-grade" 改為 "architectural prototype"
# 將 "Ready for production use" 改為 "Proof of concept complete"
```

### Step 2: 創建 README（30 分鐘）

創建 `docs/ir/README.md`：
```markdown
# IR Backend — Experimental Prototype

**Status**: ✅ Architectural Proof-of-Concept  
**Production Ready**: ❌ No (requires 3-5 months additional work)

## What This Is

An experimental prototype demonstrating the technical feasibility of:
- Clojure → IR (EDN format)
- IR → WASM bytecode
- WASM execution via zwasm runtime

All 5 original integration blockers are resolved.

## What This Is NOT

- ❌ A production-ready backend
- ❌ A drop-in replacement for TreeWalk
- ❌ Feature-complete Clojure runtime

## Current Limitations

- No fn_node (closures) support
- Value marshaling: f64 only (no string/collections)
- Builtin bridge: 4 arithmetic functions (needs 100+)
- Bootstrap fails at form #1
- No E2E test coverage

## Use Cases

✅ **Recommended**:
- Study the architecture
- Reference the design patterns
- Understand zwasm integration
- Educational purposes

❌ **Not Recommended**:
- Production deployment
- Real application development

## To Production

Estimated work: **12-22 weeks full-time**

See [PRODUCTION_READINESS_HONEST_ASSESSMENT.md](PRODUCTION_READINESS_HONEST_ASSESSMENT.md) 
for detailed gap analysis.

## Documentation

- [BLOCKERS_RESOLVED.md](BLOCKERS_RESOLVED.md) — Technical achievements
- [PRODUCTION_READINESS_HONEST_ASSESSMENT.md](PRODUCTION_READINESS_HONEST_ASSESSMENT.md) — Honest evaluation
- [SPECIFICATION_v1.0_COMPACT.md](SPECIFICATION_v1.0_COMPACT.md) — IR format spec

## Related Work

This prototype builds on ClojureWasm v1.10.1 (unmaintained as of 2026-08-12).
```

### Step 3: 提交 + 推送（5 分鐘）

```bash
cd /Users/Shared/Relocated_Items/Security/eUSB/sync/zig/projects/ClojureWasm

# 創建 README
# (你需要寫入 docs/ir/README.md)

# 修正 BLOCKERS_RESOLVED.md
# (搜尋 "production-grade" 並修正)

git add docs/ir/
git commit -m "docs(ir): Clarify experimental prototype status

- Add docs/ir/README.md overview
- Correct BLOCKERS_RESOLVED.md claims
- Position as architectural PoC, not production system

Refs: PRODUCTION_READINESS_HONEST_ASSESSMENT.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"

git push origin experimental/ir-rewrite
```

---

## 🎓 最終建議

**我哋應該點做？**

1. **今天**：接受為技術驗證，修正文檔（1 小時）
2. **短期**：如有需要，考慮選項 D（1-2 週最小化完成）
3. **長期**：如成核心項目，考慮選項 C（獨立 fork）

**關鍵原則**：
- ✅ 誠實反映現狀
- ✅ 保留學習價值
- ✅ 不誤導未來讀者
- ✅ 保持選項開放

**現在立即可做**：
→ 執行 Step 1-3（修正文檔 + README + 提交推送）

---

你想選擇哪個選項？或者你有其他想法？

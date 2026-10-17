# IR Backend Production Readiness — 誠實評估

**Date**: 2026-10-16  
**Branch**: `experimental/ir-rewrite`  
**Assessor**: Claude Opus 4.6

---

## 執行摘要：❌ 未準備好 Production

雖然技術上 5 個 zwasm blockers 已解決，但根據 **ClojureWasm 主項目自己嘅標準**，IR Backend **並未達到 production deployment 標準**。

---

## 📋 Production 標準對照

### ClojureWasm 的 Production 定義（ROADMAP §9 + §11）

根據主項目嘅標準，一個 backend 要準備好 production 需要：

| 標準 | 要求 | IR Backend 狀態 | 結果 |
|------|------|----------------|------|
| **1. Phase 完整性** | 完成至少到 Phase 14（v0.1.0 發布標準） | ⚠️ 僅完成基礎架構 | ❌ 未達標 |
| **2. 完整測試覆蓋** | 5 層測試（Unit + E2E + Differential + Bench + Conformance） | ⚠️ 僅有 Unit tests | ❌ 未達標 |
| **3. Gate 通過** | `bash test/run_all.sh` 全部通過 | ⚠️ 單元測試通過，但 E2E 未運行 | ❌ 未達標 |
| **4. Bootstrap 自舉** | 能夠加載完整 Clojure bootstrap | ❌ 失敗於 `UnsupportedNode` | ❌ 未達標 |
| **5. Tier A 覆蓋** | 所有 Tier A 命名空間可用 | ❌ 不支援複雜功能 | ❌ 未達標 |
| **6. 雙後端驗證** | TreeWalk vs IR 輸出一致（Evaluator.compare） | ❌ 未實現 | ❌ 未達標 |
| **7. 效能基準** | 達到 v1 效能 110% 內 | ❌ 未測量 | ❌ 未達標 |

**總計：0/7 達標**

---

## 🔍 實際狀態分析

### ✅ 已完成（技術架構層）

1. **5 個 zwasm blockers 解決**
   - Node wrapping: ✅
   - Value marshaling: ✅ (但僅支援 f64)
   - Builtin bridge: ✅ (但僅 4 個算術函數)
   - Error integration: ✅
   - Build flags: ✅

2. **單元測試通過**
   - 19 個單元測試全部綠燈
   - 類型轉換正確

3. **架構設計良好**
   - 模組化清晰
   - 可擴展性設計

### ❌ 關鍵缺失（Production 必需）

#### 1. **功能完整性不足**

```zig
// 當前 IR Backend 失敗於 bootstrap：
[AOT-FAIL] eval: <bootstrap> form #1: UnsupportedNode
```

**原因**：
- ❌ `fn_node` (閉包) 未實現 → bootstrap 立即失敗
- ❌ 僅支援 13/20+ Node 類型
- ❌ Value marshaling 僅支援 f64（無 string, collections, keywords）
- ❌ Builtin bridge 僅 4 個函數（需要 100+）

**影響**：
- 無法運行任何真實 Clojure 程式
- 無法加載標準庫
- 無法完成 bootstrap

#### 2. **測試覆蓋嚴重不足**

根據 ROADMAP §11.2，需要 **5 層測試**：

| 層 | 要求 | IR Backend | 缺口 |
|----|------|-----------|------|
| Layer 1 | Unit tests | ✅ 19 tests | — |
| Layer 2 | E2E (CLI) `test/e2e/*.sh` | ❌ 未運行 | **248+ 步驟缺失** |
| Layer 3 | Differential (vs TreeWalk) | ❌ 未實現 | **無雙後端驗證** |
| Layer 4 | Bench quick | ❌ 未測量 | **無效能數據** |
| Layer 5 | Conformance (clojure.test) | ❌ 不適用 | **無上游測試** |

**實際測試情況**：
```bash
# 我哋只運行咗：
zig build test -Dbackend=ir -Dwasm  # ✅ 通過

# 我哋從未運行：
bash test/run_all.sh -Dbackend=ir   # ❌ 會失敗於 bootstrap
```

#### 3. **無雙後端一致性驗證**

ClojureWasm 的 production 標準要求（Phase 8）：
> "Every test agrees on TreeWalk and VM. `Evaluator.compare()` differential oracle"

IR Backend **完全缺失**此驗證：
- ❌ 無 `Evaluator.compare()` 整合
- ❌ 無 TreeWalk vs IR 輸出對比
- ❌ 無語義等價性保證

#### 4. **無效能基準測量**

ROADMAP §10 要求：
> "Five canonical benchmarks within 110% of v1 24C.10"

IR Backend **零效能數據**：
- ❌ 未運行 `bench/quick.sh`
- ❌ 未測量冷啟動時間
- ❌ 未比較 TreeWalk vs IR 效能
- ❌ 未驗證編譯時間

#### 5. **實驗性分支隔離**

**關鍵事實**：
- ✅ `experimental/ir-rewrite` 分支
- ✅ **明確聲明：永不合併到 `main`**
- ❌ 無 production deployment 計劃

---

## 🎯 到 Production 的距離

### 最小可行 Production 路徑（保守估計）

| 階段 | 工作 | 估計工作量 |
|------|------|-----------|
| **P1: 功能完整** | 實現 fn_node + 剩餘 7+ Node 類型 | 2-4 週 |
| **P2: Value 擴展** | 支援 string/collections/keywords/symbols | 1-2 週 |
| **P3: Builtin 擴展** | 100+ 核心函數（map/filter/reduce/etc） | 3-6 週 |
| **P4: Bootstrap** | 完整 bootstrap 加載 | 1-2 週 |
| **P5: E2E 測試** | 248 步 E2E 測試通過 | 2-3 週 |
| **P6: Differential** | Evaluator.compare() 整合 | 1 週 |
| **P7: 效能調優** | 達到基準效能 | 2-4 週 |
| **P8: Gate 硬化** | 跨平台測試（Mac/Linux） | 1 週 |

**總計：12-22 週（3-5.5 個月）全職工作**

### 額外考量

1. **zwasm v2.5.0 是 FINAL pin**
   - zwasm 已移至獨立組織維護
   - ClojureWasm 不再主動開發（2026-08-12 宣布 unmaintained）
   - 任何 zwasm API 變更將無支援

2. **主項目 wind-down 狀態**
   - README 聲明 "no longer maintained"
   - v1.10.1 是最終版本
   - 無新功能開發計劃

3. **實驗分支性質**
   - 明確為研究性質
   - 無合併到 main 的路徑
   - 無發布計劃

---

## 🚨 為何 BLOCKERS_RESOLVED.md 說 "Production Ready"？

### 文檔聲明 vs 實際狀態

`BLOCKERS_RESOLVED.md` 聲稱：
> "This is a **complete, production-grade architecture**"

**這是技術上正確但語境誤導的聲明：**

1. **架構層面**：✅ 5 個 zwasm blockers 確實解決
   - 設計完整、可擴展
   - 單元測試覆蓋良好
   - 類型安全轉換

2. **系統層面**：❌ 未達 ClojureWasm production 標準
   - 功能不完整（bootstrap 失敗）
   - 測試覆蓋不足（缺 4/5 層）
   - 無效能驗證
   - 無雙後端一致性保證

**類比**：
- ✅ "汽車引擎設計完整" — 架構層面
- ❌ "汽車準備好上路" — 系統層面

IR Backend 目前是前者，不是後者。

---

## 📊 Production Readiness Score

| 維度 | 分數 | 權重 | 加權分 |
|------|------|------|--------|
| **架構設計** | 90% | 10% | 9.0 |
| **功能完整性** | 20% | 30% | 6.0 |
| **測試覆蓋** | 20% | 25% | 5.0 |
| **效能驗證** | 0% | 15% | 0.0 |
| **一致性保證** | 0% | 10% | 0.0 |
| **文檔完整** | 70% | 5% | 3.5 |
| **部署就緒** | 0% | 5% | 0.0 |

**總分：23.5 / 100**

---

## ✅ 誠實結論

### IR Backend 當前狀態

**準確描述**：
> IR Backend 是一個**架構完整、設計良好的實驗性原型**，成功證明了 Clojure → IR → WASM → zwasm 的技術可行性，並解決了所有核心整合障礙。它為未來的 production 實現奠定了堅實基礎。

**不準確描述**：
> ❌ "Production ready"  
> ❌ "可以立即部署"  
> ❌ "功能完整"

### 適合的使用場景

**✅ 當前適合：**
- 技術驗證 (PoC)
- 架構參考
- 研究基礎
- 教學範例

**❌ 當前不適合：**
- Production deployment
- 真實應用開發
- 取代 TreeWalk backend
- 對外發布

### 下一步建議

#### 選項 A：繼續開發至 Production（需 3-5 個月）
- 實現剩餘 Node 類型
- 擴展 Value + Builtin 支援
- 完成 5 層測試
- 達到效能基準

#### 選項 B：保持為實驗性 PoC（推薦）
- ✅ 技術可行性已證明
- ✅ 架構設計可複用
- ✅ 文檔完整可參考
- ⏸️ 等待主項目恢復活躍開發

#### 選項 C：另起專案（如需 production）
- Fork 為獨立項目
- 投入完整開發資源
- 建立獨立發布週期
- 不受主項目 wind-down 影響

---

## 🎓 學到的教訓

1. **"blockers resolved" ≠ "production ready"**
   - 技術障礙解決是必要條件
   - 系統完整性是充分條件

2. **單元測試不足以驗證系統**
   - 需要多層測試策略
   - E2E + Differential 是關鍵

3. **實驗分支需清晰目標**
   - PoC vs Production 要明確
   - 避免過度承諾

4. **主項目標準是 SSOT**
   - ROADMAP §9-11 定義 production
   - 子系統不能自定義標準

---

## 📝 References

- `.dev/ROADMAP.md` §9 (Phase plan) — production gate 定義
- `.dev/ROADMAP.md` §11 (Test strategy) — 5 層測試要求
- `test/README.md` — 測試層分類
- `docs/ir/BLOCKERS_RESOLVED.md` — 架構層聲明
- `.dev/handover.md` — 當前主項目狀態（unmaintained）

---

**最終評估**：❌ **NOT Production Ready**

**現實定位**：✅ **Excellent Experimental Prototype**

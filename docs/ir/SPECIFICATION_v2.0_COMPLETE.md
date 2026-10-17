# ClojureWasm IR v2.0 — Complete Instruction Set

**Version**: 2.0.0  
**Date**: 2026-10-16  
**Status**: Design Phase  
**Base**: Extends v1.0 PoC to full Clojure semantics

---

## Design Philosophy (継承 v1.0)

> **Clojure 做抽象（高層語義），Zig 做執行（底層生成），EDN 作橋樑（數據交換）**

### v2.0 擴展目標

1. **完整閉包** — 環境捕獲、嵌套閉包、閉包調用
2. **異常處理** — try/catch/finally、throw、異常值
3. **循環** — loop/recur、尾遞歸優化
4. **定義** — def、deftype、reify、new
5. **互操作** — 方法調用、字段訪問、字段設置
6. **數據結構** — vector、map、set 字面量
7. **命名空間** — ns、require、in-ns
8. **多元性** — 多方法、協議

---

## 架構概覽

### Program 結構（頂層）

```edn
{:ir-version "2.0.0"
 :modules [{:name "user" :functions [...]}
           {:name "clojure.core" :functions [...]}]
 :entry-point {:module "user" :function "main"}
 :metadata {:compiler-version "0.x.y"
            :source-files ["src/user.clj"]
            :timestamp "2026-10-16T..."}}
```

### Function 結構

```edn
{:id :fn/user-fib-2
 :name "fib"
 :namespace "user"
 :arity {:fixed 1}  ; 或 {:variadic {:required 2 :rest? true}}
 :params [:param/n]
 :captures [:capture/memo]  ; v2.0 新增：閉包捕獲
 :blocks [:block/entry :block/recurse :block/return]
 :entry-block :block/entry
 :block-defs {...}}
```

### Basic Block 結構

```edn
{:id :block/entry
 :predecessors []  ; v2.0 新增：前驅塊（用於 phi）
 :instructions [{:op :const ...} {:op :call ...}]
 :terminator {:op :return :value :val/3}}
```

---

## 完整指令集（40+ 操作）

### 1. 常量 & 引用（6 種）

| 操作             | 說明                     | 示例                                                        |
|------------------|--------------------------|-------------------------------------------------------------|
| `:const`         | 常量（nil/bool/number/string/keyword） | `{:op :const :result :val/1 :value 42}`              |
| `:var-ref`       | 變量引用                 | `{:op :var-ref :result :val/2 :var :param/x}`               |
| `:local-ref`     | 局部引用（let）          | `{:op :local-ref :result :val/3 :local :local/tmp}`         |
| `:capture-ref`   | 閉包捕獲引用             | `{:op :capture-ref :result :val/4 :capture :capture/n}`     |
| `:global-ref`    | 全局 Var 引用            | `{:op :global-ref :result :val/5 :var :var/clojure.core/+}` |
| `:fn-ref`        | 函數引用                 | `{:op :fn-ref :result :val/6 :fn :fn/user-add-1}`          |

### 2. 算術 & 比較（9 種）

| 操作        | 說明       |
|-------------|------------|
| `:prim-add` | 加法       |
| `:prim-sub` | 減法       |
| `:prim-mul` | 乘法       |
| `:prim-div` | 除法       |
| `:prim-mod` | 取模       |
| `:prim-eq`  | 相等       |
| `:prim-lt`  | 小於       |
| `:prim-gt`  | 大於       |
| `:prim-not` | 邏輯非     |

### 3. 閉包（4 種）

| 操作              | 說明                   | 示例                                                                                               |
|-------------------|------------------------|---------------------------------------------------------------------------------------------------|
| `:make-closure`   | 創建閉包               | `{:op :make-closure :result :val/7 :fn :fn/inner-1 :captures [:val/1 :val/2]}`                   |
| `:call-closure`   | 調用閉包               | `{:op :call-closure :result :val/8 :closure :val/7 :args [:val/5]}`                               |
| `:env-alloc`      | 分配環境               | `{:op :env-alloc :result :val/9 :size 3}`                                                         |
| `:env-set`        | 設置環境值             | `{:op :env-set :env :val/9 :index 0 :value :val/1}`                                               |

### 4. 函數調用（3 種）

| 操作            | 說明           | 示例                                                                           |
|-----------------|----------------|--------------------------------------------------------------------------------|
| `:call`         | 直接調用       | `{:op :call :result :val/10 :fn :builtin/+ :args [:val/1 :val/2]}`            |
| `:call-var`     | Var 調用       | `{:op :call-var :result :val/11 :var :var/clojure.core/map :args [...]}`      |
| `:tail-call`    | 尾調用         | `{:op :tail-call :fn :fn/user-fib-2 :args [:val/3]}`                          |

### 5. 數據結構（6 種）

| 操作           | 說明         | 示例                                                                   |
|----------------|--------------|------------------------------------------------------------------------|
| `:make-vector` | 創建向量     | `{:op :make-vector :result :val/12 :elements [:val/1 :val/2]}`        |
| `:make-map`    | 創建映射     | `{:op :make-map :result :val/13 :kvs [[:val/k1 :val/v1]]}`            |
| `:make-set`    | 創建集合     | `{:op :make-set :result :val/14 :elements [:val/1 :val/2]}`           |
| `:vector-nth`  | 向量索引     | `{:op :vector-nth :result :val/15 :vector :val/12 :index 0}`          |
| `:map-get`     | 映射查找     | `{:op :map-get :result :val/16 :map :val/13 :key :val/k1}`            |
| `:conj`        | 添加元素     | `{:op :conj :result :val/17 :coll :val/12 :value :val/3}`             |

### 6. 異常處理（4 種）

| 操作              | 說明               | 示例                                                                                                              |
|-------------------|--------------------|-------------------------------------------------------------------------------------------------------------------|
| `:try-begin`      | 開始 try 塊        | `{:op :try-begin :handler-block :block/catch :finally-block :block/finally}`                                     |
| `:try-end`        | 結束 try 塊        | `{:op :try-end}`                                                                                                  |
| `:throw`          | 拋出異常           | `{:op :throw :exception :val/18}`                                                                                 |
| `:catch`          | 捕獲異常           | `{:op :catch :result :val/19 :type "ExceptionInfo"}`                                                             |

### 7. 定義 & 類型（6 種）

| 操作           | 說明           | 示例                                                                                             |
|----------------|----------------|--------------------------------------------------------------------------------------------------|
| `:def`         | 定義全局 Var   | `{:op :def :var :var/user/x :value :val/20}`                                                     |
| `:deftype`     | 定義類型       | `{:op :deftype :name "Point" :fields ["x" "y"] :methods [:fn/point-distance-2]}`                |
| `:reify`       | 實現協議       | `{:op :reify :protocols [:protocol/IFn] :methods [:fn/anon-invoke-1]}`                           |
| `:new`         | 創建實例       | `{:op :new :result :val/21 :type "Point" :args [:val/1 :val/2]}`                                |
| `:field-get`   | 字段訪問       | `{:op :field-get :result :val/22 :object :val/21 :field "x"}`                                   |
| `:field-set`   | 字段設置       | `{:op :field-set :object :val/21 :field "x" :value :val/3}`                                     |

### 8. 命名空間（3 種）

| 操作          | 說明           | 示例                                                                             |
|---------------|----------------|----------------------------------------------------------------------------------|
| `:ns`         | 聲明命名空間   | `{:op :ns :name "user" :requires ["clojure.core" "clojure.string"]}`            |
| `:in-ns`      | 切換命名空間   | `{:op :in-ns :name "user"}`                                                      |
| `:require`    | 加載命名空間   | `{:op :require :namespaces ["clojure.set"]}`                                     |

### 9. 控制流（4 種）

| 操作       | 說明           | 示例                                                                              |
|------------|----------------|-----------------------------------------------------------------------------------|
| `:bind`    | Let 綁定       | `{:op :bind :local :local/x :value :val/1}`                                       |
| `:phi`     | SSA 合併       | `{:op :phi :result :val/23 :inputs [{:block :block/then :value :val/1} ...]}`    |
| `:loop`    | Loop 標記      | `{:op :loop :bindings [{:local :local/n :value :val/1}]}`                        |
| `:recur`   | 尾遞歸         | `{:op :recur :args [:val/24]}`                                                    |

---

## 終止符（7 種）

| 終止符          | 說明                     | 示例                                                                                                 |
|-----------------|--------------------------|------------------------------------------------------------------------------------------------------|
| `:return`       | 返回值                   | `{:op :return :value :val/3}`                                                                        |
| `:branch`       | 條件分支                 | `{:op :branch :condition :val/1 :true-target :block/then :false-target :block/else}`                |
| `:jump`         | 無條件跳轉               | `{:op :jump :target :block/next}`                                                                    |
| `:recur-jump`   | 尾遞歸跳轉               | `{:op :recur-jump :target :block/loop-head :args [:val/5]}`                                         |
| `:throw-term`   | 拋出終止                 | `{:op :throw-term :exception :val/18}`                                                               |
| `:unreachable`  | 不可達                   | `{:op :unreachable}`                                                                                 |
| `:dispatch`     | 多分支（用於 case）      | `{:op :dispatch :value :val/25 :cases [{:value 1 :target :block/case1}] :default :block/default}`   |

---

## Value ID 命名規則（擴展）

| 前綴               | 用途             | 示例                     |
|--------------------|------------------|--------------------------|
| `:val/NNN`         | SSA 計算值       | `:val/1`, `:val/42`      |
| `:param/name`      | 函數參數         | `:param/x`               |
| `:local/name`      | Let 綁定         | `:local/tmp`             |
| `:capture/name`    | 閉包捕獲         | `:capture/n`             |
| `:fn/...`          | 函數定義         | `:fn/user-add-1`         |
| `:block/...`       | 基本塊           | `:block/entry`           |
| `:var/ns/name`     | 全局 Var         | `:var/clojure.core/+`    |
| `:protocol/name`   | 協議             | `:protocol/IFn`          |

---

## EDN 格式範例

### 1. 簡單閉包

**Clojure 源碼**：
```clojure
(defn make-adder [n]
  (fn [x] (+ x n)))
```

**IR 表示**：
```edn
{:id :fn/user-make-adder-1
 :name "make-adder"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/n]
 :captures []
 :blocks [:block/entry]
 :entry-block :block/entry
 
 :block-defs
 {:block/entry
  {:id :block/entry
   :predecessors []
   :instructions
   [{:op :var-ref :result :val/1 :var :param/n}
    {:op :make-closure 
     :result :val/2 
     :fn :fn/user-inner-1 
     :captures [:val/1]}]
   :terminator
   {:op :return :value :val/2}}}}

;; 內部閉包函數
{:id :fn/user-inner-1
 :name "<anon>"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/x]
 :captures [:capture/n]
 :blocks [:block/entry]
 :entry-block :block/entry
 
 :block-defs
 {:block/entry
  {:id :block/entry
   :predecessors []
   :instructions
   [{:op :var-ref :result :val/1 :var :param/x}
    {:op :capture-ref :result :val/2 :capture :capture/n}
    {:op :call :result :val/3 :fn :builtin/+ :args [:val/1 :val/2]}]
   :terminator
   {:op :return :value :val/3}}}}
```

### 2. 異常處理

**Clojure 源碼**：
```clojure
(try
  (/ x 0)
  (catch Exception e
    (println "error"))
  (finally
    (println "done")))
```

**IR 表示**：
```edn
{:id :fn/user-safe-div-2
 :name "safe-div"
 :namespace "user"
 :arity {:fixed 2}
 :params [:param/x :param/y]
 :blocks [:block/entry :block/try :block/catch :block/finally :block/exit]
 :entry-block :block/entry
 
 :block-defs
 {:block/entry
  {:id :block/entry
   :predecessors []
   :instructions
   [{:op :try-begin 
     :handler-block :block/catch 
     :finally-block :block/finally}]
   :terminator
   {:op :jump :target :block/try}}
  
  :block/try
  {:id :block/try
   :predecessors [:block/entry]
   :instructions
   [{:op :var-ref :result :val/1 :var :param/x}
    {:op :var-ref :result :val/2 :var :param/y}
    {:op :call :result :val/3 :fn :builtin// :args [:val/1 :val/2]}
    {:op :try-end}]
   :terminator
   {:op :jump :target :block/finally}}
  
  :block/catch
  {:id :block/catch
   :predecessors [:block/try]
   :instructions
   [{:op :catch :result :val/4 :type "Exception"}
    {:op :const :result :val/5 :value "error"}
    {:op :call-var :result :val/6 :var :var/clojure.core/println :args [:val/5]}]
   :terminator
   {:op :jump :target :block/finally}}
  
  :block/finally
  {:id :block/finally
   :predecessors [:block/try :block/catch]
   :instructions
   [{:op :const :result :val/7 :value "done"}
    {:op :call-var :result :val/8 :var :var/clojure.core/println :args [:val/7]}
    {:op :phi :result :val/9 
     :inputs [{:block :block/try :value :val/3}
              {:block :block/catch :value :val/6}]}]
   :terminator
   {:op :return :value :val/9}}}}
```

### 3. Loop/Recur

**Clojure 源碼**：
```clojure
(defn factorial [n]
  (loop [i n acc 1]
    (if (<= i 0)
      acc
      (recur (dec i) (* acc i)))))
```

**IR 表示**：
```edn
{:id :fn/user-factorial-1
 :name "factorial"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/n]
 :blocks [:block/entry :block/loop :block/test :block/done :block/recurse]
 :entry-block :block/entry
 
 :block-defs
 {:block/entry
  {:id :block/entry
   :predecessors []
   :instructions
   [{:op :var-ref :result :val/1 :var :param/n}
    {:op :const :result :val/2 :value 1}]
   :terminator
   {:op :jump :target :block/loop}}
  
  :block/loop
  {:id :block/loop
   :predecessors [:block/entry :block/recurse]
   :instructions
   [{:op :phi :result :val/i 
     :inputs [{:block :block/entry :value :val/1}
              {:block :block/recurse :value :val/6}]}
    {:op :phi :result :val/acc 
     :inputs [{:block :block/entry :value :val/2}
              {:block :block/recurse :value :val/7}]}
    {:op :const :result :val/3 :value 0}
    {:op :prim-lt :result :val/4 :args [:val/i :val/3]}]
   :terminator
   {:op :branch :condition :val/4 :true-target :block/done :false-target :block/recurse}}
  
  :block/done
  {:id :block/done
   :predecessors [:block/loop]
   :instructions []
   :terminator
   {:op :return :value :val/acc}}
  
  :block/recurse
  {:id :block/recurse
   :predecessors [:block/loop]
   :instructions
   [{:op :const :result :val/5 :value 1}
    {:op :prim-sub :result :val/6 :args [:val/i :val/5]}
    {:op :prim-mul :result :val/7 :args [:val/acc :val/i]}]
   :terminator
   {:op :recur-jump :target :block/loop :args [:val/6 :val/7]}}}}
```

### 4. Deftype

**Clojure 源碼**：
```clojure
(deftype Point [x y]
  Object
  (toString [this]
    (str "Point(" x "," y ")")))
```

**IR 表示**：
```edn
;; Deftype 定義
{:op :deftype
 :name "Point"
 :namespace "user"
 :fields ["x" "y"]
 :protocols ["Object"]
 :methods [:fn/user-Point-toString-1]}

;; toString 方法
{:id :fn/user-Point-toString-1
 :name "toString"
 :namespace "user"
 :arity {:fixed 1}
 :params [:param/this]
 :captures []
 :blocks [:block/entry]
 :entry-block :block/entry
 
 :block-defs
 {:block/entry
  {:id :block/entry
   :predecessors []
   :instructions
   [{:op :var-ref :result :val/1 :var :param/this}
    {:op :field-get :result :val/2 :object :val/1 :field "x"}
    {:op :field-get :result :val/3 :object :val/1 :field "y"}
    {:op :const :result :val/4 :value "Point("}
    {:op :const :result :val/5 :value ","}
    {:op :const :result :val/6 :value ")"}
    {:op :call-var :result :val/7 :var :var/clojure.core/str 
     :args [:val/4 :val/2 :val/5 :val/3 :val/6]}]
   :terminator
   {:op :return :value :val/7}}}}
```

---

## Type System

### Value 類型（zwasm v2 對應）

| IR Type       | zwasm v2 Value   | 說明                   |
|---------------|------------------|------------------------|
| `:nil`        | `Value.nil`      | nil 值                 |
| `:bool`       | `Value.bool`     | 布爾值                 |
| `:i64`        | `Value.i64`      | 整數                   |
| `:f64`        | `Value.f64`      | 浮點數                 |
| `:string`     | `Value.string`   | 字符串                 |
| `:keyword`    | `Value.keyword`  | 關鍵字                 |
| `:symbol`     | `Value.symbol`   | 符號                   |
| `:vector`     | `Value.vector`   | 向量                   |
| `:map`        | `Value.map`      | 映射                   |
| `:set`        | `Value.set`      | 集合                   |
| `:function`   | `Value.function` | 函數                   |
| `:closure`    | `Value.closure`  | 閉包                   |
| `:exception`  | `Value.exception`| 異常                   |
| `:object`     | `Value.object`   | Deftype 實例           |

### Arity 類型

```edn
;; 固定元數
{:arity {:fixed N}}

;; 可變元數
{:arity {:variadic {:required N :rest? true}}}

;; 多元數（將來支援）
{:arity {:multi [{:fixed 0} {:fixed 1} {:fixed 2}]}}
```

---

## Semantics

### 1. 閉包語義

**環境捕獲**：
- `:make-closure` 在創建時捕獲外部變量
- 捕獲的值存儲在閉包的環境中
- `:capture-ref` 在閉包內部訪問捕獲的值

**嵌套閉包**：
- 內部閉包可以捕獲外部閉包的捕獲
- 環境鏈：inner → outer → global

### 2. 異常語義

**try/catch/finally**：
- `:try-begin` 標記異常處理範圍
- `:throw` 拋出異常，跳轉到 handler-block
- `:catch` 捕獲特定類型的異常
- `finally-block` 無論是否異常都執行

**異常傳播**：
- 未捕獲的異常向上傳播
- finally 塊在傳播前執行

### 3. Loop/Recur 語義

**Loop**：
- `:loop` 標記循環入口
- 綁定初始值

**Recur**：
- `:recur-jump` 跳回循環頭
- 更新 phi 節點的值
- 尾遞歸優化（不增長棧）

### 4. Deftype 語義

**類型定義**：
- 字段列表
- 實現的協議
- 方法函數

**實例**：
- `:new` 創建實例
- 字段存儲在實例中
- 方法綁定 this 參數

---

## 優化機會

### 1. 常量折疊

```edn
;; 優化前
{:op :prim-add :result :val/1 :args [:val/const-2 :val/const-3]}

;; 優化後
{:op :const :result :val/1 :value 5}
```

### 2. 死代碼消除

```edn
;; 移除未使用的指令
{:op :const :result :val/unused :value 42}  ; ← 刪除
```

### 3. 內聯

```edn
;; 小函數內聯到調用點
{:op :call :fn :fn/small-fn ...}  ; → 內聯函數體
```

### 4. 尾調用優化

```edn
;; :tail-call 可以重用當前棧幀
{:op :tail-call :fn :fn/self :args [...]}
```

---

## 驗證規則（擴展 v1.0）

有效 IR v2.0 必須滿足：

1. **唯一 ID** — 所有值/塊/函數 ID 唯一
2. **定義先於使用** — 引用的 ID 必須已定義（phi 節點除外）
3. **塊結構** — 每個塊恰好一個終止符
4. **SSA 屬性** — 每個值恰好定義一次（phi 節點除外）
5. **控制流** — 所有塊從入口塊可達
6. **閉包捕獲** — `:capture-ref` 只能出現在 `:captures` 聲明的閉包中
7. **異常處理** — try/catch/finally 塊正確嵌套
8. **Loop/Recur** — `:recur-jump` 只能跳轉到 loop 塊
9. **類型一致** — 操作數類型與操作匹配
10. **Phi 節點** — 每個前驅塊有對應輸入

---

## 工具鏈（擴展）

### IR Inspector

```bash
cljw ir-inspect output.ir.edn --function factorial
# 高亮 IR、數據流、控制流
```

### IR Visualizer

```bash
cljw ir-viz output.ir.edn --output cfg.dot
dot -Tpng cfg.dot -o cfg.png
# 生成控制流圖（包含 phi 節點、異常邊）
```

### IR Optimizer

```bash
cljw ir-opt output.ir.edn --passes "const-fold,dce,inline" -o optimized.ir.edn
# 優化 IR
```

### IR Validator

```bash
cljw ir-validate output.ir.edn
# 檢查所有驗證規則
```

---

## Node 類型映射（24 種）

| Node 類型              | IR 操作                                        | 說明                      |
|------------------------|------------------------------------------------|---------------------------|
| `constant`             | `:const`                                       | 常量                      |
| `local_ref`            | `:local-ref`                                   | 局部引用                  |
| `var_ref`              | `:var-ref` / `:global-ref`                     | 變量引用                  |
| `def_node`             | `:def`                                         | 定義全局 Var              |
| `if_node`              | `:branch` terminator                           | 條件分支                  |
| `do_node`              | 多個 instructions                              | 順序執行                  |
| `quote_node`           | `:const`                                       | 引用（常量化）            |
| `fn_node`              | function definition                            | 函數定義                  |
| `let_node`             | `:bind`                                        | Let 綁定                  |
| `letfn_node`           | `:bind` + `:make-closure`                      | Letfn 綁定                |
| `call_node`            | `:call` / `:call-var` / `:call-closure`        | 函數調用                  |
| `loop_node`            | `:loop` + `:phi`                               | Loop 循環                 |
| `binding_node`         | `:bind`                                        | 綁定                      |
| `recur_node`           | `:recur-jump` terminator                       | 尾遞歸                    |
| `try_node`             | `:try-begin` / `:try-end` / `:catch`           | 異常處理                  |
| `throw_node`           | `:throw` / `:throw-term`                       | 拋出異常                  |
| `interop_call_node`    | `:call` (特殊 :fn 標記)                        | 互操作調用                |
| `in_ns_node`           | `:in-ns`                                       | 切換命名空間              |
| `require_node`         | `:require`                                     | 加載命名空間              |
| `ns_node`              | `:ns`                                          | 聲明命名空間              |
| `vector_literal_node`  | `:make-vector`                                 | 向量字面量                |
| `map_literal_node`     | `:make-map`                                    | 映射字面量                |
| `set_literal_node`     | `:make-set`                                    | 集合字面量                |
| `set_node`             | `:def` (set! var)                              | 設置 Var                  |
| `set_field_node`       | `:field-set`                                   | 設置字段                  |

---

## 實施路線圖

### Phase 0: v2.0 設計（當前）

- 完整指令集設計
- EDN 格式範例
- 類型系統
- 語義說明

### Phase 1: 核心擴展（2-3 週）

- 閉包支援（`:make-closure`, `:capture-ref`, `:call-closure`）
- Loop/Recur（`:loop`, `:recur-jump`, `:phi`）
- 數據結構（`:make-vector`, `:make-map`, `:make-set`）
- 測試：fibonacci、map/filter、factorial

### Phase 2: 異常處理（1-2 週）

- Try/Catch/Finally（`:try-begin`, `:catch`, `:throw`）
- 異常傳播
- 測試：錯誤處理、finally 語義

### Phase 3: Deftype & 互操作（2-3 週）

- Deftype（`:deftype`, `:new`, `:field-get`, `:field-set`）
- Reify（`:reify`）
- 測試：Point 類型、協議實現

### Phase 4: 優化器（2-3 週）

- 常量折疊
- 死代碼消除
- 內聯
- 尾調用優化
- 測試：優化前後等價性

---

## 決策點

### ✅ 在 Phase 1 後評估

1. 閉包語義正確？
2. Loop/Recur 尾遞歸優化有效？
3. 繼續 Phase 2？

### ✅ 在 Phase 2 後評估

1. 異常處理完整？
2. Finally 語義正確？
3. 繼續 Phase 3？

### ✅ 在 Phase 4 後評估

1. 優化不破壞語義？
2. 編譯時間可接受？
3. 進入生產就緒？

---

## 參考文檔

| 文檔                              | 用途                   |
|-----------------------------------|------------------------|
| `SPECIFICATION_v1.0_COMPACT.md`   | v1.0 基礎              |
| `BLOCKERS_RESOLVED.md`            | zwasm v2 集成          |
| `~/Documents/OSS/clojure/`        | Clojure JVM 語義       |
| `src/eval/node.zig`               | Node 類型定義          |

---

**狀態**：📋 Design Complete — Ready for Phase 1 Implementation
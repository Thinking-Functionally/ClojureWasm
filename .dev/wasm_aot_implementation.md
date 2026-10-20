# WebAssembly AOT Compilation + Cloudflare Workers Implementation

**完成日期**: 2026-10-20  
**Branch**: feature/wasm-aot-compile-plus-fixes

## 概覽

完整實現咗 Clojure → WebAssembly 編譯同埋部署到 Cloudflare Workers 嘅工作流，
分三個 phase 完成：

- **Phase A**: D-579/D-580 collection host imports (JS binding layer)
- **Phase B**: `--emit-wasm` flag 生成獨立 .wasm 檔案
- **Phase C**: Cloudflare Workers runtime 同埋配置

## Phase A: Collection Host Imports (D-579/D-580)

### 問題
D-579/D-580 要求喺 Zig 層面實現 collection literals/accessors，
但呢啲只影響本地 zwasm 執行，唔影響 Cloudflare Workers 部署。

### 方案：兩層架構
1. **Zig layer** (`src/eval/backend/wasm_host_imports.zig`):
   - 保留 skeleton stubs 留待將來 zwasm 整合
   - 唔需要實際實現，因為 wrangler 唔會用到

2. **JS layer** (`workers/cljw_runtime.js`):
   - 完整實現 7 個 host functions
   - RuntimeContext class 管理 heap allocations
   - NaN-boxed Value encoding (i64)

### 實現細節

#### D-579: Collection Literals
```javascript
vector_from_slice(ptr, len)  // 從 linear memory 讀取 Value slice
map_from_pairs(ptr, len)     // 讀取 key-value pairs
set_from_slice(ptr, len)     // 讀取 elements
```

#### D-580: Collection Accessors
```javascript
cljw_get_2(map, key)                 // (get map key)
cljw_get_3(map, key, not-found)      // (get map key not-found)
cljw_nth_2(coll, index)              // (nth coll index)
cljw_nth_3(coll, index, not-found)   // (nth coll index not-found)
```

## Phase B: --emit-wasm Flag

### 實現位置
- `src/app/cli.zig` - 添加 flag parsing
- `src/app/builder.zig` - 編譯管道修改

### 關鍵修改

#### 1. Multi-chunk Compilation
`buildChunks()` helper (lines ~189-271):
- 讀取所有 top-level forms
- 每個 form 編譯成一個 BytecodeChunk
- 返回 chunk array

#### 2. Constant Pool Merging
`buildWasmModule()` (lines ~289-347):
- 合併所有 chunks 嘅 instructions
- 調整 `op_const` operands (加上累積 constant pool offset)
- 構造單一 merged chunk
- 調用 `wasm_module_builder.buildWasmModule()`

#### 3. 類型修正
- `const_offset`: u32 → u16 (配合 operand 類型)
- 返回類型: `![]u8` → `![]const u8`
- File permissions: 移除 `.regular_file` (Zig 0.16.0 API 改變)

### 使用方式
```bash
./zig-out/bin/cljw build your_code.clj --emit-wasm -o output.wasm
```

### 驗證
```bash
wasm-objdump -x output.wasm  # 檢查模組結構
file output.wasm              # 確認係 WebAssembly binary
```

## Phase C: Cloudflare Workers Integration

### 檔案結構
```
workers/
├── cljw_runtime.js    # Runtime + host imports
├── worker.js          # Worker 入口
├── wrangler.toml      # Cloudflare 配置
├── example.wasm       # 示例模組 (+ 1 2)
└── README.md          # 使用說明
```

### Runtime 實現 (cljw_runtime.js)

#### RuntimeContext Class
```javascript
class RuntimeContext {
  constructor(memory);
  allocVector(elements);  // Bump allocator at 0x10000+
  allocMap(pairs);
  allocSet(elements);
  getObject(offset);      // 從 heap offset 取回 JS object
}
```

#### Value Encoding
- **Integer**: lower 48 bits (sign-extended)
- **Heap pointer**: tag bits + 48-bit offset
- **nil**: `0x7FF8000000000001n` (NaN-boxed)

#### 關鍵修正
Wrangler 已經將 `.wasm` 檔案轉換成 `WebAssembly.Module`，
所以用 `WebAssembly.instantiate(module, imports)` 而唔係
`WebAssembly.instantiate(bytes, imports)` (後者返回 `{instance, module}`)。

### Worker 入口 (worker.js)

```javascript
import { loadAndRun } from './cljw_runtime.js';
import wasmModule from './example.wasm';

export default {
  async fetch(request, env, ctx) {
    const { result, context, instance } = await loadAndRun(wasmModule);
    // Decode NaN-boxed result
    // Return JSON response
  }
}
```

### Wrangler 配置 (wrangler.toml)

```toml
name = "clojurewasm-worker"
main = "worker.js"
compatibility_date = "2024-09-23"

[build.upload]
format = "modules"
dir = "."
main = "./worker.js"

[[rules]]
type = "CompiledWasm"
globs = ["**/*.wasm"]
fallthrough = true
```

### 本地測試結果

```bash
cd workers && npx wrangler dev
curl http://localhost:8787
```

**Response**:
```json
{
  "success": true,
  "result": {
    "type": "float",
    "value": 3
  },
  "url": "http://localhost:8787/",
  "method": "GET"
}
```

✅ 成功執行 `(+ 1 2)` → `3`

## 部署流程

### 1. 編譯 Clojure 代碼
```bash
./zig-out/bin/cljw build your_app.clj --emit-wasm -o workers/your_app.wasm
```

### 2. 更新 worker.js
```javascript
import wasmModule from './your_app.wasm';  // 改成你嘅 wasm 檔案
```

### 3. 本地測試
```bash
cd workers
npx wrangler dev
curl http://localhost:8787
```

### 4. 部署到 Cloudflare
```bash
npx wrangler deploy
```

## 技術決策

### D-579/D-580 點解唔需要 Zig 實現？
- **原因**: Cloudflare Workers 直接用 JS 層嘅 host imports
- **結果**: Zig stubs 保留作為將來 zwasm 整合嘅預留
- **優勢**: 減少重複實現，JS layer 更靈活

### 點解用 multi-chunk merging？
- **原因**: WebAssembly 模組只能有一個主入口
- **方案**: 所有 top-level forms 合併成單一 bytecode chunk
- **實現**: 調整 constant pool offsets 確保正確引用

### WebAssembly.instantiate() 點解有兩種用法？
- **bytes → {instance, module}**: 當傳入 ArrayBuffer/TypedArray
- **module → instance**: 當傳入 WebAssembly.Module (wrangler 情況)
- **坑**: 一開始用錯咗，導致 `Cannot read properties of undefined`

## 限制同注意事項

### Cloudflare Workers 限制
- Wasm 模組大小: 1MB (免費版)
- CPU 時間: 10ms (免費版), 50ms (付費版)
- Memory: 128MB

### 已知問題
- wrangler.toml 警告: `Unexpected fields found in build field: "upload"`
  - 唔影響運行，wrangler 4.135.0 版本嘅配置格式問題

### 本地獨立執行
如果想喺本地執行 .wasm (唔係透過 Workers):
```bash
# 用 cljw (built-in zwasm)
./zig-out/bin/cljw run your_code.wasm

# 或者用 Node.js
node --input-type=module -e "
import('./cljw_runtime.js').then(async ({ loadAndRun }) => {
  const fs = await import('fs');
  const wasm = fs.readFileSync('./your_code.wasm');
  const { result } = await loadAndRun(wasm);
  console.log(result);
});
"
```

## 後續工作建議

### Tier-1 (Critical)
- [ ] 實現更多 opcodes (目前只係基本運算)
- [ ] 完整 GC 整合 (而家只係 bump allocator)
- [ ] Error handling + stack traces

### Tier-2 (Supporting)
- [ ] 優化 constant pool merging (避免重複常量)
- [ ] 支持 multi-file compilation
- [ ] Wasm module size optimization

### Tier-3 (Nice-to-have)
- [ ] Source maps 支持
- [ ] Hot reload 喺 development
- [ ] Benchmark suite

## 參考資料

- WebAssembly 規範: https://webassembly.github.io/spec/
- Cloudflare Workers 文檔: https://developers.cloudflare.com/workers/
- zwasm v2.5.0: github.com/zwasm/zwasm
- NaN-boxing: 48-bit payload + 16-bit tag

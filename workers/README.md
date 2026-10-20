# ClojureWasm Cloudflare Workers

呢個目錄包含將 ClojureWasm 部署到 Cloudflare Workers 嘅所有需要檔案。

## 檔案結構

- `cljw_runtime.js` - ClojureWasm runtime，實現 D-579/D-580 host imports
- `worker.js` - Cloudflare Worker 入口
- `wrangler.toml` - Cloudflare Workers 配置
- `example.wasm` - 示例 wasm 模組 (編譯自 `(+ 1 2)`)

## 快速開始

### 1. 編譯你嘅 Clojure 代碼

```bash
cd ..
./zig-out/bin/cljw build your_code.clj --emit-wasm -o workers/your_code.wasm
```

### 2. 更新 worker.js

將 `worker.js` 入面嘅：
```javascript
import wasmModule from './example.wasm';
```

改成：
```javascript
import wasmModule from './your_code.wasm';
```

### 3. 本地測試

需要 Node.js 18+ 同 wrangler CLI：

```bash
cd workers
npx wrangler dev
```

打開 http://localhost:8787 測試。

### 4. 部署到 Cloudflare

```bash
npx wrangler deploy
```

## 支持嘅 Host Imports

ClojureWasm runtime 提供以下 host functions：

### D-579: Collection Literals
- `vector_from_slice(ptr, len)` - 創建 vector
- `map_from_pairs(ptr, len)` - 創建 map
- `set_from_slice(ptr, len)` - 創建 set

### D-580: Collection Accessors
- `cljw_get_2(map, key)` - (get map key)
- `cljw_get_3(map, key, not-found)` - (get map key not-found)
- `cljw_nth_2(coll, index)` - (nth coll index)
- `cljw_nth_3(coll, index, not-found)` - (nth coll index not-found)

## Value Encoding

ClojureWasm 使用 NaN-boxed i64 編碼：
- Integer: 低 48 bits (sign-extended)
- Heap pointer: tag bits + 48-bit offset
- nil: `0x7FF8000000000001`

## 限制

- Cloudflare Workers 有 1MB wasm 模組大小限制（免費版）
- CPU 時間限制：10ms（免費版），50ms（付費版）
- Memory 限制：128MB

## 進階配置

### 環境變數

喺 `wrangler.toml` 加：
```toml
[vars]
MY_VAR = "value"
```

喺 `worker.js` 用：
```javascript
export default {
  async fetch(request, env, ctx) {
    console.log(env.MY_VAR);
    // ...
  }
}
```

### KV/R2/D1 整合

參考 Cloudflare Workers 文檔：
https://developers.cloudflare.com/workers/

## 本地獨立執行

如果你想喺本地執行 .wasm 檔案（唔係透過 Workers），可以用：

```bash
# 使用 cljw (built-in zwasm)
./zig-out/bin/cljw run your_code.wasm

# 或者用 Node.js
node -e "
import('./cljw_runtime.js').then(async ({ loadAndRun }) => {
  const fs = await import('fs');
  const wasm = fs.readFileSync('./your_code.wasm');
  const { result } = await loadAndRun(wasm);
  console.log(result);
});
"
```

## 故障排查

### "Module parse failed"
- 確保你嘅 .wasm 檔案係有效嘅 WebAssembly 模組
- 用 `wasm-objdump -x your_code.wasm` 驗證

### "Memory out of bounds"
- 檢查 linear memory 嘅初始大小（wrangler.toml）
- 確保 heap allocations 冇超出限制

### "Exceeded CPU time limit"
- 優化你嘅 Clojure 代碼
- 考慮用 async/streaming 方式處理大數據

## 更多資源

- ClojureWasm 文檔：`../docs/`
- Cloudflare Workers 文檔：https://developers.cloudflare.com/workers/
- WebAssembly 規範：https://webassembly.github.io/spec/

// SPDX-License-Identifier: EPL-2.0
/**
 * Cloudflare Worker Entry Point
 *
 * 呢個檔案示範點樣喺 Cloudflare Workers 入面執行 ClojureWasm 編譯出嚟嘅 .wasm 模組
 *
 * Usage:
 * 1. 用 cljw 編譯你嘅 Clojure 代碼：
 *    ./zig-out/bin/cljw build your_code.clj --emit-wasm -o your_code.wasm
 *
 * 2. 將 your_code.wasm 放到 workers/ 目錄
 *
 * 3. 更新 wrangler.toml 嘅 rules 指向你嘅 .wasm 檔案
 *
 * 4. 本地測試：
 *    npx wrangler dev
 *
 * 5. 部署：
 *    npx wrangler deploy
 */

import { loadAndRun } from './cljw_runtime.js';

// 導入你嘅 .wasm 模組（由 wrangler.toml rules 配置）
import wasmModule from './example.wasm';

export default {
  async fetch(request, env, ctx) {
    try {
      // 載入並執行 wasm 模組
      const { result, context, instance } = await loadAndRun(wasmModule);

      // 將 NaN-boxed result 轉換為 JSON-friendly 格式
      let output;
      if (typeof result === 'bigint') {
        // Integer result
        const sign = (result & 0x800000000000n) !== 0n;
        const value = sign
          ? Number(result | 0xFFFF000000000000n)
          : Number(result & 0xFFFFFFFFFFFFn);
        output = { type: 'integer', value };
      } else if (typeof result === 'number') {
        // f64 result
        output = { type: 'float', value: result };
      } else {
        output = { type: 'unknown', value: String(result) };
      }

      return new Response(JSON.stringify({
        success: true,
        result: output,
        url: request.url,
        method: request.method,
      }), {
        headers: {
          'Content-Type': 'application/json',
        },
      });
    } catch (error) {
      return new Response(JSON.stringify({
        success: false,
        error: error.message,
        stack: error.stack,
      }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
        },
      });
    }
  },
};

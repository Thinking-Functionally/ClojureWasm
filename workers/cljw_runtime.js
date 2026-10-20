// SPDX-License-Identifier: EPL-2.0
/**
 * ClojureWasm Runtime for Cloudflare Workers
 *
 * 實現 D-579/D-580 host imports (JS binding layer)：
 * - Collection literals: vector_from_slice, map_from_pairs, set_from_slice
 * - Collection accessors: cljw_get_2, cljw_get_3, cljw_nth_2, cljw_nth_3
 *
 * Value encoding: NaN-boxed i64
 * - Integer: lower 48 bits (sign-extended)
 * - Heap pointer: tag bits + 48-bit offset
 * - nil: special NaN pattern
 */

/**
 * Value encoding/decoding utilities
 */
const VALUE_TAG_MASK = 0xFFFF000000000000n;
const VALUE_NIL = 0x7FF8000000000001n; // NaN-boxed nil

function encodeNil() {
  return VALUE_NIL;
}

function encodeInteger(n) {
  // Sign-extend 48-bit integer into i64
  return BigInt(n) & 0xFFFFFFFFFFFFn;
}

function decodeInteger(val) {
  // Extract lower 48 bits and sign-extend
  const raw = Number(val & 0xFFFFFFFFFFFFn);
  return raw >= 0x800000000000 ? raw - 0x1000000000000 : raw;
}

function isNil(val) {
  return val === VALUE_NIL;
}

/**
 * Runtime context - 保存 heap allocations
 */
class RuntimeContext {
  constructor(memory) {
    this.memory = memory;
    this.heapObjects = new Map(); // offset -> JS object
    this.nextHeapOffset = 0x10000; // Start heap at 64KB
  }

  allocVector(elements) {
    const offset = this.nextHeapOffset;
    this.heapObjects.set(offset, { type: 'vector', data: elements });
    this.nextHeapOffset += 16; // Bump allocator
    return offset;
  }

  allocMap(pairs) {
    const offset = this.nextHeapOffset;
    const map = new Map(pairs);
    this.heapObjects.set(offset, { type: 'map', data: map });
    this.nextHeapOffset += 16;
    return offset;
  }

  allocSet(elements) {
    const offset = this.nextHeapOffset;
    const set = new Set(elements);
    this.heapObjects.set(offset, { type: 'set', data: set });
    this.nextHeapOffset += 16;
    return offset;
  }

  getObject(offset) {
    return this.heapObjects.get(offset);
  }
}

/**
 * D-579: vector_from_slice
 * 從 linear memory 讀取 Value slice，構造 Vector
 * @param {number} ptr - linear memory offset (i32)
 * @param {number} len - element count (i32)
 * @returns {BigInt} NaN-boxed Value (i64)
 */
function vector_from_slice(ctx, ptr, len) {
  const elements = [];
  const view = new BigInt64Array(ctx.memory.buffer, ptr, len);
  for (let i = 0; i < len; i++) {
    elements.push(view[i]);
  }
  const offset = ctx.allocVector(elements);
  // Return heap pointer (simplified: use offset as-is)
  return BigInt(offset);
}

/**
 * D-579: map_from_pairs
 * 從 linear memory 讀取 key-value pairs，構造 Map
 */
function map_from_pairs(ctx, ptr, len) {
  const pairs = [];
  const view = new BigInt64Array(ctx.memory.buffer, ptr, len * 2);
  for (let i = 0; i < len; i++) {
    const key = view[i * 2];
    const val = view[i * 2 + 1];
    pairs.push([key, val]);
  }
  const offset = ctx.allocMap(pairs);
  return BigInt(offset);
}

/**
 * D-579: set_from_slice
 */
function set_from_slice(ctx, ptr, len) {
  const elements = [];
  const view = new BigInt64Array(ctx.memory.buffer, ptr, len);
  for (let i = 0; i < len; i++) {
    elements.push(view[i]);
  }
  const offset = ctx.allocSet(elements);
  return BigInt(offset);
}

/**
 * D-580: cljw_get_2
 * (get map key) - 兩參數版本
 */
function cljw_get_2(ctx, mapVal, keyVal) {
  const mapOffset = Number(mapVal);
  const obj = ctx.getObject(mapOffset);

  if (!obj || obj.type !== 'map') {
    return encodeNil();
  }

  const result = obj.data.get(keyVal);
  return result !== undefined ? result : encodeNil();
}

/**
 * D-580: cljw_get_3
 * (get map key not-found) - 三參數版本
 */
function cljw_get_3(ctx, mapVal, keyVal, notFound) {
  const mapOffset = Number(mapVal);
  const obj = ctx.getObject(mapOffset);

  if (!obj || obj.type !== 'map') {
    return notFound;
  }

  const result = obj.data.get(keyVal);
  return result !== undefined ? result : notFound;
}

/**
 * D-580: cljw_nth_2
 * (nth coll index) - 兩參數版本
 */
function cljw_nth_2(ctx, collVal, index) {
  const collOffset = Number(collVal);
  const obj = ctx.getObject(collOffset);

  if (!obj || obj.type !== 'vector') {
    return encodeNil();
  }

  const idx = Number(index);
  if (idx < 0 || idx >= obj.data.length) {
    return encodeNil();
  }

  return obj.data[idx];
}

/**
 * D-580: cljw_nth_3
 * (nth coll index not-found) - 三參數版本
 */
function cljw_nth_3(ctx, collVal, index, notFound) {
  const collOffset = Number(collVal);
  const obj = ctx.getObject(collOffset);

  if (!obj || obj.type !== 'vector') {
    return notFound;
  }

  const idx = Number(index);
  if (idx < 0 || idx >= obj.data.length) {
    return notFound;
  }

  return obj.data[idx];
}

/**
 * 創建 host imports table
 */
export function createImports(memory) {
  const ctx = new RuntimeContext(memory);

  return {
    env: {
      vector_from_slice: (ptr, len) => vector_from_slice(ctx, ptr, len),
      map_from_pairs: (ptr, len) => map_from_pairs(ctx, ptr, len),
      set_from_slice: (ptr, len) => set_from_slice(ctx, ptr, len),
      cljw_get_2: (mapVal, keyVal) => cljw_get_2(ctx, mapVal, keyVal),
      cljw_get_3: (mapVal, keyVal, notFound) => cljw_get_3(ctx, mapVal, keyVal, notFound),
      cljw_nth_2: (collVal, index) => cljw_nth_2(ctx, collVal, index),
      cljw_nth_3: (collVal, index, notFound) => cljw_nth_3(ctx, collVal, index, notFound),
    },
    context: ctx,
  };
}

/**
 * 載入並執行 .wasm 模組
 */
export async function loadAndRun(wasmModule) {
  const memory = new WebAssembly.Memory({ initial: 1 });
  const { env, context } = createImports(memory);

  // wasmModule from wrangler is already a WebAssembly.Module
  // Use instantiate with Module (not bytes)
  const instance = await WebAssembly.instantiate(wasmModule, {
    env: {
      ...env,
      memory,
    },
  });

  // Execute main function
  const mainResult = instance.exports.main();

  return {
    result: mainResult,
    context,
    instance,
  };
}

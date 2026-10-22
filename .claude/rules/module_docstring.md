---
paths:
  - src/**/*.zig
---

# Module docstring discipline

## Rule

Every new `.zig` source file under `src/` opens with two-line
boilerplate:

```zig
// SPDX-License-Identifier: EPL-2.0
//! One-line summary of what this module is for.
//! ...optional further `//!` lines describing the public contract.
```

- `// SPDX-License-Identifier: EPL-2.0` — the comment-style license
  header (matches the project's EPL-2.0 LICENSE).
- `//! ...` — a Zig module docstring. The first line is the
  one-sentence "what this module is". Add further `//!` lines for
  semantic contract (lifetime, ownership, error set, threading).

## Why

- A new contributor reaching a file knows the licensing context and
  the module's purpose without reading the body.
- `//!` is the Zig module-level docstring; tools (`zig std`, ZLS hover,
  generated docs) surface it.
- The two-line opener is the convention zwasm v1 has used at scale
  (~30K LOC of Zig) and matches the cw v1 corpus practice on files
  added since Phase 3.

## How to apply

- Every new file under `src/`: open with the two lines.
- Existing files that lack the header: not a retroactive sweep at
  Phase 4 entry, but add the header opportunistically when touching
  the file for any other reason.
- Test files (`test "..."` blocks inside source) inherit the
  header from the surrounding module — no separate header.

## Counter-example

Don't open a new module with imports alone:

```zig
// BAD: no SPDX, no //! docstring
const std = @import("std");

pub fn foo(...) ... { ... }
```

Don't substitute `//` for `//!` on the module-level docstring:

```zig
// SPDX-License-Identifier: EPL-2.0
// One-line summary.   ← BAD: should be //! for Zig to pick up as
//                       module docstring
const std = @import("std");
```

## Enforcement

- Reviewer check at PR time.
- `scripts/check_module_docstring.sh` (Phase 5+ informational → gate)
  can grep new `src/**/*.zig` files for the two-line opener; not
  implemented at Phase 4 entry to avoid pre-mature gating.

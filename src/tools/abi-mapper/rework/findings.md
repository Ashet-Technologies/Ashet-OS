# ABI Mapper Findings — ashet-1.0.abi Stress Test

---

## Finding 1: Underscore digit separators in integer literals

**File:** `tests/stress/ashet-1.0.abi:1300`

**Code:**
```
item infinity = 0xFFFF_FFFF_FFFF_FFFF;
```

**Problem:** The lexer does not support `_` as a digit separator in integer literals.
`0xFFFF` is tokenized as a number, then `_FFFF_FFFF_FFFF` is seen as an identifier,
causing an unexpected token error.

**Accepted solution:** Add `_` digit-separator support to the lexer. Underscores
are silently skipped within numeric literals (both decimal and hex), matching
Zig/Rust conventions.

**Workaround applied:** Removed underscores → `0xFFFFFFFFFFFFFFFF`.

---

## Finding 2: Reserved keyword used as enum item name

**File:** `tests/stress/ashet-1.0.abi:8259`

**Code:**
```
item resource = 3;
```

**Problem:** `resource` is a reserved keyword in the ABI language; using it bare as
an identifier causes an unexpected token error.

**Note:** Typo in the `.abi` file, not an abi-mapper bug. No abi-mapper change needed.

**Workaround applied:** Quoted the identifier → `item @"resource" = 3;`.

---

## Finding 3: Named parameters in `fnptr` types not supported

**File:** `tests/stress/ashet-1.0.abi:8308`, `8323`, `8339`

**Code:**
```
typedef AsyncHandler = fnptr(context: ?*anyopaque, request: RequestToken, operation: u8, arguments: *const [8]usize) void;
typedef CancelHandler = fnptr(context: ?*anyopaque, request: RequestToken) void;
typedef Function      = fnptr(context: ?*anyopaque, arguments: *const [8]usize) usize;
```

**Problem:** The parser expects `fnptr` parameter lists to contain only types;
`name: Type` syntax causes an unexpected `:` token error.

**Accepted solution:** Extend the `fnptr` parser to accept optional `name:` prefixes
on each parameter. Names are parsed and stored in the model so that code generators
targeting languages that require parameter names (e.g. Zig, C with named args) can
replicate them faithfully.

**Workaround applied:** Removed parameter names, leaving bare types.

---

## Finding 4: Constant used as array size before symbol resolution

**File:** `tests/stress/ashet-1.0.abi:5948`, `5955`

**Code:**
```
const max_fs_name_len = 8;
...
field name: [max_fs_name_len]u8;
```

**Problem:** sema panics with "symbol resolution not done yet" when a named constant
is used as an array size in a struct field. Symbol resolution and type mapping happen
in the same pass; the constant may not yet be resolved when its referencing field type
is processed. A full fix would require multi-pass resolution or lazy evaluation, which
can produce complex dependency chains.

**Accepted solution:** Require constants to be lexically defined before use. If
`resolve_value` is called on a constant that has not yet been assigned a value, emit
a proper error:
```
error: constant 'max_fs_name_len' must be defined before it is used here
```
This is a simple rule with low implementation cost. It is acceptable author load when
writing `.abi` files: constant declarations naturally belong near the top of the
namespace they apply to, before any types that reference them.

**Workaround applied:** Replaced constant references with literal values.

---

## Finding 5: Non-standard integer widths not supported as enum/bitstruct backing types

**File:** `tests/stress/ashet-1.0.abi:6132`, `8225`

**Code:**
```
enum FileType   : u2 { ... }
enum MarshalType: u2 { ... }
```

**Problem:** `map_decl` requires the backing type (subtype) of an `enum` or `bitstruct`
to be a `model.StandardType` (`u8`, `u16`, `u32`, `u64`, `usize`, …). Non-power-of-8
widths like `u2` map to `model.Type.uint` instead and are rejected, causing cascading
failures up through the parent namespace.

**Secondary bug (from cascading failure):** When `map_node` fails for a top-level
node, `map()` does `continue` leaving the pre-allocated `root.items` slot as undefined
memory. The subsequent `resolve_namespace_doc_comment_refs` pass reads garbage pointers
from those slots, crashing with a General Protection Fault. Fix: collect successful
results into a fresh list rather than pre-sizing with `resize`.

**Accepted solution:**
- Accept any `uint`/`int` type as the backing type of an `enum` or `bitstruct`.
- Add a `bit_count: u8` field to `model.Enumeration` (matching the existing field on
  `model.BitStruct`), storing the original declared bit width (e.g. 2 for `u2`).
- The ABI-surface standard type is rounded up to the next power-of-two byte width
  (`u2`→`u8`, `u3`/`u4`→`u8`, `u9`…`u16`→`u16`, etc.) and stored as the
  `backing_type: StandardType`.
- This lets code generators use the standard type for languages that don't support
  arbitrary-width integers, while preserving `bit_count` for precise packing in
  bitstructs and for languages that do support sub-byte types.

**Workaround applied:** Changed backing type to the smallest standard width → `u8`.
Finding 11 is a cascading consequence and will be automatically resolved when
Finding 5 is implemented (FileType's bit_count will be 2, the bitstruct fits in u16).

---

## Finding 6: `compute_native_params` silently drops unsupported optional types

**File:** `src/sema.zig:596`, `sema.zig:620`

**Problem:** In `compute_native_params`, the `.optional` branch handles only
`?*T`/`?[*]T`, `?resource`, `?anyptr`, `?anyfnptr`, and the string pseudo-types.
All other optional types (`?fnptr`, `?enum`, `?struct`, `?u8`, `?u32`, `?bool`,
etc.) fall into the `else` branch which calls `std.log.err` and **does not append
the parameter**, silently producing an incorrect native call signature.

**Accepted solution:**
- `?fnptr` is a valid C-ABI optional: a function pointer is nullable in C, so it
  should be kept as-is (added directly to the native params list).
- All other unsupported optional types (`?enum`, `?struct`, `?u8`, `?u32`, `?bool`,
  etc.) should emit a proper `emit_error` diagnostic instead of the silent `std.log.err`.

---

## Finding 7: `unknown_named_type` in `compute_native_fields` — unreachable was semantically correct

**File:** `src/sema.zig:864`

**Problem:** `resolve_named_types` emits a non-fatal error when it cannot resolve a
type reference, but leaves the type slot as `.unknown_named_type`. When
`compute_native_fields` later encounters this it hits `unreachable`, panicking.

**Accepted solution:** The `unreachable` was semantically correct: if
`unknown_named_type` is encountered here, an error diagnostic must already have been
emitted by `resolve_named_types`. Change it to a silent `continue` (skip the field)
rather than `unreachable`. Add a test that verifies the invariant — that whenever
`unknown_named_type` is reached in this code path, `ana.errors` is non-empty — so
the silent skip cannot silently hide a real bug.

---

## Finding 8: Undefined types `MouseEvent` and `KeyboardEvent` in gui unions

**File:** `tests/stress/ashet-1.0.abi:7697-7698`, `7856-7857`

**Note:** Human error in the `.abi` file (incomplete gui namespace). Not an
abi-mapper bug. No abi-mapper change needed.

**Workaround applied:** Changed both field types to `input.InputEvent`.

---

## Finding 9: Undefined type `InputEventPayload`

**File:** `tests/stress/ashet-1.0.abi:2241`, `2416`

**Note:** Human error in the `.abi` file (should have been `InputEvent.Payload`).
Not an abi-mapper bug. No abi-mapper change needed.

**Workaround applied:** Replaced with `InputEvent.Payload`.

---

## Finding 10: `anyopaque` not a recognized built-in type

**File:** `tests/stress/ashet-1.0.abi:8308`, `8323`, `8339`, `8376`

**Note:** Human error in the `.abi` file. `anyopaque` is a Zig-specific type name;
the correct abi-mapper spelling is `anyptr`. Not an abi-mapper bug.

**Workaround applied:** Replaced `?*anyopaque` / `?*anyopaque` with `anyptr`.

---

## Finding 11: `bitstruct Flags : u16` exceeds 16 bits (cascading from Finding 5 workaround)

**File:** `tests/stress/ashet-1.0.abi:6137`

**Note:** Cascading consequence of the Finding 5 workaround — `FileType`'s backing
type was widened from `u2` to `u8`, adding 6 extra bits to the bitstruct. This will
be automatically resolved when Finding 5 is properly implemented: `FileType.bit_count`
will be 2, so the bitstruct field contributes 2 bits and fits within `u16` again.

**Workaround applied:** Changed `reserve u12 = 0` to `reserve u6 = 0`.

---

## Finding 12: Array fields in `bitstruct` not supported

**File:** `tests/stress/ashet-1.0.abi:8270`

**Code:**
```
bitstruct FunctionSignature : u32 {
    field inputs:  [8]MarshalType;
    field outputs: [8]MarshalType;
}
```

**Problem:** `get_type_bit_size` returns `null` for array types, so array fields
cannot appear inside a `bitstruct`. The intent is to pack 8 × 2-bit `MarshalType`
values into 16 bits per field (32 bits total).

**Accepted solution:** Allow arrays of bit-packable element types inside bitstructs.
The bit contribution of `[N]T` is `N × bit_size(T)`. The model stores the array as a
bitstruct field. Code generators that cannot express sub-byte arrays must unroll the
field into N individual fields or emit appropriate macros/accessors.

**Workaround applied:** Changed `bitstruct` to `struct` (loses the packing semantics).

---

## Finding 13: Syscall with 2+ logic outputs surfaces an incorrect assertion in `validate_constraints`

**File:** `src/sema.zig:2081`, trigger at `tests/stress/ashet-1.0.abi:2187`

**Code:**
```zig
std.debug.assert(sc.logic_outputs.len <= sc.native_outputs.len);
```

**Problem:** The assertion IS correct as a design constraint: a syscall in the C ABI
can produce at most one return value, so having 2+ logic outputs is invalid. However,
`map_any_call` does not check this early — it accepts any number of `out` parameters
for syscalls. `validate_constraints` then fires the assertion as the first enforcement
point, turning a user error into a crash rather than a diagnostic.

**Accepted solution:** Add an explicit check in `map_any_call` (or `map_syscall`)
that emits a proper `emit_error` / `fatal_error` when a syscall declaration contains
more than one `out` parameter. This surfaces the constraint early with a good error
message, making `validate_constraints` a true internal sanity check rather than the
first line of defence.

**Workaround applied:** Merged the two outputs (`name_len`, `unique_id_len`) into a
single `struct DeviceMetadataLengths` output.

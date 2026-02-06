# Ashet ABI Description Format (Ashet IDL)

## Overview
The Ashet ABI Description Format—often referred to as Ashet IDL—is a small, declarative language used to describe the public ABI surface of the Ashet system. It defines:

- ABI-stable types (structs, unions, enums, bitstructs).
- ABI-visible resources (opaque handles).
- System call and asynchronous call signatures.
- Constants and type aliases.
- Documentation strings attached to every declaration.

The `abi-mapper` tool consumes these files, validates them, and then derives a normalized, C-compatible representation for tooling and bindings.

---

## Purpose
The format exists to solve several problems at once:

1. **Single source of truth**
   ABI definitions should not be duplicated across languages or tooling. The IDL is the canonical definition used by generators, analyzers, and documentation.

2. **Stable ABI contracts**
   Types and call signatures must remain stable across versions. By keeping definitions in a simple, analyzable format, changes are explicit and reviewable.

3. **Language-neutral modeling**
   The language is small and avoids host-language features. This makes it easier to generate bindings for C, Zig, Rust, or custom tooling.

4. **Deterministic C ABI lowering**
   Slices, strings, optionals, and multi-return calls must be expressed in a way that can reliably lower to C-compatible forms.

5. **Human readability**
   Documentation is part of the format, making the ABI itself self-describing.

---

## Syntax

### Informal structure

An IDL file is a sequence of declarations and their children. Declarations are nested within namespaces, and each declaration may contain child nodes that describe its fields, items, parameters, or errors.

Key features:

- **Doc comments** use `///` and attach to the next node.
- **Line comments** use `//?` and are ignored by the parser.
- **Identifiers** are ASCII and may include dots (`.`) for scoped names. If a name includes special characters or keywords, escape it using `@"..."`.

### Small examples

Namespace with an enum:

```abi
/// Process-related declarations.
namespace process {
    /// Exit status codes.
    enum ExitCode : u32 {
        item success = 0;
        item failure = 1;
        ...
    }
}
```

Syscall with inputs, outputs, and errors:

```abi
/// Returns a process file name.
syscall get_file_name {
    in target: ?Process;
    out file_name: str;
    error InvalidHandle;
}
```

### Grammar (EBNF-style)

```
Document        = { Node } ;

Node            = DocComment* ( Declaration
                              | Field
                              | In
                              | Out
                              | EnumItem
                              | Error
                              | Reserve
                              | TypeDef
                              | Const
                              | Ellipse
                              | NoReturn ) ;

DocComment      = "///" { any-char-except-newline } newline ;
Comment         = "//?" { any-char-except-newline } newline ;

Declaration     = ("namespace" | "struct" | "union" | "enum" | "bitstruct" |
                   "syscall" | "async_call" | "resource")
                  Identifier [ ":" Type ] "{" { Node } "}" ;

Field           = "field" Identifier ":" Type [ "=" Value ] ";" ;
In              = "in" Identifier ":" Type [ "=" Value ] ";" ;
Out             = "out" Identifier ":" Type [ "=" Value ] ";" ;
EnumItem        = "item" Identifier [ "=" Value ] ";" ;
Error           = "error" Identifier ";" ;
Reserve         = "reserve" Type "=" Value ";" ;
NoReturn        = "noreturn" ";" ;
Ellipse         = "..." ;

TypeDef         = "typedef" Identifier "=" Type ";" ;
Const           = "const" Identifier [ ":" Type ] "=" Value ";" ;

Type            = MagicType
                | "?" Type
                | "*" PointerType
                | "[" "]" PointerType
                | "[" "*" "]" PointerType
                | "[" Value "]" Type
                | "fnptr" "(" [ Type { "," Type } ] ")" Type
                | BuiltinType
                | SignedIntType
                | UnsignedIntType
                | Identifier ;

PointerType     = [ "const" ] [ "align" "(" Number ")" ] Type ;

MagicType       = "<<" Identifier ":" MagicSize ">>" ;
MagicSize       = "u8" | "u16" | "u32" | "u64" | "usize" ;

BuiltinType     = "void" | "bool" | "noreturn" | "anyptr" | "anyfnptr" |
                  "str" | "bytestr" | "bytebuf" | "usize" | "isize" |
                  "f32" | "f64" ;
SignedIntType   = "i" Number ;
UnsignedIntType = "u" Number ;

Value           = Number
                | Identifier
                | "true" | "false" | "null"
                | "." "{" [ "." Identifier "=" Value { "," "." Identifier "=" Value } ] "}" ;

Identifier      = { letter | digit | "_" | "." } | "@\"" { any-char-except-quote-or-newline } "\"" ;
Number          = decimal | hex | binary ;
```

### Context rules (summary)

The grammar lists all node types, but not all nodes are legal everywhere. The key rules are:

- `field` appears only inside `struct`, `union`, or `bitstruct`.
- `item` and `...` appear only inside `enum`.
- `in`, `out`, `error`, and `noreturn` appear only inside `syscall` or `async_call`.
- `reserve` appears only inside `bitstruct`.
- `typedef` and `const` are top-level declarations (including inside namespaces).

---

## Semantics

### Namespaces and fully-qualified names

Namespaces provide hierarchical structure. Every declaration acquires a fully-qualified name based on its namespace nesting. You can reference types by:

- **Local name** within the same namespace.
- **Qualified name** using dot notation (e.g., `process.ExitCode`).

Example:

```abi
namespace fs {
    struct Path { field data: str; }
}

namespace process {
    // Refers to fs.Path by qualified name.
    syscall spawn {
        in path: fs.Path;
    }
}
```

### Doc comments

- `///` lines are collected and attached to the next node.
- Empty leading/trailing lines are trimmed.
- Common indentation is removed so multi-line blocks align cleanly.

Example:

```abi
/// Returns the base address of the process.
///
/// This value is constant while the process is alive.
syscall get_base_address {
    in target: ?Process;
    out base_address: usize;
}
```

### Declarations

#### `struct`
- A list of named `field` entries.
- Fields may have defaults.
- Order is preserved and meaningful for layout and ABI.

Example:

```abi
struct Point {
    field x: i32;
    field y: i32;
}
```

#### `union`
- A list of named `field` entries.
- Fields **cannot** have default values.
- Union layout is a C-style overlapping representation.

Example:

```abi
union AnyAddr {
    field v4: IPv4;
    field v6: IPv6;
}
```

#### `enum`
- Requires an integer subtype (e.g., `: u32`).
- Items may specify explicit values.
- `...` marks the enum as *open*, indicating more values may exist outside this file.

Example:

```abi
enum ExitCode : u32 {
    item success = 0;
    item failure = 1;
    ...
}
```

#### `bitstruct`
- Requires an integer subtype (e.g., `: u16`).
- Fields are packed in order into the backing integer.
- `reserve` creates unnamed padding bits.
- All fields must have known bit widths.
- Total bit width must match the backing type exactly.

Example:

```abi
bitstruct FileAttributes : u16 {
    field directory: bool;
    reserve u15 = 0;
}
```

#### `syscall` and `async_call`
- Define call signatures.
- `in` parameters are inputs; `out` parameters are outputs.
- `error` entries define possible error codes.
- `noreturn` marks a call as not returning (and forbids outputs).

Example:

```abi
syscall terminate {
    in exit_code: ExitCode;
    noreturn;
}
```

#### `resource`
- Declares an opaque handle type.
- Treated as a distinct ABI type for safety and clarity.

Example:

```abi
resource File { }
resource Process { }
```

#### `typedef`
- Creates an alias name for an existing type.
- Used to introduce convenient names or to reify “magic types.”

Example:

```abi
typedef ThreadFunction = fnptr (?anyptr) u32;
```

#### `const`
- Declares a constant value.
- A type annotation is optional.
- Values can be integers, booleans, `null`, or compound initializers.

Example:

```abi
const page_size: usize = 4096;
```

---

## Type System

### Built-in types

The built-in (well-known) types are the core primitives the format understands:

- **Primitives:** `void`, `bool`, `noreturn`
- **Pointers:** `anyptr` (opaque data pointer), `anyfnptr` (opaque function pointer)
- **Strings/buffers:**
  - `str` — immutable UTF-8 string
  - `bytestr` — immutable byte string
  - `bytebuf` — mutable byte buffer
- **Integers:** `usize`, `isize`, `u8/u16/u32/u64`, `i8/i16/i32/i64`, and arbitrary `uN`/`iN`
- **Floats:** `f32`, `f64`

Important size rules:

- `usize` / `isize` match pointer size.
- `str`, `bytestr`, `bytebuf` are represented as a pointer + length pair.
- `bool` is 1 bit in bitstructs, 1 byte in normal layouts.

### User-defined types

- **Structs, unions, enums, bitstructs, resources** are all named and referenced by their identifiers or qualified names.
- Type names are resolved within namespace scopes.

### Pointers, slices, arrays, and optionals

#### Pointer forms

- `*T` — pointer to one element.
- `*const T` — pointer to a constant element.
- `*const align(8) T` — pointer with explicit alignment requirement.

#### Slice forms

- `[]T` — slice (pointer + length).
- `[*]T` — unknown-length pointer (no length in the type).

#### Arrays

- `[N]T` — fixed-size array (N is an integer value).

#### Optionals

- `?T` — nullable/optional wrapper.

#### Function pointers

- `fnptr (A, B, C) R` — function pointer taking parameters `A`, `B`, `C` returning `R`.

Examples:

```abi
field data: []const u8;        // slice of bytes
field ptr: [*]u8;              // unknown-length pointer
field buf: [128]u8;            // fixed-size array
field callback: fnptr (u32) u32;
field maybe_handle: ?Process;  // optional resource
```

### Magic types (`<<...>>`)

Magic types are a special expansion mechanism. They are only used via `typedef` and expand into enums that enumerate declarations of a given kind.

Supported kinds:

- `struct_enum`
- `union_enum`
- `enum_enum`
- `bitstruct_enum`
- `syscall_enum`
- `async_call_enum`
- `resource_enum`
- `constant_enum`

Each magic type requires a size (`u8`, `u16`, `u32`, `u64`, `usize`). The analyzer generates a concrete enum, with items derived from the fully-qualified names of all declarations of that kind.

Example:

```abi
/// Enumeration of all syscall numbers.
typedef Syscall_ID = <<syscall_enum:u32>>;
```

---

## C ABI Lowering

The ABI mapper derives a **native** C-compatible form from the **logical** IDL definitions. The transformation is deterministic and documented here so tooling can target it consistently.

### Slice lowering

Slices (`[]T`) and string/buffer types are always lowered to pointer + length pairs in C ABI:

- Logical: `name: []T`
- Native:
  - `name_ptr: *T` (or `*const T` if the logical type is immutable)
  - `name_len: usize`

This applies to:

- `[]T`
- `str`, `bytestr`, `bytebuf`
- Optional slices and optional string/buffer types

Example:

```abi
syscall read {
    in buffer: []u8;
    out count: usize;
}
```

Lowered inputs:

- `buffer_ptr: *u8`
- `buffer_len: usize`

### Optional lowering

Optionals that are already C-compatible are kept as-is (e.g., optional pointers or optional resources). Optional slices and optional string/buffer types are lowered with the optional applied to the pointer only; the length remains a plain `usize`.

Example:

```abi
in owners: ?[]Process;
```

Lowers to:

- `owners_ptr: ?*Process`
- `owners_len: usize`

Example:

```abi
in file_name: ?str;
```

Lowers to:

- `file_name_ptr: ?*const u8`
- `file_name_len: usize`

### Syscall return/value lowering

Syscalls follow these rules to ensure a C-compatible signature:

1. **Errors present** (`error` entries exist):
   - All logical outputs become input pointers (`out` parameters are passed as `*T`).
   - The function returns a single `u16` error code (`0` is success, non-zero is an error).

2. **No errors and exactly one output:**
   - That output is returned directly as the C return value.

3. **No errors and multiple outputs:**
   - Outputs become input pointers.
   - The function returns `void`.

This gives a single, predictable ABI signature in all cases.

### Async call lowering

Async calls are lowered similarly for slices and optionals, but do **not** use syscall return remapping. Their outputs remain outputs in the native representation, which is treated as a structure-like ABI (useful for async operation records rather than direct C call signatures).

### Struct field lowering

Struct fields undergo slice lowering in-place:

- `str`, `bytestr`, `bytebuf` become `*_ptr` + `*_len`.
- `[]T` becomes `*_ptr` + `*_len`.
- Optional slices become `?*_ptr` + `*_len`.

Union fields are not transformed; unions must already be C-ABI compatible.

Example:

```abi
struct FileInfo {
    field name: str;
    field data: []const u8;
}
```

Lowered fields:

- `name_ptr: *const u8`, `name_len: usize`
- `data_ptr: *const u8`, `data_len: usize`

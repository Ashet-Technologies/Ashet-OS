# Ashet IDL Documentation Comment Format

**Status:** Draft

## 1. Overview

This document specifies the syntax, semantics, and data model for structured documentation comments in Ashet IDL files. It replaces the previous unstructured `docs: []const u8` (list of raw lines) representation with a validated, hyperlinked document fragment tree.

### 1.1 Design goals

- **Minimal migration friction.** Existing doc comments are nearly valid as-is.
- **Validated cross-references.** Every reference to an IDL declaration is resolved and checked at parse time.
- **Structured admonitions.** `NOTE`, `LORE`, `EXAMPLE`, etc. are first-class constructs, not conventions.
- **HyperDoc-compatible AST.** The output tree uses a subset of HyperDoc 2.0's semantic model, enabling shared rendering and tooling.
- **Parseable in Zig.** No complex grammar; every construct is recognizable by a simple line-prefix or character-level scan.

### 1.2 Relationship to HyperDoc 2.0

The output AST of a parsed doc comment is a strict subset of HyperDoc 2.0's document model. Specifically, it uses the node types `p`, `note`, `warning`, `tip`, `ul`, `ol`, `pre`, `\mono`, `\em`, `\ref`, and `\link`, plus the custom extensions `lore`, `example`, `deprecated`, and `decision`.

The *input syntax*, however, is a distinct lightweight format optimized for `///` comment lines, not HyperDoc surface syntax. Think of it as a convenient authoring frontend that compiles to a HyperDoc fragment.

---

## 2. Source representation

### 2.1 Comment extraction

Documentation comments are lines beginning with `///`. The parser strips the `///` prefix and exactly one optional trailing space character (the separator between `///` and content). The resulting lines form the **raw doc text**, which is then parsed according to this specification.

```
/// This is a paragraph.        →  "This is a paragraph."
///                              →  ""
///   Indented continuation.     →  "  Indented continuation."
```

Line comments (`//?`) are not part of the documentation and are discarded before doc parsing.

### 2.2 Encoding

Raw doc text inherits the encoding of the IDL source file (UTF-8). No additional encoding layer is defined.

---

## 3. Document model (normative)

A parsed doc comment produces a **DocComment** value. The model is specified here as a JSON schema; the canonical in-memory representation in Zig is derived from this.

### 3.1 JSON schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ashet.org/schemas/abi-doc-comment/v1",
  "title": "Ashet IDL DocComment",

  "$defs": {

    "DocComment": {
      "description": "Root type. A parsed documentation comment.",
      "type": "object",
      "required": ["sections"],
      "additionalProperties": false,
      "properties": {
        "sections": {
          "type": "array",
          "items": { "$ref": "#/$defs/Section" },
          "minItems": 0
        }
      }
    },

    "Section": {
      "description": "A thematic section of a doc comment. The first section with kind 'main' contains the primary description. Subsequent sections are admonitions.",
      "type": "object",
      "required": ["kind", "blocks"],
      "additionalProperties": false,
      "properties": {
        "kind": {
          "type": "string",
          "enum": [
            "main",
            "note",
            "warning",
            "lore",
            "example",
            "deprecated",
            "decision",
            "learn",
          ]
        },
        "blocks": {
          "type": "array",
          "items": { "$ref": "#/$defs/Block" },
          "minItems": 1
        }
      }
    },

    "Block": {
      "description": "A block-level element inside a section.",
      "oneOf": [
        { "$ref": "#/$defs/Paragraph" },
        { "$ref": "#/$defs/UnorderedList" },
        { "$ref": "#/$defs/OrderedList" },
        { "$ref": "#/$defs/CodeBlock" }
      ]
    },

    "Paragraph": {
      "type": "object",
      "required": ["type", "content"],
      "additionalProperties": false,
      "properties": {
        "type": { "const": "paragraph" },
        "content": { "$ref": "#/$defs/InlineContent" }
      }
    },

    "UnorderedList": {
      "type": "object",
      "required": ["type", "items"],
      "additionalProperties": false,
      "properties": {
        "type": { "const": "unordered_list" },
        "items": {
          "type": "array",
          "items": { "$ref": "#/$defs/InlineContent" },
          "minItems": 1
        }
      }
    },

    "OrderedList": {
      "type": "object",
      "required": ["type", "items"],
      "additionalProperties": false,
      "properties": {
        "type": { "const": "ordered_list" },
        "items": {
          "type": "array",
          "items": { "$ref": "#/$defs/InlineContent" },
          "minItems": 1
        }
      }
    },

    "CodeBlock": {
      "type": "object",
      "required": ["type", "content"],
      "additionalProperties": false,
      "properties": {
        "type": { "const": "code_block" },
        "syntax": {
          "description": "Optional syntax identifier (HyperDoc §10.1.1 compatible).",
          "type": ["string", "null"]
        },
        "content": {
          "description": "Raw text content of the code block. Line breaks are preserved.",
          "type": "string"
        }
      }
    },

    "InlineContent": {
      "description": "A sequence of inline spans forming a rich text run.",
      "type": "array",
      "items": { "$ref": "#/$defs/Inline" }
    },

    "Inline": {
      "description": "A single inline element.",
      "oneOf": [
        { "$ref": "#/$defs/Text" },
        { "$ref": "#/$defs/Code" },
        { "$ref": "#/$defs/Emphasis" },
        { "$ref": "#/$defs/Ref" },
        { "$ref": "#/$defs/Link" }
      ]
    },

    "Text": {
      "type": "object",
      "required": ["type", "value"],
      "additionalProperties": false,
      "properties": {
        "type": { "const": "text" },
        "value": { "type": "string" }
      }
    },

    "Code": {
      "description": "Inline monospace code span. Not validated as a reference.",
      "type": "object",
      "required": ["type", "value"],
      "additionalProperties": false,
      "properties": {
        "type": { "const": "code" },
        "value": { "type": "string" }
      }
    },

    "Emphasis": {
      "type": "object",
      "required": ["type", "content"],
      "additionalProperties": false,
      "properties": {
        "type": { "const": "emphasis" },
        "content": { "$ref": "#/$defs/InlineContent" }
      }
    },

    "Ref": {
      "description": "A validated cross-reference to an IDL declaration. The fqn field always contains the fully-qualified resolved name, regardless of what the author wrote in the source.",
      "type": "object",
      "required": ["type", "fqn"],
      "additionalProperties": false,
      "properties": {
        "type": { "const": "ref" },
        "fqn": {
          "description": "The fully-qualified name of the referenced IDL declaration. Always stored in resolved form (e.g. 'resource.bind.target', never the shorthand 'target').",
          "type": "string"
        }
      }
    },

    "Link": {
      "description": "A hyperlink to an external resource.",
      "type": "object",
      "required": ["type", "url"],
      "additionalProperties": false,
      "properties": {
        "type": { "const": "link" },
        "url": { "type": "string" },
        "content": {
          "description": "Display text. If absent or empty, the URL is used as display text.",
          "$ref": "#/$defs/InlineContent"
        }
      }
    }
  },

  "$ref": "#/$defs/DocComment"
}
```

### 3.2 Type summary

```
DocComment
 └─ sections: Section[]

Section
 ├─ kind: "main" | "note" | "warning" | "lore" | "example"
 │         | "deprecated" | "decision" | "learn"
 └─ blocks: Block[]          (at least 1)

Block = Paragraph | UnorderedList | OrderedList | CodeBlock

Paragraph
 └─ content: Inline[]

UnorderedList
 └─ items: Inline[][]        (each item is one inline run)

OrderedList
 └─ items: Inline[][]

CodeBlock
 ├─ syntax: string?
 └─ content: string           (raw text, newlines preserved)

Inline = Text | Code | Emphasis | Ref | Link

Text     { value: string }
Code     { value: string }
Emphasis { content: Inline[] }
Ref      { fqn: string }          (always fully-qualified, resolved form)
Link     { url: string, content?: Inline[] }
```

### 3.3 HyperDoc AST mapping

For tooling that consumes HyperDoc document trees, the mapping is:

| Doc comment type | HyperDoc element |
|---|---|
| Section(main) | sequence of child blocks (no wrapper) |
| Section(note) | `note { ... }` |
| Section(warning) | `warning { ... }` |
| Section(lore) | `lore { ... }` (extension) |
| Section(example) | `example { ... }` (extension) |
| Section(deprecated) | `deprecated { ... }` (extension) |
| Section(decision) | `decision { ... }` (extension) |
| Paragraph | `p { ... }` |
| UnorderedList | `ul { li { ... } li { ... } }` |
| OrderedList | `ol { li { ... } li { ... } }` |
| CodeBlock | `pre(syntax="...") : \| ...` |
| Text | bare inline text |
| Code | `\mono { ... }` |
| Emphasis | `\em { ... }` |
| Ref | `\ref(ref="...");` |
| Link | `\link(uri="...") { ... }` |

---

## 4. Syntax

### 4.1 Block structure

After prefix stripping (§2.1), the raw doc text is parsed line-by-line into blocks. Blank lines are block separators.

#### 4.1.1 Paragraphs

Any sequence of non-blank lines that does not match another block rule forms a paragraph. Adjacent lines are joined with a single space (whitespace normalization).

```
/// The process handle to terminate.
/// Must be a valid, non-destroyed handle.
```

Produces one paragraph: `The process handle to terminate. Must be a valid, non-destroyed handle.`

#### 4.1.2 Admonition sections

A line matching the pattern `<TAG>: <text>` where `<TAG>` is one of the recognized admonition keywords starts a new section. The text after the colon (plus any continuation lines) forms the first block of that section. Continuation lines are either:

- Indented by at least one space beyond the tag's colon position (aligned continuation), or
- Any non-blank, non-admonition, non-list line (unindented continuation — for compatibility with existing docs).

Recognized tags (case-sensitive):

| Tag | Section kind |
|---|---|
| `NOTE` | `note` |
| `WARNING` | `warning` |
| `LORE` | `lore` |
| `EXAMPLE` | `example` |
| `DEPRECATED` | `deprecated` |
| `DECISION` | `decision` |
| `LEARN` | `learn` |

A new admonition tag or a blank line followed by different content ends the current section and starts a new one.

```
/// NOTE: This will *always* destroy the resource, even if it's
///       still strongly bound by a process.
```

Produces: `Section(note)` containing one paragraph.

Multiple admonitions of the same kind are separate sections:

```
/// NOTE: First note.
///
/// NOTE: Second note.
```

Produces two `Section(note)` values.

All text before the first admonition tag belongs to `Section(main)`. If no admonition tags appear, the entire doc comment is a single `Section(main)`.

#### 4.1.3 Unordered lists

A line beginning with `- ` (hyphen + space) starts an unordered list item. Continuation lines must be indented by at least two spaces.

```
/// - Resources are created through various calls in the kernel API,
///   but their lifetime is managed through this namespace.
/// - After creation, a resource is strongly bound to the creator.
```

Produces: `UnorderedList` with two items.

Adjacent list items form a single list. A blank line or non-list-item line ends the list.

#### 4.1.4 Ordered lists

A line beginning with `<N>. ` (decimal number + dot + space) starts an ordered list item. Continuation lines must be indented past the number prefix.

```
/// 1. Allocate memory.
/// 2. Write the payload.
/// 3. Schedule the ARC.
```

#### 4.1.5 Fenced code blocks

A line consisting of exactly ` ``` ` or ` ```<syntax> ` starts a fenced code block. The block continues until a closing ` ``` ` line. Lines between the fences are taken verbatim (no inline parsing, no whitespace normalization).

```
/// ```zig
/// const handle = try resource.open(path);
/// defer resource.close(handle);
/// ```
```

Produces: `CodeBlock { syntax: "zig", content: "const handle = try resource.open(path);\ndefer resource.close(handle);" }`

The syntax identifier, if present, follows HyperDoc §10.1.1 rules.

### 4.2 Inline syntax

Within paragraphs, list items, and admonition text, the following inline constructs are recognized. Inline parsing operates on the joined, whitespace-normalized text of a block.

#### 4.2.1 Inline code: `` `...` ``

A backtick-delimited span produces an inline `Code` node. The content between backticks is taken verbatim (no nested inline parsing).

```
/// The `destroy` syscall always succeeds.
```

Produces: `[Text("The "), Code("destroy"), Text(" syscall always succeeds.")]`

Backtick spans must not be empty. An unmatched backtick is a parse error.

#### 4.2.2 Cross-reference: `` @`...` ``

An `@` character immediately followed by a backtick-delimited span produces an inline `Ref` node. The content between the backticks is interpreted as a fully-qualified name (FQN) and **must** resolve to a declaration in the IDL.

```
/// See @`overlapped.ARC` for the completion queue model.
```

Produces: `[Text("See "), Ref("overlapped.ARC"), Text(" for the completion queue model.")]`

FQN resolution rules:

Resolution walks from the innermost scope outward. Given a reference `@`name`` on a declaration with FQN `a.b.c`:

1. **Self scope.** Look up `a.b.c.name` — i.e., the reference names a child of the declaration the doc comment is attached to. This is the most common case for syscall docs referencing their own parameters, struct docs referencing their own fields, enum docs referencing their own items, etc.
2. **Sibling scope.** Look up `a.b.name` — i.e., a sibling declaration in the same namespace.
3. **Parent scopes.** Walk outward: `a.name`, then `name` at global scope.
4. **Global exact match.** Look up `name` as a fully-qualified path (for when the author writes the full FQN explicitly).
5. If no match is found, emit a validation error.

Steps 1–3 check the *unqualified* name against progressively broader scopes. Step 4 handles the case where `name` itself contains dots and is already fully qualified (e.g., `@`overlapped.ARC.tag``).

If a name is ambiguous (matches at multiple scopes), the innermost match wins. Tooling **should** emit a warning for ambiguous references and suggest using the full FQN.

**Examples:**

```abi
/// Parameter @`foo` is used for stuff.
///                   ↑ resolves to call.foo (self scope)
syscall call {
    in foo: u32;
}
```

```abi
namespace overlapped {
    /// See @`ARC` for the structure layout.
    ///       ↑ resolves to overlapped.ARC (sibling scope)
    syscall schedule {
        in @"arc": *ARC;
    }
}
```

```abi
/// Uses the @`overlapped.ARC` completion model.
///            ↑ resolves as-is (global exact match)
namespace process { ... }
```

For references to sub-items (fields, enum items, error variants), dot notation works at any scope level: `@`ARC.tag`` inside `namespace overlapped` resolves to `overlapped.ARC.tag` via sibling scope + child traversal.

A bare `@` not immediately followed by a backtick has no special meaning and is treated as literal text.

#### 4.2.3 Emphasis: `*...*`

An asterisk-delimited span produces an inline `Emphasis` node. The content between asterisks is parsed for nested inline constructs (code, references, links — but not nested emphasis).

```
/// This will *always* destroy the resource.
```

Produces: `[Text("This will "), Emphasis([Text("always")]), Text(" destroy the resource.")]`

Emphasis spans must not be empty. Opening `*` must be preceded by whitespace or start-of-text, and closing `*` must be followed by whitespace, punctuation, or end-of-text. This prevents false matches on expressions like `a*b*c`.

#### 4.2.4 Links: `[text](url)` and `<url>`

**Titled link:** A `[` character starts a link's display text, closed by `]`, immediately followed by `(url)`. The display text is parsed for nested inline constructs (code, emphasis, references). The URL is taken verbatim.

```
/// See [the RISC-V specification](https://riscv.org/specifications/) for details.
```

Produces: `Link { url: "https://riscv.org/specifications/", content: [Text("the RISC-V specification")] }`

**Autolink:** A `<` character followed by a URL scheme (`http://`, `https://`, or `mailto:`) and closed by `>` produces a link where the display text is the URL itself.

```
/// More information at <https://ashet.org/docs/abi>.
```

Produces: `Link { url: "https://ashet.org/docs/abi", content: [Text("https://ashet.org/docs/abi")] }`

A `<` not followed by a recognized URL scheme is treated as literal text. This avoids ambiguity with angle brackets in prose (e.g., `<CR><LF>`).

### 4.3 Escape sequences

To use the special characters literally in inline text:

| Sequence | Produces |
|---|---|
| `` \` `` | literal `` ` `` |
| `\*` | literal `*` |
| `\[` | literal `[` |
| `\<` | literal `<` |
| `\@` | literal `@` |
| `\\` | literal `\` |

Escapes are only recognized in inline contexts. They are not recognized inside code spans (`` `...` ``), code blocks, or URLs.

---

## 5. Parsing algorithm (non-normative)

This section describes the intended parsing strategy. It is non-normative but should produce results identical to the normative syntax rules.

### 5.1 Block pass (line-oriented)

```
input:  list of stripped doc lines
output: list of (SectionKind, Block)

state:
  current_section = main
  current_block = null
  in_code_fence = false

for each line:
  if in_code_fence:
    if line == "```":
      emit CodeBlock, in_code_fence = false
    else:
      append line to code block buffer
    continue

  if line starts with "```":
    flush current_block
    extract optional syntax tag
    in_code_fence = true
    continue

  if line is blank:
    flush current_block
    continue

  if line matches /^(NOTE|WARNING|LORE|EXAMPLE|DEPRECATED|DECISION):\s+(.*)/:
    flush current_block
    current_section = matched tag
    start new paragraph with captured text
    continue

  if line matches /^- (.*)/:
    if current_block is not unordered_list: flush, start new list
    append new list item with captured text
    continue

  if line matches /^(\d+)\. (.*)/:
    if current_block is not ordered_list: flush, start new list
    append new list item with captured text
    continue

  if current_block is list and line starts with sufficient indentation:
    append to current list item (continuation)
    continue

  if current_block is paragraph:
    append line to paragraph (continuation)
  else:
    flush current_block
    start new paragraph with line

flush current_block
```

### 5.2 Inline pass (character-oriented)

For each paragraph or list item text, scan left-to-right:

```
while not end-of-text:
  if char == '\\' and next is escapable:
    emit Text(next), advance 2
  elif char == '`':
    scan to closing '`'
    emit Code(content)
  elif char == '@' and next == '`':
    advance past '@'
    scan to closing '`'
    emit Ref(content)  // validated later
  elif char == '*':
    if valid emphasis open (preceded by whitespace/start):
      scan to closing '*' (with valid close context)
      recursively parse content for nested inlines
      emit Emphasis(parsed_content)
    else:
      emit Text('*')
  elif char == '[':
    scan to ']('
    parse display text for nested inlines
    scan to closing ')'
    emit Link(url, parsed_display)
  elif char == '<' and followed by url scheme:
    scan to '>'
    emit Link(url, [Text(url)])
  else:
    accumulate into Text span
```

### 5.3 Validation pass

After block and inline parsing:

1. **FQN resolution:** For every `Ref` node, resolve the FQN against the IDL symbol table using the scoped resolution rules (§4.2.2). The resolution requires knowing the FQN of the declaration the doc comment is attached to. Emit an error for unresolvable references; emit a warning for ambiguous references.
2. **Empty section check:** Sections with zero blocks are invalid (parser bug, not user error).
3. **Unclosed constructs:** Unmatched backticks, asterisks, brackets, or code fences are parse errors.
4. **TODO rejection:** If any section's text starts with `TODO:` (or a line comment `//? TODO:` was mistakenly written as `/// TODO:`), emit a warning. TODOs are development artifacts; use `//? TODO:` instead.

---

## 6. Examples

### 6.1 Simple field and parameter documentation

Source:

```abi
/// The process handle to query.
/// If `null`, uses the current process.
in target: ?Process;
```

JSON output:

```json
{
  "sections": [{
    "kind": "main",
    "blocks": [{
      "type": "paragraph",
      "content": [
        { "type": "text", "value": "The process handle to query. If " },
        { "type": "code", "value": "null" },
        { "type": "text", "value": ", uses the current process." }
      ]
    }]
  }]
}
```

Self-scope reference example — a syscall doc referencing its own parameter:

```abi
/// Binds @`resource` to a process.
///
/// The success of this operation allows @`target` to access
/// @`resource`, and optionally gain/lose a strong binding.
syscall bind {
    in resource: SystemResource;
    in target: ?Process;
    in binding: BindOperation;
}
```

Here `@`resource`` resolves to `resource.bind.resource` (self-scope), `@`target`` to `resource.bind.target`.

### 6.2 Multiple notes

Source:

```abi
/// Immediately destroys the resource and releases its memory.
///
/// NOTE: This will *always* destroy the resource, even if it's
///       still strongly bound by a process.
///
/// NOTE: This immediately triggers tether chains and destroys
///       all tethered resources as well.
///
/// NOTE: @`resource.destroy` always succeeds; destroying an invalid
///       or already-destroyed handle is a no-op.
```

JSON output:

```json
{
  "sections": [
    {
      "kind": "main",
      "blocks": [{
        "type": "paragraph",
        "content": [
          { "type": "text", "value": "Immediately destroys the resource and releases its memory." }
        ]
      }]
    },
    {
      "kind": "note",
      "blocks": [{
        "type": "paragraph",
        "content": [
          { "type": "text", "value": "This will " },
          { "type": "emphasis", "content": [
            { "type": "text", "value": "always" }
          ]},
          { "type": "text", "value": " destroy the resource, even if it's still strongly bound by a process." }
        ]
      }]
    },
    {
      "kind": "note",
      "blocks": [{
        "type": "paragraph",
        "content": [
          { "type": "text", "value": "This immediately triggers tether chains and destroys all tethered resources as well." }
        ]
      }]
    },
    {
      "kind": "note",
      "blocks": [{
        "type": "paragraph",
        "content": [
          { "type": "ref", "fqn": "resource.destroy" },
          { "type": "text", "value": " always succeeds; destroying an invalid or already-destroyed handle is a no-op." }
        ]
      }]
    }
  ]
}
```

### 6.3 LORE section with list and cross-references

Source:

```abi
/// All syscalls related to generic resource management.
///
/// - Resources are created through various calls in the kernel API, but their
///   lifetime is managed through calls inside this namespace.
/// - After creation, a resource is strongly bound to the process that created it.
/// - When a resource is destroyed, it becomes unusable from userland.
///
/// NOTE: Every kernel object the userland can interact with is a @`SystemResource`.
///
/// LORE: Originally, Ashet OS had no concept of bindings, but only of ownership.
///       But this quickly led to problems like "the desktop server also owns the
///       window, so even if the application releases the window, it is not destroyed."
///       The idea of allowing a process to access a resource without keeping it alive
///       solves this problem completely. See @`resource.bind` for the binding API.
```

JSON output:

```json
{
  "sections": [
    {
      "kind": "main",
      "blocks": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "value": "All syscalls related to generic resource management." }
          ]
        },
        {
          "type": "unordered_list",
          "items": [
            [
              { "type": "text", "value": "Resources are created through various calls in the kernel API, but their lifetime is managed through calls inside this namespace." }
            ],
            [
              { "type": "text", "value": "After creation, a resource is strongly bound to the process that created it." }
            ],
            [
              { "type": "text", "value": "When a resource is destroyed, it becomes unusable from userland." }
            ]
          ]
        }
      ]
    },
    {
      "kind": "note",
      "blocks": [{
        "type": "paragraph",
        "content": [
          { "type": "text", "value": "Every kernel object the userland can interact with is a " },
          { "type": "ref", "fqn": "SystemResource" },
          { "type": "text", "value": "." }
        ]
      }]
    },
    {
      "kind": "lore",
      "blocks": [{
        "type": "paragraph",
        "content": [
          { "type": "text", "value": "Originally, Ashet OS had no concept of bindings, but only of ownership. But this quickly led to problems like \"the desktop server also owns the window, so even if the application releases the window, it is not destroyed.\" The idea of allowing a process to access a resource without keeping it alive solves this problem completely. See " },
          { "type": "ref", "fqn": "resource.bind" },
          { "type": "text", "value": " for the binding API." }
        ]
      }]
    }
  ]
}
```

### 6.4 DECISION and EXAMPLE admonitions

Source:

```abi
/// Defines the process exit status.
///
/// DECISION: Unlike POSIX, Ashet OS uses a single boolean for success/failure
///           rather than an integer exit code. Integer codes are overloaded in
///           practice (is 2 "worse" than 1? is 0 always success?) and the
///           meaningful information is carried by log output, not codes.
///
/// EXAMPLE: A well-behaved application terminates with:
///
/// ```zig
/// process.terminate(.success);
/// ```
```

JSON output:

```json
{
  "sections": [
    {
      "kind": "main",
      "blocks": [{
        "type": "paragraph",
        "content": [
          { "type": "text", "value": "Defines the process exit status." }
        ]
      }]
    },
    {
      "kind": "decision",
      "blocks": [{
        "type": "paragraph",
        "content": [
          { "type": "text", "value": "Unlike POSIX, Ashet OS uses a single boolean for success/failure rather than an integer exit code. Integer codes are overloaded in practice (is 2 \"worse\" than 1? is 0 always success?) and the meaningful information is carried by log output, not codes." }
        ]
      }]
    },
    {
      "kind": "example",
      "blocks": [
        {
          "type": "paragraph",
          "content": [
            { "type": "text", "value": "A well-behaved application terminates with:" }
          ]
        },
        {
          "type": "code_block",
          "syntax": "zig",
          "content": "process.terminate(.success);"
        }
      ]
    }
  ]
}
```

### 6.5 Links

Source:

```abi
/// The timezone database follows the IANA format.
/// See [the IANA tz database](https://www.iana.org/time-zones) for details,
/// or the mirror at <https://github.com/eggert/tz>.
```

JSON output:

```json
{
  "sections": [{
    "kind": "main",
    "blocks": [{
      "type": "paragraph",
      "content": [
        { "type": "text", "value": "The timezone database follows the IANA format. See " },
        { "type": "link",
          "url": "https://www.iana.org/time-zones",
          "content": [
            { "type": "text", "value": "the IANA tz database" }
          ]
        },
        { "type": "text", "value": " for details, or the mirror at " },
        { "type": "link",
          "url": "https://github.com/eggert/tz",
          "content": [
            { "type": "text", "value": "https://github.com/eggert/tz" }
          ]
        },
        { "type": "text", "value": "." }
      ]
    }]
  }]
}
```

### 6.6 Minimal field doc (the common case)

Source:

```abi
/// The time is adjusted to the first possible past point in time.
```

JSON output:

```json
{
  "sections": [{
    "kind": "main",
    "blocks": [{
      "type": "paragraph",
      "content": [
        { "type": "text", "value": "The time is adjusted to the first possible past point in time." }
      ]
    }]
  }]
}
```

---

## 7. Grammar (EBNF)

This grammar describes the surface syntax after `///` prefix stripping.

```ebnf
(* Block level — line oriented *)

doc_comment      = { blank_line } , { section } ;

section          = [ admonition_start ] , block , { blank_line , block } ;

admonition_start = tag , ":" , ws , text_line ;
tag              = "NOTE" | "WARNING" | "LORE" | "EXAMPLE"
                 | "DEPRECATED" | "DECISION" | "LEARN";

block            = code_block | unordered_list | ordered_list | paragraph ;

code_block       = "```" , [ syntax_id ] , newline ,
                   { code_line , newline } ,
                   "```" , newline ;
syntax_id        = ident_char , { ident_char | "-" | "." | ":" } ;
code_line        = { any_char_except_newline } ;

unordered_list   = ul_item , { ul_item } ;
ul_item          = "- " , inline_text , newline ,
                   { "  " , continuation_text , newline } ;

ordered_list     = ol_item , { ol_item } ;
ol_item          = digit , { digit } , ". " , inline_text , newline ,
                   { "   " , continuation_text , newline } ;

paragraph        = text_line , { continuation_text , newline } ;

text_line        = inline_text , newline ;
continuation_text = inline_text ;

blank_line       = newline ;

(* Inline level — character oriented *)

inline_text      = { inline_item } ;

inline_item      = ref | code_span | emphasis | titled_link
                 | autolink | escape | plain_text ;

ref              = "@" , "`" , fqn_chars , "`" ;
code_span        = "`" , code_chars , "`" ;
emphasis         = "*" , inline_text , "*" ;       (* see §4.2.3 for open/close rules *)
titled_link      = "[" , inline_text , "]" , "(" , url_chars , ")" ;
autolink         = "<" , url_scheme , url_chars , ">" ;
escape           = "\\" , escapable_char ;

fqn_chars        = fqn_char , { fqn_char } ;
fqn_char         = letter | digit | "_" | "." | "@" ;   (* @"..." for escaped IDL names *)
code_chars       = { any_char_except_backtick }- ;       (* at least one character *)
url_scheme       = "http://" | "https://" | "mailto:" ;
url_chars        = { any_char_except_closing }- ;
escapable_char   = "`" | "*" | "[" | "<" | "@" | "\\" ;
plain_text       = { text_char }- ;
text_char        = ? any character not starting another inline construct ? ;
```

---

## 8. Diagnostics

The parser **must** emit diagnostics for the following conditions:

| Condition | Severity |
|---|---|
| Unresolvable `@\`fqn\`` | Error |
| Ambiguous `@\`fqn\`` (matches at multiple scopes) | Warning |
| Unclosed backtick span | Error |
| Unclosed emphasis span | Error |
| Unclosed code fence | Error |
| Unclosed `[text](url)` link | Error |
| Empty code span (``` `` ```) | Error |
| Empty emphasis span (`**`) | Error |
| `TODO:` used as admonition tag | Warning |
| Trailing whitespace on doc lines | Warning (non-fatal) |
| Section with no blocks (parser bug) | Error |

---

## 9. Migration guide

The following table summarizes the changes needed to migrate existing doc comments:

| Current pattern | New pattern | Count (est.) |
|---|---|---|
| `` `fqn` `` where fqn is a real declaration | `` @`fqn` `` | ~50-100 |
| `NOTE:` | `NOTE:` (unchanged) | 454 |
| `LORE:` | `LORE:` (unchanged) | 30 |
| `EXAMPLE:` | `EXAMPLE:` (unchanged) | 7 |
| `*emphasis*` | `*emphasis*` (unchanged) | ~10 |
| `` `code` `` (non-referencing) | `` `code` `` (unchanged) | ~500 |
| `- list item` | `- list item` (unchanged) | ~20 |
| `//? TODO:` (line comments) | `//? TODO:` (unchanged) | 67 |
| `/// TODO:` (in doc comments) | Move to `//? TODO:` | 1 |

**Effective migration:** Add `@` prefix to backtick spans that reference IDL declarations. Everything else stays the same.

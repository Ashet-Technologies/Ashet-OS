# Turtle Font Format

## Data encoding

```zig
struct {
  font_id: u32 = 0x4c2b8688,
  glyph_count: u32,
  glyph_index: [glyph_count]struct {
    codepoint: u24,
    advance: u8,
    offset: u32,
  },
  glyph_code: [*]u8,
}
```

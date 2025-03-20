# Bitmap Font Format

## Data encoding

```rs
struct Font {
  font_id: u32 = 0xcb3765be,
  line_height: u32, // Height of the font in pixels till the next line
  glyph_count: u32,
  glyph_meta: [glyph_count] packed struct (u32) {
    codepoint: u24,
    advance: u8,
  },
  glyph_offsets: [glyph_count]u32, // Stores offsets in `glyphs` to Glyph structs
  glyphs: [*]u8, // 
}

struct Glyph
{
  width: u8, // 255 must be enough for everyone
  height: u8,  // 255 must be enough for everyone
  offset_x: i8, // offset of the glyph to the base point
  offset_y: i8, // offset of the glyph to the base point
  bits: [(height+7)/8 * width]u8, // column-major bitmap, LSB=Top to MSB=Bottom
}
```

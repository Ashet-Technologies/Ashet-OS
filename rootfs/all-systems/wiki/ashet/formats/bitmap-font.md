# Bitmap Font Format

## Data encoding

```rs
struct Font {
  font_id: u32 = 0xcb3765be,
  line_height: u32, // Height of the font in pixels till the next line
  glyph_count: u32,

  // Contains meta-data about all available glyphs.
  // Code points must be sorted in ascending order so a binary search can be employed
  // to find the expected code point.
  glyph_meta: [glyph_count] packed struct (u32) {
    codepoint: u24,
    advance: u8,
  },

  // Stores relative offsets in `glyphs` to `Glyph` structures, each
  // encoding the corresponding code point from `glyph_meta`.
  glyph_offsets: [glyph_count]u32,

  // Sequence of `Glyph` structures with variable size.
  glyphs: [*]u8,
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

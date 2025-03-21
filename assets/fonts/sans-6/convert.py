#!/usr/bin/python

import io, math, json
from PIL import Image

glyphs=[]

max_height = None 
with open("metadata.txt") as file:
    lines = [line.rstrip() for line in file]
    for line in lines:
        items = line.split('\t')
        img_file = f"img/{items[1]}h_{items[0]}.gif"
        img = Image.open(img_file)

        rgb_img = img.convert('RGB')
        
        byte = int(items[1],16)
        codepoint = byte # todo: add translation
        width = int(img.width/2)
        height = int(img.height/2)

        if len(items) > 4 and len(items[4]) > 0:
          if len(items[4]) > 1:
            raise ValueError('unexpected ' + items[4])
          codepoint = int(ord(items[4]))

        if max_height != None:
          max_height = max(max_height, height)
        else: 
         max_height = height 

        glyph={
          "codepoint": codepoint,
          "width": width,
          "height": height,
          "byte": byte,
          "filename": img_file,
          "data": []
        }

        for x in range(0, width):
          bits = 0
          for y in range(0, height):
            r,g,b = rgb_img.getpixel((2*x, 2*y))
            pix = 1
            if r >= 0x80:
              pix = 0
            bits = bits | (pix << y)
          glyph["data"].append(bits)
        
        assert(len(glyph["data"]) == width)
        
        glyphs.append(glyph)

print(json.dumps(
  {
    chr(glyph["codepoint"]): {
      "filename": glyph["filename"],
      "advance": glyph["width"]
    }
    for glyph in glyphs
  },
  ensure_ascii=False,
  indent=2,
))


# sort by codepoints
glyphs.sort(key=lambda v : v["codepoint"])

for i in range(1, len(glyphs)):
  if glyphs[i-1]["codepoint"] == glyphs[i]["codepoint"]:
    raise ValueError('Duplicate glyph ' + str(glyphs[i]["byte"]))

def i8(i):
  return int(i).to_bytes(1, byteorder='little', signed=True)

def u8(i):
  return int(i).to_bytes(1, byteorder='little', signed=False)

def u32(i):
  return int(i).to_bytes(4, byteorder='little', signed=False)

with open("small.font", "wb") as file:
  file.write(u32(0xcb3765be))
  file.write(u32(6))
  file.write(u32(len(glyphs)))
  for glyph in glyphs:
    encoded = glyph["codepoint"]
    encoded |= int(glyph["width"])<<24
    file.write(u32(encoded))
  off = 0
  for glyph in glyphs:
    file.write(u32(off))
    off += 4 # header
    off += len(glyph["data"])
  for glyph in glyphs:
    file.write(u8(glyph["width"]))
    file.write(u8(glyph["height"]))
    file.write(i8(0))
    file.write(i8(0))
    file.write(bytearray(glyph["data"]))
  
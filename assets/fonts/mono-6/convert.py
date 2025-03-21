#!/usr/bin/python

import io, math
from PIL import Image

glyphs = []

max_height = None

img = Image.open("pico-8.png")
rgb_img = img.convert("RGB")

with open("glyphs.txt") as file:
    lines = [line.rstrip() for line in file]
    for line in lines:
        items = line.split("\t")  # CHAR, SRC_X, SRC_Y

        byte = int(ord(items[0]))
        codepoint = int(byte)
        width = 3
        height = 5

        src_x = 4 * int(items[1])
        src_y = 6 * int(items[2])

        if len(items) > 4 and len(items[4]) > 0:
            if len(items[4]) > 1:
                raise ValueError("unexpected " + items[4])
            codepoint = int(ord(items[4]))

        glyph = {
            "codepoint": codepoint,
            "width": width,
            "height": height,
            "byte": byte,
            "data": [],
        }

        for x in range(0, width):
            bits = 0
            for y in range(0, height):
                r, g, b = rgb_img.getpixel((src_x + x, src_y + y))
                pix = 1
                if r >= 0x80:
                    pix = 0
                bits = bits | (pix << y)
            glyph["data"].append(bits)

        assert len(glyph["data"]) == width

        glyphs.append(glyph)

# sort by codepoints
glyphs.sort(key=lambda v: v["codepoint"])

for i in range(1, len(glyphs)):
    if glyphs[i - 1]["codepoint"] == glyphs[i]["codepoint"]:
        raise ValueError("Duplicate glyph " + str(glyphs[i]["byte"]))


def i8(i):
    return int(i).to_bytes(1, byteorder="little", signed=True)


def u8(i):
    return int(i).to_bytes(1, byteorder="little", signed=False)


def u32(i):
    return int(i).to_bytes(4, byteorder="little", signed=False)


with open("mono-6.font", "wb") as file:
    file.write(u32(0xCB3765BE))
    file.write(u32(6))  # font height
    file.write(u32(len(glyphs)))
    for glyph in glyphs:
        encoded = glyph["codepoint"]
        encoded |= int(glyph["width"] + 1) << 24  # advance
        file.write(u32(encoded))
    off = 0
    for glyph in glyphs:
        file.write(u32(off))
        off += 4  # header
        off += len(glyph["data"])
    for glyph in glyphs:
        file.write(u8(glyph["width"]))
        file.write(u8(glyph["height"]))
        file.write(i8(0))
        file.write(i8(0))
        file.write(bytearray(glyph["data"]))

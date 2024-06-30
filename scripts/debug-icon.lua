#!/bin/lua

local png = require "dromozoa.png"

local f = assert(io.open(arg[1], "r"))

local bitmap = f:read(64 * 64)
local palette_src = f:read(15 * 2)

local palette = {[1] = {0, 0, 0, 0}}
for i = 1, 15 do
    local lo = palette_src:byte(2 * (i - 1) + 1)
    local hi = palette_src:byte(2 * (i - 1) + 2)
    local idx = lo + 256 * hi

    local r5 = bit32.rshift(bit32.band(idx, 0xF800), 11)
    local g6 = bit32.rshift(bit32.band(idx, 0x07E0), 5)
    local b5 = bit32.rshift(bit32.band(idx, 0x001F), 0)

    local r8 = bit32.bor(bit32.lshift(r5, 3), bit32.rshift(r5, 2))
    local g8 = bit32.bor(bit32.lshift(g6, 2), bit32.rshift(g6, 4))
    local b8 = bit32.bor(bit32.lshift(b5, 3), bit32.rshift(b5, 2))

    palette[i + 1] = {r8, g8, b8, 0xFF}
end

local writer = assert(png.writer())

local out = assert(io.open(arg[2], "wb"))
assert(writer:set_write_fn(function(data) out:write(data) end,
                           function() out:flush() end))
assert(writer:set_flush(2))

assert(writer:set_IHDR{
    width = 64,
    height = 64,
    bit_depth = 8,
    color_type = png.PNG_COLOR_TYPE_RGB_ALPHA
})

for y = 0, 63 do
    local row = ""

    for x = 0, 63 do

        local i = 1 + 64 * y + x;

        local index = bitmap:byte(i)

        local color = palette[index + 1]

        row = row .. string.char(color[3], color[2], color[1], color[4])
    end

    assert(writer:set_row(y + 1, row))
end

assert(writer:write_png())
out:close()

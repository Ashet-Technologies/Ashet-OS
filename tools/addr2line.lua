#!/bin/lua

arg[1] = arg[1] or "zig-out/bin/ashet-os"

while true do
    local line = io.stdin:read("*line")
    if not line then return end

    line = line:gsub("0x(%x%x%x%x%x%x%x%x)", function(hexnum)
        local proc = assert(io.popen("llvm-addr2line --exe \"" .. arg[1] ..
                                         "\" " .. hexnum, "r"))
        local addr = proc:read("*line")
        proc:close()
        return "0x" .. hexnum .. " (" .. addr .. ")"
    end)

    io.write(line, "\n")
end

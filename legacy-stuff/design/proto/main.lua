local bit32 = require("bit")

local system = {
    screen = {bg = 15, memory = {}, width = 64, height = 32},
    console = {cursor = {x = 0, y = 0, visible = true}, fg = 0x0, bg = 0xF},
    palette = {
        [0x0] = {love.math.colorFromBytes(20, 12, 28)}, -- #140c1c, black
        [0x1] = {love.math.colorFromBytes(68, 36, 52)}, -- #442434, dark violet
        [0x2] = {love.math.colorFromBytes(48, 52, 109)}, -- #30346d, dark blue
        [0x3] = {love.math.colorFromBytes(78, 74, 78)}, -- #4e4a4e, dark gray
        [0x4] = {love.math.colorFromBytes(133, 76, 48)}, -- #854c30, brown
        [0x5] = {love.math.colorFromBytes(52, 101, 36)}, -- #346524, dark green
        [0x6] = {love.math.colorFromBytes(208, 70, 72)}, -- #d04648, red
        [0x7] = {love.math.colorFromBytes(117, 113, 97)}, -- #757161, mid gray
        [0x8] = {love.math.colorFromBytes(89, 125, 206)}, -- #597dce, blue
        [0x9] = {love.math.colorFromBytes(210, 125, 44)}, -- #d27d2c, orange
        [0xA] = {love.math.colorFromBytes(133, 149, 161)}, -- #8595a1, bright gray
        [0xB] = {love.math.colorFromBytes(109, 170, 44)}, -- #6daa2c, green
        [0xC] = {love.math.colorFromBytes(210, 170, 153)}, -- #d2aa99, beige
        [0xD] = {love.math.colorFromBytes(109, 194, 202)}, -- #6dc2ca, cyan
        [0xE] = {love.math.colorFromBytes(218, 212, 94)}, -- #dad45e, yellow
        [0xF] = {love.math.colorFromBytes(222, 238, 214)} -- #deeed6, white
    }
}

do
    for i = 0, system.screen.width * system.screen.height - 1 do
        system.screen.memory[i] = 0xF020
    end
    local mt = {}
    function mt.__newindex(t, k, v)
        error("index out of bounds: " .. tostring(k), 2)
    end
    function mt.__index(t, k, v)
        error("index out of bounds: " .. tostring(k), 2)
    end
    setmetatable(system.screen.memory, mt)
end

local function deepCopy(value)
    if type(value) == "table" then
        local res = {}
        for i, v in pairs(value) do res[i] = deepCopy(v) end
        return res
    else
        return value
    end
end

local function centeredString(str)

    local padding = system.screen.width - #str
    if padding > 0 then
        local lpad = math.floor(padding / 2)
        local rpad = padding - lpad

        return string.rep(" ", lpad) .. str .. string.rep(" ", rpad)
    else
        return str
    end

end

function system.main()

    local function app_Browser()
        system.console.clear()
        system.screen.put(0, 1, (" "):rep(system.screen.width), 0xF, 0x2)
        system.screen.put(0, 2, (" "):rep(system.screen.width), 0xF, 0x2)
        system.screen.put(0, 3, (" "):rep(system.screen.width), 0xF, 0x2)
        system.screen.put(1, 2, "gopher://random-projects.net/", 0xF, 0x2)

        for i = 4, system.screen.height - 1 do
            local f, b = 0xA, 0x3
            if i >= 3 and i <= 6 then f, b = 0x3, 0xA end
            system.screen.put(system.screen.width - 1, i, " ", f, b)
        end

        local gopher_data = love.filesystem.read("res/gopher.txt")

        system.console.print("\n\n\n\n");
        system.console.print(gopher_data)

        system.screen.put(2, 29, "Ashet Home Computer", 0x8, 0xF)
        system.screen.put(2, 30, "Kristall Small-Internet Browser", 0x8, 0xF)
        system.screen.put(2, 31, "The LoLa Programming Language", 0x8, 0xF)

        local sel = system.console.appMenu {
            app = "Browser",
            {title = "File"},
            {title = "Edit"},
            {title = "View"},
            {title = "Favourites"},
            {title = "Help"}
        }
    end

    local function app_Shell()
        system.console.clear()
        system.console.print("\n")
        system.console.print("AshetOS Shell\n")

        system.console.appMenu {
            app = "Shell",
            {title = "File"},
            {title = "Edit"},
            {title = "Help"}
        }

        while true do
            local prompt = system.console.readLine("#> ");
            if prompt == "exit" then return end
            system.console.print("command entered: ", prompt, "\n")
        end
    end

    while true do

        local sel = system.console.menu(centeredString("Ashet OS"), "Shell",
                                        "Applications", "File System",
                                        "System Settings", "Power Off")
        if sel == 1 then
            app_Shell()
        elseif sel == 2 then

        elseif sel == 3 then

        elseif sel == 4 then

        elseif sel == 5 then
            return
        elseif sel == 2 then

        else

        end
    end
end

local font_texture
local char_quads = {}
local screen_canvas

local function Color(r, g, b) return {r / 255, g / 255, b / 255} end

function math.clamp(a, min, max)
    if a < min then
        return min
    elseif a > max then
        return max
    else
        return a
    end
end

function system.screen.attrs(fg, bg)
    fg = bit32.band(0xF, math.floor(tonumber(fg) or 0))
    bg = bit32.band(0xF, math.floor(tonumber(bg) or 15))

    return 256 * (16 * fg + bg)
end

function system.screen.set(x, y, c, fg, bg)
    assert(type(x) == "number")
    assert(type(y) == "number")
    assert(type(c) == "number" or type(c) == "string")

    local i = system.screen.width * math.floor(y) + math.floor(x)

    local attrs = system.screen.attrs(fg, bg)

    if type(c) == "string" then
        system.screen.memory[i] = attrs + c:byte()
    else
        system.screen.memory[i] = attrs + bit32.band(math.floor(c), 0xFF)
    end
end

function system.screen.put(x, y, text, fg, bg)
    assert(type(x) == "number")
    assert(type(y) == "number")
    assert(type(text) == "string")

    for i = 1, #text do system.screen.set(x + i - 1, y, text:byte(i), fg, bg) end
end

function system.present() coroutine.yield({id = "present"}) end
function system.sleep(time)
    coroutine.yield({
        id = "sleep",
        time = tonumber(time) or error("sleep expects a numeric value")
    })
end

function system.console.clear()
    for i = 0, system.screen.width * system.screen.height - 1 do
        system.screen.memory[i] = 0x20 +
                                      system.screen
                                          .attrs(system.console.fg,
                                                 system.console.bg)
    end
    system.console.cursor.x = 0
    system.console.cursor.y = 0
end

function system.console.print(...)

    local table = {...}
    local str = ""
    for i = 1, #table do str = str .. tostring(table[i]) end
    --
    local cur = system.console.cursor

    for i = 1, #str do
        local c = str:byte(i)

        if c == 0x0A then
            -- lw
            cur.x = 0
            cur.y = cur.y + 1
        else
            system.screen.set(cur.x, cur.y, c, system.console.fg,
                              system.console.bg)
            cur.x = cur.x + 1
        end
    end
end

function system.console.readLine(prompt)
    prompt = tostring(prompt) or ""
    local string = ""

    local function drawPrompt()
        local y = system.console.cursor.y

        system.screen.put(0, y, (" "):rep(system.screen.width))
        system.screen.put(0, y, prompt .. string)
        system.console.cursor.x = #prompt + #string

        system.present()
    end

    system.console.cursor.visible = true

    local key_lut = {space = " "}

    drawPrompt()
    while true do
        local msg = system.getMessage()
        if msg.type == "kbd.down" then
            -- print(msg.scancode, #msg.scancode, msg.key, #msg.key)
            if #msg.key == 1 or key_lut[msg.scancode] then
                string = string .. (key_lut[msg.scancode] or msg.key)
                drawPrompt()
            elseif msg.scancode == "backspace" then
                string = string:sub(1, #string - 1)
                drawPrompt()
            elseif msg.scancode == "return" then
                system.console.cursor.visible = false
                system.console.print("\n")
                return string
            end
        end

        system.present()
    end
end

function system.console.save()
    return {
        console = deepCopy(system.console),
        buffer = deepCopy(system.screen.buffer)
    }
end

function system.console.restore(state)
    system.console = state.console
    system.screen.buffer = state.buffer
end

function system.console.menu(title, ...)
    local options = {...}

    local previous_state = system.console.save()

    system.console.cursor.visible = false
    system.console.clear()
    system.screen.put(0, 0, title, system.console.bg, system.console.fg)

    local sel = 1
    local scroffset = 0

    local indices = "1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local function indexToString(i)
        if i > #indices then
            return " "
        else
            return indices:sub(i, i)
        end
    end

    for i = 1, #options do
        system.screen.put(0, i, indexToString(i) .. ":" .. options[i],
                          system.console.fg, system.console.bg)
        if i + 1 >= system.screen.height then break end
    end

    system.screen.put(0, sel, indexToString(sel) .. ":", system.console.bg,
                      system.console.fg)

    while true do

        local msg = system.getMessage()

        system.screen.put(0, sel - scroffset, indexToString(sel) .. ":",
                          system.console.fg, system.console.bg)

        if msg.type == "kbd.down" then
            local quick_sel = tonumber(msg.scancode)
            if quick_sel ~= nil and quick_sel >= 1 and quick_sel <= #options then
                system.console.restore(previous_state)
                return quick_sel
            elseif msg.scancode == "down" then
                if sel < #options then sel = sel + 1 end
            elseif msg.scancode == "up" then
                if sel > 1 then sel = sel - 1 end
            elseif msg.scancode == "return" then
                system.console.restore(previous_state)
                return sel
            end
        end

        local dy
        if scroffset + sel >= system.screen.height then
            scroffset = system.screen.height - sel
        elseif sel - scroffset <= 0 then
            scroffset = sel
        end

        system.screen.put(0, sel - scroffset, indexToString(sel) .. ":",
                          system.console.bg, system.console.fg)
    end
end

function system.console.appMenu(items)
    assert(type(items) == "table")

    local previous_state = system.console.save()

    system.console.cursor.visible = false

    local bg = 0x0 -- {love.math.colorFromBytes(20, 12, 28)}, -- #140c1c, black
    local hl = 0xA -- {love.math.colorFromBytes(133, 149, 161)}, -- #8595a1, bright gray
    local fg = 0xF -- {love.math.colorFromBytes(222, 238, 214)} -- #deeed6, white

    local offset = 0

    system.screen.put(0, 0, (" "):rep(system.screen.width), hl, bg)

    if items.app then
        system.screen.put(offset, 0, items.app .. " ", hl, bg)
        offset = #items.app + 1
    end

    for i = 1, #items do
        local menu = items[i]

        system.screen.put(offset, 0, menu.title .. " ", fg, bg)
        offset = offset + 1 + #menu.title
    end

    -- while true do
    --     local msg = system.getMessage()
    --     if msg.type == "kbd.down" then
    --         if msg.scancode == "down" then
    --             if sel < #options then sel = sel + 1 end
    --         elseif msg.scancode == "up" then
    --             if sel > 1 then sel = sel - 1 end
    --         elseif msg.scancode == "return" then
    --             system.console.restore(previous_state)
    --             return sel
    --         end
    --     end
    -- end
end

function system.getMessage() return coroutine.yield({id = "getMessage"}) end

local systemMain_coro

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest", 0)
    love.window.setMode(800, 600, {resizable = false, centered = true})

    font_texture = love.graphics.newImage("res/font.png")

    for i = 0, 255 do
        local x = math.floor(i % 16)
        local y = math.floor(i / 16)
        char_quads[i] = love.graphics.newQuad(1 + 7 * x, 1 + 9 * y, 6, 8,
                                              font_texture)
    end

    system.console.clear()

    screen_canvas = love.graphics.newCanvas(system.screen.width * 6,
                                            system.screen.height * 8)

    systemMain_coro = coroutine.create(system.main)

end

local systemMain_event
local event_queue = nil

local function pushEvent(event)
    assert(type(event) == "table")
    assert(type(event.type) == "string")
    event.next = event_queue
    event_queue = event
end

function love.update(dt)
    local status = coroutine.status(systemMain_coro)
    if status == "suspended" then
        local args
        local sleeping = false
        if systemMain_event == nil then
            -- sleepy
        elseif systemMain_event.id == "present" then
            --
        elseif systemMain_event.id == "getMessage" then
            if event_queue then
                args = event_queue
                event_queue = args.next
                args.next = nil
            else
                sleeping = true
            end
        elseif systemMain_event.id == "sleep" then
            if systemMain_event.time > 0 then sleeping = true end
            systemMain_event.time = systemMain_event.time - dt
        else
            print("unknown event:", systemMain_event)
        end

        if not sleeping then
            local success, event = coroutine.resume(systemMain_coro, args)
            if success then
                systemMain_event = event
            else
                error(event)
            end
        end
    elseif status == "dead" then
        love.event.quit()
    else
        print("unhandled coro status: ", status)
    end
end

function love.keypressed(key, scancode, isrepeat)
    pushEvent {
        type = "kbd.down",
        key = key,
        scancode = scancode,
        repeated = isrepeat
    }
end

function love.keyreleased(key, scancode)
    pushEvent {type = "kbd.up", key = key, scancode = scancode}
end

function love.draw()

    local blink_interval = (love.timer.getTime() % 1.0) > 0.5

    love.graphics.setCanvas(screen_canvas)
    love.graphics.clear(system.palette[system.screen.bg])
    for i = 0, #system.screen.memory do
        local chr = system.screen.memory[i]
        local x = math.floor(i % system.screen.width)
        local y = math.floor(i / system.screen.width)

        local c = bit32.band(chr, 0x00FF)
        local bg = bit32.rshift(bit32.band(chr, 0x0F00), 8)
        local fg = bit32.rshift(bit32.band(chr, 0xF000), 12)

        love.graphics.setColor(system.palette[bg])
        love.graphics.rectangle("fill", 6 * x, 8 * y, 6, 8)

        love.graphics.setColor(system.palette[fg])

        if system.console.cursor.visible and x == system.console.cursor.x and y ==
            system.console.cursor.y and blink_interval then
            love.graphics.draw(font_texture, char_quads[224], 6 * x, 8 * y)
        else
            love.graphics.draw(font_texture, char_quads[c], 6 * x, 8 * y)
        end
    end
    love.graphics.setCanvas()

    love.graphics.clear(system.palette[system.screen.bg])
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(screen_canvas, (800 - screen_canvas:getWidth() * 2) / 2,
                       (600 - screen_canvas:getHeight() * 2) / 2, 0, 2, 2)
end

-- A translation of com32/cmenu/simple.c into Lua

local m = require "cmenu"
local sl = require "syslinux"

m.init()
m.set_window_size(1, 1, 23, 78)
local testing = m.add_named_menu("testing", " Testing ")
-- demonstrate identifying (named) submenu by number:
m.add_item("Self Loop", "Go to testing", m.action.SUBMENU, nil, testing)
m.add_item("Memory Test", "Perform extensive memory testing", m.action.RUN, "memtest")
m.add_item("Exit this menu", "Go one level up", m.action.EXITMENU, "exit")

local rescue = m.add_menu(" Rescue Options ")
m.add_item("Linux Rescue", "linresc", m.action.RUN, "linresc")
m.add_item("Dos Rescue", "dosresc", m.action.RUN, "dosresc")
m.add_item("Windows Rescue", "winresc", m.action.RUN, "winresc")
m.add_item("Exit this menu", "Go one level up", m.action.EXITMENU, "exit")

m.add_named_menu("main", " Main Menu ")
m.add_item("Prepare", "prep", m.action.RUN, "prep")
m.add_item("Rescue options...", "Troubleshoot a system", m.action.SUBMENU, nil, rescue)
-- demonstrate identifying submenu by name:
m.add_item("Testing...", "Options to test hardware", m.action.SUBMENU, "testing")
m.add_item("Exit to prompt", "Exit the menu system", m.action.EXITMENU, "exit")

-- demonstrate finding menu explicitly:
local action, data = m.showmenus(m.find_menu_num("main"))

if action == m.action.RUN then
  sl.run_command (data)
else
  print (action, data)
end

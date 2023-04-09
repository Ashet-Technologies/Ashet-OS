local coolbar = Panel {}
local back_btn = ToolButton { name = "coolbar_backward", icon = "back.abm" }
local fwd_btn = ToolButton { name = "coolbar_forward", icon = "forward.abm" }
local reload_btn = ToolButton { name = "coolbar_reload", icon = "reload.abm" }
local home_btn = ToolButton { name = "coolbar_home", icon = "home.abm" }
local address_bar = TextBox { name = "coolbar_address", max_len = 256 }
local go_button = ToolButton { name = "coolbar_go", icon = "go.abm" }
local menu_button = ToolButton { name = "coolbar_app_menu", icon = "menu.abm" }
local v_scrollbar = ScrollBar { dir = "vertical", range = 1000 }
local h_scrollbar = ScrollBar { dir = "horizontal", range = 1000 }

local document_view = Panel {}

local coolbar_margin = 4

coolbar.left = window.left
coolbar.right = window.right
coolbar.top = window.top
coolbar.bottom = back_btn.bottom + coolbar_margin

v_scrollbar.right = window.right
v_scrollbar.top = coolbar.bottom
v_scrollbar.bottom = window.bottom - 12

h_scrollbar.left = window.left
h_scrollbar.right = window.right - 12
h_scrollbar.bottom = window.bottom

back_btn.left = coolbar.left + coolbar_margin
fwd_btn.left = back_btn.right + coolbar_margin
reload_btn.left = fwd_btn.right + coolbar_margin
home_btn.left = reload_btn.right + coolbar_margin
address_bar.left = home_btn.right + coolbar_margin
address_bar.right = go_button.left - coolbar_margin
go_button.right = menu_button.left - coolbar_margin
menu_button.right = coolbar.right - coolbar_margin

back_btn.top = coolbar.top + coolbar_margin
fwd_btn.top = coolbar.top + coolbar_margin
reload_btn.top = coolbar.top + coolbar_margin
home_btn.top = coolbar.top + coolbar_margin
go_button.top = coolbar.top + coolbar_margin
menu_button.top = coolbar.top + coolbar_margin

address_bar.top = home_btn.top + (home_btn.height - 12) / 2

document_view.left = window.left
document_view.right = v_scrollbar.left
document_view.top = coolbar.bottom
document_view.bottom = h_scrollbar.top

-- constants:
local scrollbar_size = 11
local coolbar_padding = 4
local sidebar_width = 100

-- widgets (bottom to top)

coolbar = Panel {}

nav_backward = ToolButton { name = "nav_backward", icon = "back.abm" }
nav_forward = ToolButton { name = "nav_forward", icon = "forward.abm" }
nav_home = ToolButton { name = "nav_home", icon = "home.abm" }
app_menu = ToolButton { name = "app_menu", icon = "menu.abm" }

tree_scrollbar = ScrollBar { name = "tree_scrollbar", dir = "vertical", range = 1000 }
doc_h_scrollbar = ScrollBar { name = "doc_h_scrollbar", dir = "horizontal", range = 1000 }
doc_v_scrollbar = ScrollBar { name = "doc_v_scrollbar", dir = "vertical", range = 1000 }

tree_view = Panel { name = "tree_view" }
doc_view = Panel { name = "doc_view" }

-- layout:

doc_view.top = coolbar.bottom
doc_view.left = tree_scrollbar.right
doc_view.right = doc_v_scrollbar.left
doc_view.bottom = doc_h_scrollbar.top

nav_backward.top = coolbar.top + coolbar_padding
nav_forward.top = coolbar.top + coolbar_padding
nav_home.top = coolbar.top + coolbar_padding
app_menu.top = coolbar.top + coolbar_padding

nav_backward.left = coolbar.left + coolbar_padding
nav_forward.left = nav_backward.right + coolbar_padding
nav_home.left = nav_forward.right + coolbar_padding
app_menu.right = coolbar.right - coolbar_padding

doc_v_scrollbar.top = coolbar.bottom
doc_v_scrollbar.right = window.right
doc_v_scrollbar.bottom = window.bottom - scrollbar_size

tree_view.left = window.left
tree_view.top = coolbar.bottom
tree_view.bottom = window.bottom
tree_view.width = sidebar_width

tree_scrollbar.left = tree_view.right
tree_scrollbar.top = coolbar.bottom
tree_scrollbar.bottom = window.bottom

doc_h_scrollbar.bottom = window.bottom
doc_h_scrollbar.right = window.right - scrollbar_size
doc_h_scrollbar.left = tree_scrollbar.right

coolbar.left = window.left
coolbar.right = window.right
coolbar.top = window.top
coolbar.bottom = app_menu.bottom + coolbar_padding

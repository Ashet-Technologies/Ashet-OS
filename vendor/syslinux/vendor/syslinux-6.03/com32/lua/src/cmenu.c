#include "cmenu.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static int l_init (lua_State *L)
{
  init_menusystem (luaL_optstring (L, 1, NULL));
  return 0;
}

static int l_set_window_size (lua_State *L)
{
  set_window_size (luaL_checkint (L, 1), luaL_checkint (L, 2),
                   luaL_checkint (L, 3), luaL_checkint (L, 4));
  return 0;
}

static int l_add_menu (lua_State *L)
{
  lua_pushinteger (L, add_menu (luaL_checkstring (L, 1),
                                luaL_optint (L, 2, -1)));
  return 1;
}

static int l_add_named_menu (lua_State *L)
{
  lua_pushinteger (L, add_named_menu (luaL_checkstring (L, 1),
                                      luaL_checkstring (L, 2),
                                      luaL_optint (L, 3, -1)));
  return 1;
}

static int l_add_item (lua_State *L)
{
  add_item (luaL_checkstring (L, 1), luaL_checkstring (L, 2), luaL_checkint (L, 3),
            luaL_optstring (L, 4, NULL), luaL_optint (L, 5, 0));
  return 0; /* FIXME return menuitem for advanced functions */
}

static int l_add_sep (lua_State *L)
{
  add_sep ();
  return 0; /* FIXME return menuitem for advanced functions */
}

static int l_find_menu_num (lua_State *L)
{
  lua_pushinteger (L, find_menu_num (luaL_checkstring (L, 1)));
  return 1;
}

static int l_showmenus (lua_State *L)
{
  t_menuitem *reply = showmenus (luaL_checkint (L, 1));
  if (!reply) return 0;
  lua_pushinteger (L, reply->action);
  lua_pushstring (L, reply->data);
  return 2;
}

static const luaL_Reg menulib[] = {
  {"init", l_init},
  {"set_window_size", l_set_window_size},
  {"add_menu", l_add_menu},
  {"add_named_menu", l_add_named_menu},
  {"add_item", l_add_item},
  {"add_sep", l_add_sep},
  {"find_menu_num", l_find_menu_num},
  {"showmenus", l_showmenus},
  {NULL, NULL}
};

LUALIB_API int luaopen_cmenu (lua_State *L) {
  luaL_newlib(L, menulib);
  lua_newtable (L);
#define export_opt(x) lua_pushinteger (L, OPT_##x); lua_setfield (L, -2, #x);
  export_opt (INACTIVE);
  export_opt (SUBMENU);
  export_opt (RUN);
  export_opt (EXITMENU);
  export_opt (CHECKBOX);
  export_opt (RADIOMENU);
  export_opt (SEP);
  export_opt (INVISIBLE);
  export_opt (RADIOITEM);
  lua_setfield (L, -2, "action");
  return 1;
}

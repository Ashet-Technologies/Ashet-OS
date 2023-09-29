#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "../../include/console.h"
#include "../../lib/sys/vesa/vesa.h"
#include "../../lib/sys/vesa/video.h"

int vesacon_load_background(const char *filename);

static int vesa_getmodes(lua_State *L)
{
  com32sys_t rm;
  uint16_t mode, *mode_ptr;
  struct vesa_general_info *gi;
  struct vesa_mode_info *mi;
  int nmode = 1;
  int rv = -1;

  gi = lmalloc(sizeof *gi);
  if (!gi)
      return -1;

  mi = lmalloc(sizeof *mi);
  if (!mi)
      goto out;

  memset(&rm, 0, sizeof(rm));
  memset(gi, 0, sizeof *gi);

  gi->signature = VBE2_MAGIC;   /* Get VBE2 extended data */
  rm.eax.w[0] = 0x4F00;         /* Get SVGA general information */
  rm.edi.w[0] = OFFS(gi);
  rm.es      = SEG(gi);
  __intcall(0x10, &rm, &rm);

  if ( rm.eax.w[0] != 0x004F )
    goto out;                   /* Function call failed */
  if ( gi->signature != VESA_MAGIC ) {
    rv = -2;                   /* No magic */
    goto out;
  }
  if ( gi->version < 0x0102 ) {
    rv = -3;                   /* VESA 1.2+ required */
    goto out;
  }

  lua_newtable(L);      /* list of modes */

  /* Copy general info */
  memcpy(&__vesa_info.gi, gi, sizeof *gi);

  /* Search for a 640x480 mode with a suitable color and memory model... */

  mode_ptr = GET_PTR(gi->video_mode_ptr);

  while ((mode = *mode_ptr++) != 0xFFFF) {
    mode &= 0x1FF;              /* The rest are attributes of sorts */

    printf("Found mode: 0x%04x (%dx%dx%d)\n", mode, mi->h_res, mi->v_res, mi->bpp);

    memset(&rm, 0, sizeof(rm));
    memset(mi, 0, sizeof *mi);
    rm.eax.w[0] = 0x4F01;       /* Get SVGA mode information */
    rm.ecx.w[0] = mode;
    rm.edi.w[0] = OFFS(mi);
    rm.es  = SEG(mi);
    __intcall(0x10, &rm, &rm);

    /* Must be a supported mode */
    if ( rm.eax.w[0] != 0x004f )
      continue;

    lua_pushnumber(L, nmode++);
    lua_newtable(L); /* mode info */

    lua_pushstring(L, "mode");
    lua_pushnumber(L, mode);
    lua_settable(L,-3);

    lua_pushstring(L, "hres");
    lua_pushnumber(L, mi->h_res);
    lua_settable(L,-3);

    lua_pushstring(L, "vres");
    lua_pushnumber(L, mi->v_res);
    lua_settable(L,-3);

    lua_pushstring(L, "bpp");
    lua_pushnumber(L, mi->bpp);
    lua_settable(L,-3);

    lua_settable(L, -3); /* add to mode list */

  }

  rv = 1;
out:
  lfree(mi);
  lfree(gi);
  return rv;
}


static int vesa_setmode(lua_State *L)
{
  /* Preventing GCC to complain about unused L*/
  L=L;
  openconsole(&dev_rawcon_r, &dev_vesaserial_w);

  return 0;
}


static int vesa_load_background(lua_State *L)
{
  const char *filename = luaL_checkstring(L, 1);

  vesacon_load_background(filename);

  return 0;
}

static const luaL_Reg vesalib[] = {
  {"getmodes", vesa_getmodes},
  {"setmode", vesa_setmode},
  {"load_background", vesa_load_background},
  {NULL, NULL}
};

/* This defines a function that opens up your library. */

LUALIB_API int luaopen_vesa (lua_State *L) {
  luaL_newlib(L, vesalib);
  return 1;
}


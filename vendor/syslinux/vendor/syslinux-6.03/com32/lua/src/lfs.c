/*
** Code implementing read only functionality copied from
** src/lfs.c at commit 2fd989cd6c777583be1c93616018c55b2cbb1bcf:
**
** LuaFileSystem 1.6.2
** Copyright 2003-2014 Kepler Project
** http://www.keplerproject.org/luafilesystem
**
** File system manipulation library.
** This library offers these functions:
** lfs.attributes (filepath [, attributename])
** lfs.chdir (path)
** lfs.currentdir ()
** lfs.dir (path)
**
** $Id: lfs.c,v 1.61 2009/07/04 02:10:16 mascarenhas Exp $
*/

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define chdir_error	strerror(errno)

/* Size of path buffer string, stolen from pwd.c */
#ifndef PATH_MAX
#  ifdef NAME_MAX
#    define PATH_MAX   NAME_MAX
#  elif FILENAME_MAX
#    define PATH_MAX   FILENAME_MAX
#  else
#    define PATH_MAX   256
#  endif       /* NAME_MAX */
#endif /* PATH_MAX */


#define DIR_METATABLE "directory metatable"
typedef struct dir_data {
        int  closed;
        DIR *dir;
} dir_data;


#define STAT_STRUCT struct stat
#define STAT_FUNC stat_via_fstat

/* Emulate stat via fstat */
int stat_via_fstat (const char *path, struct stat *buf)
{
  int fd = open (path, O_RDONLY);
  if (fd == -1) {
    DIR *dir = opendir (path);
    if (!dir) return -1;
    closedir (dir);
    buf->st_mode=S_IFDIR;
    buf->st_size=0;
    return 0;
  }
  if (fstat (fd, buf) == -1) {
    int err = errno;
    close (fd);
    errno = err;
    return -1;
  }
  close (fd);
  return 0;
}

/*
** This function changes the working (current) directory
*/
static int change_dir (lua_State *L) {
        const char *path = luaL_checkstring(L, 1);
        if (chdir(path)) {
                lua_pushnil (L);
                lua_pushfstring (L,"Unable to change working directory to '%s'\n%s\n",
                                path, chdir_error);
                return 2;
        } else {
                lua_pushboolean (L, 1);
                return 1;
        }
}


/*
** This function returns the current directory
** If unable to get the current directory, it returns nil
** and a string describing the error
*/
static int get_dir (lua_State *L) {
  char *path;
  /* Passing (NULL, 0) is not guaranteed to work. Use a temp buffer and size instead. */
  char buf[PATH_MAX];
  if ((path = getcwd(buf, PATH_MAX)) == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
  }
  else {
    lua_pushstring(L, path);
    return 1;
  }
}


/*
** Directory iterator
*/
static int dir_iter (lua_State *L) {
        struct dirent *entry;
        dir_data *d = (dir_data *)luaL_checkudata (L, 1, DIR_METATABLE);
        luaL_argcheck (L, d->closed == 0, 1, "closed directory");
        if ((entry = readdir (d->dir)) != NULL) {
                lua_pushstring (L, entry->d_name);
                return 1;
        } else {
                /* no more entries => close directory */
                closedir (d->dir);
                d->closed = 1;
                return 0;
        }
}


/*
** Closes directory iterators
*/
static int dir_close (lua_State *L) {
        dir_data *d = (dir_data *)lua_touserdata (L, 1);
        if (!d->closed && d->dir) {
                closedir (d->dir);
        }
        d->closed = 1;
        return 0;
}


/*
** Factory of directory iterators
*/
static int dir_iter_factory (lua_State *L) {
        const char *path = luaL_checkstring (L, 1);
        dir_data *d;
        lua_pushcfunction (L, dir_iter);
        d = (dir_data *) lua_newuserdata (L, sizeof(dir_data));
        luaL_getmetatable (L, DIR_METATABLE);
        lua_setmetatable (L, -2);
        d->closed = 0;
        d->dir = opendir (path);
        if (d->dir == NULL)
          luaL_error (L, "cannot open %s: %s", path, strerror (errno));
        return 2;
}


/*
** Creates directory metatable.
*/
static int dir_create_meta (lua_State *L) {
        luaL_newmetatable (L, DIR_METATABLE);

        /* Method table */
        lua_newtable(L);
        lua_pushcfunction (L, dir_iter);
        lua_setfield(L, -2, "next");
        lua_pushcfunction (L, dir_close);
        lua_setfield(L, -2, "close");

        /* Metamethods */
        lua_setfield(L, -2, "__index");
        lua_pushcfunction (L, dir_close);
        lua_setfield (L, -2, "__gc");
        return 1;
}


/*
** Convert the inode protection mode to a string.
*/
static const char *mode2string (mode_t mode) {
  if ( S_ISREG(mode) )
    return "file";
  else if ( S_ISDIR(mode) )
    return "directory";
  else if ( S_ISLNK(mode) )
        return "link";
  else if ( S_ISSOCK(mode) )
    return "socket";
  else if ( S_ISFIFO(mode) )
        return "named pipe";
  else if ( S_ISCHR(mode) )
        return "char device";
  else if ( S_ISBLK(mode) )
        return "block device";
  else
        return "other";
}


/* inode protection mode */
static void push_st_mode (lua_State *L, STAT_STRUCT *info) {
        lua_pushstring (L, mode2string (info->st_mode));
}
/* file size, in bytes */
static void push_st_size (lua_State *L, STAT_STRUCT *info) {
        lua_pushnumber (L, (lua_Number)info->st_size);
}
static void push_invalid (lua_State *L, STAT_STRUCT *info) {
  luaL_error(L, "invalid attribute name");
  info->st_size = 0; /* never reached */
}

typedef void (*_push_function) (lua_State *L, STAT_STRUCT *info);

struct _stat_members {
        const char *name;
        _push_function push;
};

struct _stat_members members[] = {
        { "mode",         push_st_mode },
        { "size",         push_st_size },
        { NULL, push_invalid }
};

/*
** Get file or symbolic link information
*/
static int _file_info_ (lua_State *L, int (*st)(const char*, STAT_STRUCT*)) {
        int i;
        STAT_STRUCT info;
        const char *file = luaL_checkstring (L, 1);

        if (st(file, &info)) {
                lua_pushnil (L);
                lua_pushfstring (L, "cannot obtain information from file `%s'", file);
                return 2;
        }
        if (lua_isstring (L, 2)) {
                int v;
                const char *member = lua_tostring (L, 2);
                if (strcmp (member, "mode") == 0) v = 0;
#ifndef _WIN32
                else if (strcmp (member, "blocks")  == 0) v = 11;
                else if (strcmp (member, "blksize") == 0) v = 12;
#endif
                else /* look for member */
                        for (v = 1; members[v].name; v++)
                                if (*members[v].name == *member)
                                        break;
                /* push member value and return */
                members[v].push (L, &info);
                return 1;
        } else if (!lua_istable (L, 2))
                /* creates a table if none is given */
                lua_newtable (L);
        /* stores all members in table on top of the stack */
        for (i = 0; members[i].name; i++) {
                lua_pushstring (L, members[i].name);
                members[i].push (L, &info);
                lua_rawset (L, -3);
        }
        return 1;
}


/*
** Get file information using stat.
*/
static int file_info (lua_State *L) {
        return _file_info_ (L, STAT_FUNC);
}


static const struct luaL_Reg fslib[] = {
        {"attributes", file_info},
        {"chdir", change_dir},
        {"currentdir", get_dir},
        {"dir", dir_iter_factory},
        {NULL, NULL},
};

LUALIB_API int luaopen_lfs (lua_State *L) {
  dir_create_meta (L);
  luaL_newlib (L, fslib);
  return 1;
}

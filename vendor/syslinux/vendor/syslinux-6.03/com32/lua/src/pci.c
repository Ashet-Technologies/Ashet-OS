#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define lpcilib_c       /* Define the library */

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <sys/pci.h>

/* removing any \n found in a string */
static void remove_eol(char *string)
{
    int j = strlen(string);
    int i = 0;
    for (i = 0; i < j; i++)
        if (string[i] == '\n')
            string[i] = 0;
}

static int pci_getinfo(lua_State *L)
{
  struct pci_domain *pci_domain;
  struct pci_device *pci_device;
  int pci_dev = 1;

  pci_domain = pci_scan();

  lua_newtable(L);	/* list of busses */

  for_each_pci_func(pci_device, pci_domain) {
    lua_pushnumber(L, pci_dev++);

    lua_newtable(L); /* device infos */

    lua_pushstring(L, "bus");
    lua_pushnumber(L, __pci_bus);
    lua_settable(L,-3);

    lua_pushstring(L, "slot");
    lua_pushnumber(L, __pci_slot);
    lua_settable(L,-3);

    lua_pushstring(L, "func");
    lua_pushnumber(L, __pci_func);
    lua_settable(L,-3);

    lua_pushstring(L, "vendor");
    lua_pushnumber(L, pci_device->vendor);
    lua_settable(L,-3);

    lua_pushstring(L, "product");
    lua_pushnumber(L, pci_device->product);
    lua_settable(L,-3);

    lua_pushstring(L, "sub_vendor");
    lua_pushnumber(L, pci_device->sub_vendor);
    lua_settable(L,-3);

    lua_pushstring(L, "sub_product");
    lua_pushnumber(L, pci_device->sub_product);
    lua_settable(L,-3);

    lua_settable(L,-3); /* end device infos */
  }

  return 1;
}

/* Try to match any pci device to the appropriate kernel module */
/* it uses the modules.pcimap from the boot device*/
static int pci_getidlist(lua_State *L)
{
  const char *pciidfile;
  char line[1024];
  char vendor[255];
  char vendor_id[5];
  char product[255];
  char productvendor[9];
  char productvendorsub[17];
  FILE *f;

  if (lua_gettop(L) == 1) {
    pciidfile = luaL_checkstring(L, 1);
  } else {
    pciidfile = "pci.ids";
  }

  lua_newtable(L);	/* list of vendors */

  /* Opening the pci.ids from the boot device*/
  f=fopen(pciidfile,"r");
  if (!f)
        return -1;

  /* for each line we found in the pci.ids*/
  while ( fgets(line, sizeof line, f) ) {
    /* Skipping uncessary lines */
    if ((line[0] == '#') || (line[0] == ' ') || (line[0] == 'C') ||
	(line[0] == 10))
        continue;

    /* If the line doesn't start with a tab, it means that's a vendor id */
    if (line[0] != '\t') {

	/* the 4th first chars are the vendor_id */
        strlcpy(vendor_id,line,4);

	/* the vendor name is the next field*/
        vendor_id[4]=0;
        strlcpy(vendor,skipspace(strstr(line," ")),255);
        remove_eol(vendor);

	/* ffff is an invalid vendor id */
	if (strstr(vendor_id,"ffff")) break;

	lua_pushstring(L, vendor_id);
	lua_pushstring(L, vendor);
	lua_settable(L,-3);

    /* if we have a tab + a char, it means this is a product id */
    } else if ((line[0] == '\t') && (line[1] != '\t')) {

	/* the product name the second field */
        strlcpy(product,skipspace(strstr(line," ")),255);
        remove_eol(product);

	/* the 4th first chars are the vendor_id */
	strlcpy(productvendor,vendor_id,4);
	/* the product id is first field */
	strlcpy(productvendor+4,&line[1],4);
        productvendor[8]=0;

	lua_pushstring(L, productvendor);
	lua_pushstring(L, product);
	lua_settable(L,-3);

    /* if we have two tabs, it means this is a sub product */
    } else if ((line[0] == '\t') && (line[1] == '\t')) {

      /* the product name is last field */
      strlcpy(product,skipspace(strstr(line," ")),255);
      strlcpy(product,skipspace(strstr(product," ")),255);
      remove_eol(product);

      strlcpy(productvendorsub, productvendor,8);
      strlcpy(productvendorsub+8, &line[2],4);
      strlcpy(productvendorsub+12, &line[7],4);
      productvendorsub[16]=0;

      lua_pushstring(L, productvendorsub);
      lua_pushstring(L, product);
      lua_settable(L,-3);

    }
  }
  fclose(f);
  return(1);
}

static const luaL_Reg pcilib[] = {
  {"getinfo", pci_getinfo},
  {"getidlist", pci_getidlist},
  {NULL, NULL}
};

/* This defines a function that opens up your library. */

LUALIB_API int luaopen_pci (lua_State *L) {
  luaL_newlib(L, pcilib);
  return 1;
}


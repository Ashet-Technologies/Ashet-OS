/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2007 H. Peter Anvin - All Rights Reserved
 *   Copyright 2011 Timothy J Gleason <timmgleason_at_gmail.com> - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

/*
 * dhcp.c
 *
 * Adds DHCPINFO functionality to the lua.c32 binary
 *
 * gettable() returns a table of the BOOTP message fields returned by
 * the DHCP server for use in a Lua pxeboot script
 * See http://tools.ietf.org/html/rfc1542
 *
 *	lua key value		RFC key
 * ----------------------------------------------------------------------- 
 *	opcode			op	 message opcode 
 *	hardware.type		htype	 Hardware address type 
 *	hardware.length		hlen	 Hardware address length 
 *	hops			hops	 Used by relay agents 
 *	transaction.id		xid	 transaction id 
 *	elapsed.seconds		secs	 Secs elapsed since client boot 
 *	flags			flags	 DHCP Flags field 
 *	client.ip.addr		ciaddr	 client IP addr 
 *	your.ip.addr		yiaddr	 'Your' IP addr. (from server) 
 *	server.ip.addr		siaddr	 Boot server IP addr 
 *	gateway.ip.addr		giaddr	 Relay agent IP addr 
 *	client.mac		chaddr	 Client hardware addr 
 *	server.hostname		sname	 Optl. boot server hostname 
 * 	boot.file		file	 boot file name (ascii path) 
 *	magic.cookie		cookie	 Magic cookie 
 *
 * getoptions() returns a table of the DHCP Options field of the BOOTP
 * message returned by the DHCP server for use in a Lua pxeboot script.
 * Many of the options are reurned formatted in as strings in a standard,
 * recognizable format, such as IP addresses.
 *
 * 1, 2, and 4 byte numerical options are returned as integers. 
 *
 * Other Options with non-standard formats are returned as strings of the 
 * raw binary number that was returned by the DHCP server and must be decoded
 * in a Lua script 
 *
 * The Options table returns the Option code as the key except where there
 * are multiple values returned. In those cases, an extra key increment number
 * is added to allow individual access to each Option value.
 * 
 *	lua key value		value Name
 * ----------------------------------------------------------------------- 
 *	1			Subnet Mask
 *	6.1			DNS Server [element 1]
 *	6.2			DNS Server [element 2]
 *	6.3			DNS Server [element 3]
 *	209			PXE Configuration File
 *	21.1			Policy Filter [element 1]
 *	21.2			Policy Filter [element 2]
 *	
 * Options that can have a list of values, but contain only one (like Option 6)
 * will not return with .sub key values.	
 *
 * Usage:
            t = dhcp.gettable()

            for k,v in pairs(t) do
              print(k.." : "..v)
            end
 */

#include <stdio.h>
#include "dhcp.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <syslinux/pxe.h>

#define STR_BUF_SIZE	129 /* Sized to accomdate File field in BOOTP message */

void
ip_address_list(lua_State *L, uint8_t* value, uint8_t len, uint8_t option )
{
  static char	op_name[64];
  static char	op_value[255];
  int		loop;

  loop = len/4;

  if ( loop == 1) {
    sprintf(op_name, "%u", option);
    lua_pushstring(L, op_name);
    sprintf(op_value, "%u.%u.%u.%u", value[0], value[1], value[2], value[3]);
    lua_pushstring(L, op_value);
    lua_settable(L,-3);
  } else {
      for (int done = 0; done < loop; done++){
	sprintf(op_name, "%u.%d", option, done+1);
	lua_pushstring(L, op_name);
	sprintf(op_value, "%u.%u.%u.%u", value[0+(done*4)], value[1+(done*4)], value[2+(done*4)], value[3+(done*4)]);
	lua_pushstring(L, op_value);
	lua_settable(L,-3);
      }
  }

}

static int dhcp_getoptions(lua_State *L)
{
  void*		dhcpdata = 0;
  dhcp_t*	dhcp = 0;
  size_t	dhcplen = 0;

  /* Append the DHCP info */
  if (pxe_get_cached_info(PXENV_PACKET_TYPE_DHCP_ACK,
    &dhcpdata, &dhcplen))
  {
    return 0;
  }

  dhcp = (dhcp_t*)dhcpdata;

  lua_newtable(L);

  int		done = 0;
  uint8_t*	ptr = (uint8_t*)&dhcp->options;
  uint8_t	len;
  uint8_t	option;
  uint8_t*	value;
  static char	op_name[64];

  do {
      option = *ptr++;
      len = *ptr++;
      value = ptr;
      ptr += len;
      switch (option) {
// IP Address formatted lists, including singles
	case 1:
	case 3:
	case 4:
	case 5:
	case 6:
	case 7:
	case 8:
	case 9:
	case 10:
	case 11:
	case 16:
	case 21: /* Policy Filters - address/mask */
	case 28:
	case 32:
	case 33: /* Static routes - destination/router */
	case 41:
	case 42:
	case 44:
	case 45:
	case 47:
	case 48:
	case 49:
	case 50:
	case 51:
	case 54:
	case 65:
	case 68:
	case 69:
	case 70:
	case 71:
	case 72:
	case 73:
	case 74:
	case 75:
	case 76:
	  ip_address_list(L, value, len, option);
          break;
// 4byte options - numerical
        case 2:
        case 24:
        case 35:
        case 38:
        case 58:
        case 59:
        case 211:
	  sprintf(op_name, "%u", option);
	  lua_pushstring(L, op_name);
	  lua_pushinteger(L, ntohl(*(long*)value));
	  lua_settable(L,-3);
          break;
// 2byte options -numerical
        case 13:
        case 22:
        case 26:
        case 57:
	  sprintf(op_name, "%u", option);
	  lua_pushstring(L, op_name);
	  lua_pushinteger(L, ntohs(*(short*)value));
	  lua_settable(L,-3);
          break;
// 1byte options - numerical
        case 19:
        case 20:
        case 23:
        case 27:
        case 29:
        case 30:
        case 31:
        case 34:
        case 36:
        case 37:
        case 39:
        case 46:
        case 52:
        case 53:
	  sprintf(op_name, "%u", option);
	  lua_pushstring(L, op_name);
	  lua_pushinteger(L, *value);
	  lua_settable(L,-3);
          break;
        case 255: 
          done = 1;
	  break;
        default:
	  sprintf(op_name, "%u", option);
	  lua_pushstring(L, op_name);
	  lua_pushlstring(L, (const char*)value, len);
	  lua_settable(L,-3);
          break;
      }

    } while (!done);

  return 1;
}

static int	dhcp_gettable(lua_State *L)
{
  void*		dhcpdata = 0;
  dhcp_t*	dhcp = 0;
  size_t	dhcplen = 0;
  static char	dhcp_arg[STR_BUF_SIZE];

  /* Append the DHCP info */
  if (pxe_get_cached_info(PXENV_PACKET_TYPE_DHCP_ACK,
    &dhcpdata, &dhcplen))
  {
    return 0;
  }

  dhcp = (dhcp_t*)dhcpdata;


  lua_newtable(L);

  lua_pushstring(L, "opcode");
  lua_pushinteger(L, dhcp->op);
  lua_settable(L,-3);

  lua_pushstring(L, "hardware.type");
  lua_pushinteger(L, dhcp->htype);
  lua_settable(L,-3);

  lua_pushstring(L, "hardware.length");
  lua_pushinteger(L, dhcp->hlen);
  lua_settable(L,-3);

  lua_pushstring(L, "hops");
  lua_pushinteger(L, dhcp->hops);
  lua_settable(L,-3);

  lua_pushstring(L, "transaction.id");
  lua_pushinteger(L, ntohl(dhcp->xid));
  lua_settable(L,-3);

  lua_pushstring(L, "elapsed.seconds");
  lua_pushinteger(L, ntohs(dhcp->secs));
  lua_settable(L,-3);

  lua_pushstring(L, "flags");
  lua_pushinteger(L, ntohs(dhcp->flags));
  lua_settable(L,-3);

  sprintf(dhcp_arg, "%u.%u.%u.%u", dhcp->ciaddr[0], dhcp->ciaddr[1], dhcp->ciaddr[2], dhcp->ciaddr[3]);
  lua_pushstring(L, "client.ip.addr");
  lua_pushstring(L, dhcp_arg);
  lua_settable(L,-3);

  sprintf(dhcp_arg, "%u.%u.%u.%u", dhcp->yiaddr[0], dhcp->yiaddr[1], dhcp->yiaddr[2], dhcp->yiaddr[3]);
  lua_pushstring(L, "your.ip.addr");
  lua_pushstring(L, dhcp_arg);
  lua_settable(L,-3);

  sprintf(dhcp_arg, "%u.%u.%u.%u", dhcp->siaddr[0], dhcp->siaddr[1], dhcp->siaddr[2], dhcp->siaddr[3]);
  lua_pushstring(L, "server.ip.addr");
  lua_pushstring(L, dhcp_arg);
  lua_settable(L,-3);

  sprintf(dhcp_arg, "%u.%u.%u.%u", dhcp->giaddr[0], dhcp->giaddr[1], dhcp->giaddr[2], dhcp->giaddr[3]);
  lua_pushstring(L, "gateway.ip.addr");
  lua_pushstring(L, dhcp_arg);
  lua_settable(L,-3);

  sprintf(dhcp_arg, "%02X:%02X:%02X:%02X:%02X:%02X",
                    dhcp->chaddr[0], dhcp->chaddr[1], dhcp->chaddr[2],
                    dhcp->chaddr[3], dhcp->chaddr[4], dhcp->chaddr[5]);
  lua_pushstring(L, "client.mac");
  lua_pushstring(L, dhcp_arg);
  lua_settable(L,-3);

  snprintf(dhcp_arg, STR_BUF_SIZE, "%s", dhcp->sname);
  dhcp_arg[STR_BUF_SIZE-1] = 0; 	/* Guarantee for lua_pushstring that dhcp_arg is 0 terminated /*/
  lua_pushstring(L, "server.hostname");
  lua_pushstring(L, dhcp_arg);
  lua_settable(L,-3);

  snprintf(dhcp_arg, STR_BUF_SIZE, "%s", dhcp->file);
  dhcp_arg[STR_BUF_SIZE-1] = 0; 	/* Guarantee for lua_pushstring that dhcp_arg is 0 terminated /*/
  lua_pushstring(L, "boot.file");
  lua_pushstring(L, dhcp_arg);
  lua_settable(L,-3);

  sprintf(dhcp_arg, "%u.%u.%u.%u", dhcp->cookie[0], dhcp->cookie[1], dhcp->cookie[2], dhcp->cookie[3]);
  lua_pushstring(L, "magic.cookie");
  lua_pushstring(L, dhcp_arg);
  lua_settable(L,-3);

  return 1;
}

static const luaL_Reg dhcplib[] = {
  {"gettable", dhcp_gettable},
  {"getoptions", dhcp_getoptions},
  {NULL, NULL}
};

LUALIB_API int luaopen_dhcp (lua_State *L) {
  luaL_newlib(L, dhcplib);
  return 1;
}

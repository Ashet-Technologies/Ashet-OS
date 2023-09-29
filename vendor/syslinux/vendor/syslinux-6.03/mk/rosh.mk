## -*- makefile -*- -------------------------------------------------------
##
##   Copyright 2008 H. Peter Anvin - All Rights Reserved
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
##   Boston MA 02110-1301, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## COM32 GRC configurables
##

## Include the COM32 common configurables
include $(MAKEDIR)/elf.mk

# CFLAGS     = $(GCCOPT) $(GCCWARN) -march=i386 \
# 	     -fomit-frame-pointer -D__COM32__ -D__FIRMWARE_$(FIRMWARE)__ \
# 	     -nostdinc -iwithprefix include \
# 	     -I$(com32)/libutil/include -I$(com32)/include
# 	 -g3 -dD

# LNXCFLAGS  = -I$(com32)/libutil/include $(GCCWARN) -O -g3 -D_GNU_SOURCE -dD
# 	 -U__GNUC__

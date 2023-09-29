SUBDIRS = mbr geodsp

all tidy dist clean spotless install:
	@mkdir -p $(addprefix $(OBJ)/,$(SUBDIRS))
	set -e; for d in $(SUBDIRS); \
		do $(MAKE) -C $(OBJ)/$$d -f $(SRC)/$$d/Makefile \
		SRC="$(SRC)"/$$d OBJ="$(OBJ)"/$$d $@; done

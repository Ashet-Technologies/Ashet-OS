include $(MAKEDIR)/syslinux.mk

OPTFLAGS = -g -Os
INCLUDES = -I$(SRC) -I$(objdir) -I$(SRC)/../libfat -I$(SRC)/../libinstaller
CFLAGS	 = $(GCCWARN) -D_FILE_OFFSET_BITS=64 $(OPTFLAGS) $(INCLUDES)
LDFLAGS	 = 

SRCS     = syslinux.c \
	   ../libinstaller/fs.c \
	   ../libinstaller/syslxmod.c \
	   ../libinstaller/syslxopt.c \
	   ../libinstaller/setadv.c \
	   ../libinstaller/bootsect_bin.c \
	   ../libinstaller/ldlinux_bin.c \
	   ../libinstaller/ldlinuxc32_bin.c \
	   $(wildcard $(SRC)/../libfat/*.c)
OBJS	 = $(patsubst %.c,%.o,$(notdir $(SRCS)))

.SUFFIXES: .c .o .i .s .S

VPATH = $(SRC):$(SRC)/../libfat:$(SRC)/../libinstaller:$(OBJ)/../libinstaller

all: installer

tidy dist:
	-rm -f *.o *.i *.s *.a .*.d *.tmp

clean: tidy
	-rm -f syslinux

spotless: clean
	-rm -f *~

installer: syslinux

syslinux: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

strip:
	$(STRIP) syslinux

%.o: %.c
	$(CC) $(UMAKEDEPS) $(CFLAGS) -c -o $@ $<
%.i: %.c
	$(CC) $(UMAKEDEPS) $(CFLAGS) -E -o $@ $<
%.s: %.c
	$(CC) $(UMAKEDEPS) $(CFLAGS) -S -o $@ $<

-include .*.d

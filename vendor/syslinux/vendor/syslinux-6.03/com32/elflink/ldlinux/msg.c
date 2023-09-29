#include <syslinux/video.h>
#include <com32.h>
#include <stdio.h>
#include <bios.h>
#include <graphics.h>

static uint8_t TextAttribute;	/* Text attribute for message file */
extern uint8_t DisplayMask;	/* Display modes mask */

/* Routine to interpret next print char */
static void (*NextCharJump)(uint8_t);

void msg_initvars(void);
static void msg_setfg(uint8_t data);
static void msg_putchar(uint8_t ch);

/*
 *
 * get_msg_file: Load a text file and write its contents to the screen,
 *               interpreting color codes.
 *
 * Returns 0 on success, -1 on failure.
 */
int get_msg_file(char *filename)
{
	FILE *f;
	char ch;

	f = fopen(filename, "r");
	if (!f)
		return -1;

	TextAttribute = 0x7;	/* Default grey on white */
	DisplayMask = 0x7;	/* Display text in all modes */
	msg_initvars();

	/*
	 * Read the text file a byte at a time and interpret that
	 * byte.
	 */
	while ((ch = getc(f)) != EOF) {
		/* DOS EOF? */
		if (ch == 0x1A)
			break;

		NextCharJump(ch);	/* Do what shall be done */
	}

	DisplayMask = 0x07;

	fclose(f);
	return 0;
}

static inline int display_mask_vga(void)
{
	uint8_t mask = UsingVGA & 0x1;
	return (DisplayMask & ++mask);
}

static void msg_setbg(uint8_t data)
{
	if (unhexchar(&data) == 0) {
		data <<= 4;
		if (display_mask_vga())
			TextAttribute = data;

		NextCharJump = msg_setfg;
	} else {
		TextAttribute = 0x7;	/* Default attribute */
		NextCharJump = msg_putchar;
	}
}

static void msg_setfg(uint8_t data)
{
	if (unhexchar(&data) == 0) {
		if (display_mask_vga()) {
			/* setbg set foreground to 0 */
			TextAttribute |= data;
		}
	} else
		TextAttribute = 0x7;	/* Default attribute */

	NextCharJump = msg_putchar;
}

static inline void msg_ctrl_o(void)
{
	NextCharJump = msg_setbg;
}

/* Convert ANSI colors to PC display attributes */
static int convert_to_pcdisplay[] = { 0, 4, 2, 6, 1, 5, 3, 7 };

static void set_fgbg(void)
{
	uint8_t bg, fg;

	fg = convert_to_pcdisplay[(TextAttribute & 0x7)];
	bg = convert_to_pcdisplay[((TextAttribute >> 4) & 0x7)];

	printf("\033[");
	if (TextAttribute & 0x8)
		printf("1;"); /* Foreground bright */

	printf("3%dm\033[", fg);

	if (TextAttribute & 0x80)
		printf("5;"); /* Foreground blink */

	printf("4%dm", bg);
}

static void msg_formfeed(void)
{
	set_fgbg();
	printf("\033[2J\033[H\033[0m");
}

static void msg_novga(void)
{
	syslinux_force_text_mode();
	msg_initvars();
}

static void msg_viewimage(void)
{
	FILE *f;

	*VGAFilePtr = '\0';	/* Zero-terminate filename */

	mangle_name(VGAFileMBuf, VGAFileBuf);
	f = fopen(VGAFileMBuf, "r");
	if (!f) {
		/* Not there */
		NextCharJump = msg_putchar;
		return;
	}

	vgadisplayfile(f);
	fclose(f);
	msg_initvars();
}

/*
 * Getting VGA filename
 */
static void msg_filename(uint8_t data)
{
	/* <LF> = end of filename */
	if (data == 0x0A) {
		msg_viewimage();
		return;
	}

	/* Ignore space/control char */
	if (data > ' ') {
		if ((char *)VGAFilePtr < (VGAFileBuf + sizeof(VGAFileBuf)))
			*VGAFilePtr++ = data;
	}
}

static void msg_vga(void)
{
	NextCharJump = msg_filename;
	VGAFilePtr = (uint16_t *)VGAFileBuf;
}

static void msg_normal(uint8_t data)
{
	/* 0x1 = text mode, 0x2 = graphics mode */
	if (!display_mask_vga() || !(DisplayCon & 0x01)) {
		/* Write to serial port */
		if (DisplayMask & 0x4)
			write_serial(data);

		return;		/* Not screen */
	}

	set_fgbg();
	printf("%c\033[0m", data);
}

static void msg_modectl(uint8_t data)
{
	data &= 0x07;
	DisplayMask = data;
	NextCharJump = msg_putchar;
}

static void msg_putchar(uint8_t ch)
{
	/* 10h to 17h are mode controls */
	if (ch >= 0x10 && ch < 0x18) {
		msg_modectl(ch);
		return;
	}

	switch (ch) {
	case 0x0F:		/* ^O = color code follows */
		msg_ctrl_o();
		break;
	case 0x0D:		/* Ignore <CR> */
		break;
	case 0x0C:		/* <FF> = clear screen */
		msg_formfeed();
		break;
	case 0x19:		/* <EM> = return to text mode */
		msg_novga();
		break;
	case 0x18:		/* <CAN> = VGA filename follows */
		msg_vga();
		break;
	default:
		msg_normal(ch);
		break;
	}
}

/*
 * Subroutine to initialize variables, also needed after loading
 * graphics file.
 */
void msg_initvars(void)
{
	/* Initialize state machine */
	NextCharJump = msg_putchar;
}

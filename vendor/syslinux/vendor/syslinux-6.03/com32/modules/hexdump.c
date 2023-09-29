#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <console.h>
#include <errno.h>
#include <syslinux/loadfile.h>

/* Macros */
#define ROWS_PER_PAGE 24
#define COLS_PER_ROW 16
#define BYTES_PER_PAGE (ROWS_PER_PAGE * COLS_PER_ROW)

/* Functions declarations */
static int usage(void);
static void eat_stdin(void);
static int do_page(void);
static void hexdump(const void *memory, size_t bytes);

/* Objects */
static const char *prog_name;
static int opt_page;
static int opt_no_buffer;
static int opt_extended_ascii;

int main(int argc, char **argv)
{
    int rc;
    const char *filename;
    int i;
    void *file_data;
    size_t file_sz;
    FILE *f;
    size_t len;
    const char *cur_pos;

    /* Assume failure */
    rc = EXIT_FAILURE;

    /* Determine the program name, as invoked */
    if (argc < 1 || !argv || !argv[0]) {
	fprintf(stderr, "argc or argv failure!\n");
	goto err_prog_name;
    }
    prog_name = argv[0];

    /* Process arguments */
    filename = NULL;
    for (i = 1; i < argc; ++i) {
	if (!argv[i]) {
	    fprintf(stderr, "argc and argv mismatch!\n");
	    goto err_argv;
	}

	if (!strncmp(argv[i], "--page", sizeof "--page") ||
	    !strncmp(argv[i], "-p", sizeof "-p")) {
	    opt_page = 1;
	    continue;
	}

	if (!strncmp(argv[i], "--no-buffer", sizeof "--no-buffer")) {
	    opt_no_buffer = 1;
	    continue;
	}

	if (!strncmp(argv[i], "--extended-ascii", sizeof "--extended-ascii")) {
	    opt_extended_ascii = 1;
	    continue;
	}

	if (!strncmp(argv[i], "--help", sizeof "--help") ||
	    !strncmp(argv[i], "-h", sizeof "-h") ||
	    !strncmp(argv[i], "-?", sizeof "-?"))
	    return usage();

	/* Otherwise, interpret as a filename, but only accept one */
	if (filename)
	    return usage();
	filename = argv[i];
    }
    if (!filename)
	return usage();
    fprintf(stdout, "Dumping file: %s\n", filename);

    /* Either fetch the whole file, or just allocate a buffer */
    f = NULL;
    if (opt_no_buffer) {
	errno = 0;
	if (loadfile(filename, &file_data, &file_sz)) {
	    fprintf(stderr, "Couldn't load file.  Error: %d\n", errno);
	    goto err_file_data;
	}
    } else {
	file_sz = BYTES_PER_PAGE;
	file_data = malloc(file_sz);
	if (!file_data) {
	    fprintf(stderr, "Couldn't allocate file data buffer\n");
	    goto err_file_data;
	}
	errno = 0;
	f = fopen(filename, "r");
	if (!f) {
	    fprintf(stderr, "Couldn't open file.  Error: %d\n", errno);
	    goto err_f;
	}
    }

    /* Dump the data */
    len = BYTES_PER_PAGE;
    cur_pos = file_data;
    do {
	if (f) {
	    /* Buffered */
	    len = fread(file_data, 1, file_sz, f);
	    cur_pos = file_data;
	} else {
	    /* Non-buffered */
	    if (file_sz < len)
		len = file_sz;
	}
	if (!len)
	    break;

	hexdump(cur_pos, len);

	/* Pause, if requested */
	if (opt_page) {
	    /* The user might choose to quit */
	    if (do_page())
		break;
	}

	/* Reduce file_sz for non-buffered mode */
	if (!f)
	    file_sz -= len;
    } while (cur_pos += len);

    rc = EXIT_SUCCESS;

    if (f)
	fclose(f);
    err_f:

    free(file_data);
    err_file_data:

    err_argv:

    err_prog_name:

    return rc;
}

static int usage(void)
{
    static const char usage[] =
	"Usage: %s [<option> [...]] <filename> [<option> [...]]\n"
	"\n"
	"Options: -p\n"
	"         --page . . . . . . . Pause output every 24 lines\n"
	"         --no-buffer . . . .  Load the entire file before dumping\n"
	"         --extended-ascii . . Use extended ASCII chars in dump\n"
	"         -?\n"
	"         -h\n"
	"         --help  . . . . . .  Display this help\n";

    fprintf(stderr, usage, prog_name);
    return EXIT_FAILURE;
}

static void eat_stdin(void)
{
    int i;

    while (1) {
	i = fgetc(stdin);
	if (i == EOF || i == '\n')
	    return;
    }
}
static int do_page(void)
{
    int i;

    while (1) {
	fprintf(stdout, "Continue? [Y|n]: ");
	i = fgetc(stdin);
	switch (i) {
	    case 'n':
	    case 'N':
	    eat_stdin();
	    return 1;

	    case EOF:
	    fprintf(stderr, "No response.  Continuing...\n");
	    /* Fall through to "yes" */

	    case 'y':
	    case 'Y':
	    eat_stdin();
	    case '\n':
	    return 0;

	    default:
	    fprintf(stderr, "Invalid choice\n");
	    eat_stdin();
	}
    }
}

static void hexdump(const void *memory, size_t bytes)
{
    const unsigned char *p, *q;
    int i;
 
    p = memory;
    while (bytes) {
        q = p;
        printf("%p: ", (void *) p);
        for (i = 0; i < 16 && bytes; ++i) {
            printf("%02X ", *p);
            ++p;
            --bytes;
          }
        bytes += i;
        while (i < 16) {
            printf("XX ");
            ++i;
          }
        printf("| ");
        p = q;
        for (i = 0; i < 16 && bytes; ++i) {
            printf("%c", isprint(*p) && !isspace(*p) ? *p : ' ');
            ++p;
            --bytes;
          }
        while (i < 16) {
            printf(" ");
            ++i;
          }
        printf("\n");
      }
    return;
}

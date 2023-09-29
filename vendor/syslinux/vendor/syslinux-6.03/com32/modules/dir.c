/*
 * Display directory contents
 */
#include <stdlib.h>
#include <stdio.h>
#include <console.h>
#include <string.h>
#include <com32.h>
#include <dirent.h>
#include <minmax.h>
#include <unistd.h>
#include <getkey.h>

static int rows, cols;		/* Screen parameters */

#define DIR_CHUNK	1024

static const char *type_str(int type)
{
    switch (type) {
    case DT_FIFO:
	return "[fif]";
    case DT_CHR:
	return "[chr]";
    case DT_DIR:
	return "[dir]";
    case DT_BLK:
	return "[blk]";
    case DT_UNKNOWN:
    case DT_REG:
	return "";
    case DT_LNK:
	return "[lnk]";
    case DT_SOCK:
	return "[sck]";
    case DT_WHT:
	return "[wht]";
    default:
	return "[???]";
    }
}

static void free_dirents(struct dirent **dex, size_t n_de)
{
    size_t i;

    for (i = 0; i < n_de; i++)
	free(dex[i]);

    free(dex);
}

static int compare_dirent(const void *p_de1, const void *p_de2)
{
    const struct dirent *de1 = *(const struct dirent **)p_de1;
    const struct dirent *de2 = *(const struct dirent **)p_de2;
    int ndir1, ndir2;

    ndir1 = de1->d_type != DT_DIR;
    ndir2 = de2->d_type != DT_DIR;

    if (ndir1 != ndir2)
	return ndir1 - ndir2;

    return strcmp(de1->d_name, de2->d_name);
}

static int display_directory(const char *dirname)
{
    DIR *dir;
    struct dirent *de;
    struct dirent **dex = NULL;
    size_t n_dex = 0, n_de = 0;
    size_t i, j, k;
    size_t nrows, ncols, perpage;
    size_t endpage;
    int maxlen = 0;
    int pos, tpos, colwidth;

    dir = opendir(dirname);
    if (!dir) {
	printf("Unable to read directory: %s\n", dirname);
	return -1;
    }

    while ((de = readdir(dir)) != NULL) {
	struct dirent *nde;

	if (n_de >= n_dex) {
	    struct dirent **ndex;

	    ndex = realloc(dex, (n_dex + DIR_CHUNK) * sizeof *dex);
	    if (!ndex)
		goto nomem;

	    dex = ndex;
	    n_dex += DIR_CHUNK;
	}

	nde = malloc(de->d_reclen);
	if (!nde)
	    goto nomem;

	memcpy(nde, de, de->d_reclen);
	dex[n_de++] = nde;

	maxlen = max(maxlen, de->d_reclen);
    }

    closedir(dir);

    qsort(dex, n_de, sizeof *dex, compare_dirent);

    maxlen -= offsetof(struct dirent, d_name) + 1;
    ncols = (cols + 2)/(maxlen + 8);
    ncols = min(ncols, n_de);
    ncols = max(ncols, 1U);
    colwidth = (cols + 2)/ncols;
    perpage = ncols * (rows - 1);

    for (i = 0; i < n_de; i += perpage) {
	/* Rows on this page */
	endpage = min(i+perpage, n_de);
	nrows = ((endpage-i) + ncols - 1)/ncols;

	for (j = 0; j < nrows; j++) {
	    pos = tpos = 0;
	    for (k = i+j; k < endpage; k += nrows) {
		pos += printf("%*s%-5s %s",
			      (tpos - pos), "",
			      type_str(dex[k]->d_type),
			      dex[k]->d_name);
		tpos += colwidth;
	    }
	    printf("\n");
	}

	if (endpage >= n_de)
	    break;

	get_key(stdin, 0);
    }

    free_dirents(dex, n_de);
    return 0;

nomem:
    closedir(dir);
    printf("Out of memory error!\n");
    free_dirents(dex, n_de);
    return -1;
}

int main(int argc, char *argv[])
{
    int rv;

    if (getscreensize(1, &rows, &cols)) {
	/* Unknown screen size? */
	rows = 24;
	cols = 80;
    }

    if (argc < 2)
	rv = display_directory(".");
    else if (argc == 2)
	rv = display_directory(argv[1]);
    else {
	printf("Usage: dir directory\n");
	rv = 1;
    }

    return rv ? 1 : 0;
}
  

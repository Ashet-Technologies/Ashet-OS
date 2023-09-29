#include <stdio.h>
#include <stdlib.h>
#include <console.h>

int main(int argc, char *argv[])
{
    FILE *f;
    int i;
    int len;
    char buf[4096];

    if (argc < 2) {
	fprintf(stderr, "Usage: %s filename...\n", argv[0]);
	return 1;
    }

    for (i = 1; i < argc; i++) {
	f = fopen(argv[i], "r");
	if (!f) {
	    fprintf(stderr, "%s: %s: file not found\n", argv[0], argv[i]);
	    return 1;
	}

	while ((len = fread(buf, 1, sizeof buf, f)) > 0)
	    fwrite(buf, 1, len, stdout);
	
	fclose(f);
    }

    return 0;
}

#pragma once

#include <stdarg.h>
#include <stddef.h>

typedef struct {
    int dummy;
} FILE;

typedef struct {
    int dummy;
} fpos_t;

#define _IOFBF (<TODO>)      /* see description */
#define _IOLBF (<TODO>)      /* see description */
#define _IONBF (<TODO>)      /* see description */
#define BUFSIZ (<TODO>)      /* see description */
#define EOF (<TODO>)         /* see description */
#define FOPEN_MAX (<TODO>)   /* see description */
#define FILENAME_MAX (<TODO>)/* see description */
#define L_tmpnam (<TODO>)    /* see description */
#define SEEK_CUR (<TODO>)    /* see description */
#define SEEK_END (<TODO>)    /* see description */
#define SEEK_SET (<TODO>)    /* see description */
#define TMP_MAX (<TODO>)     /* see description */

extern FILE _ashetos_stdin;
extern FILE _ashetos_stdout;
extern FILE _ashetos_stderr;

#define stdin (&_ashetos_stdin)
#define stdout (&_ashetos_stdout)
#define stderr (&_ashetos_stderr)

#define _PRINTF_NAN_LEN_MAX /* see description */

int      remove(const char * filename);
int      rename(char const * old, char const * new);
FILE *   tmpfile(void);
char *   tmpnam(char * s);
int      fclose(FILE * stream);
int      fflush(FILE * stream);
FILE *   fopen(char const * restrict filename, char const * restrict mode);
FILE *   freopen(char const * restrict filename, char const * restrict mode,
                 FILE * restrict stream);
void     setbuf(FILE * restrict stream, char * restrict buf);
int      setvbuf(FILE * restrict stream, char * restrict buf, int mode, size_t size);
int      printf(char const * restrict format, ...);
int      scanf(char const * restrict format, ...);
int      snprintf(char * restrict s, size_t n, char const * restrict format, ...);
int      sprintf(char * restrict s, char const * restrict format, ...);
int      sscanf(char const * restrict s, char const * restrict format, ...);
int      vfprintf(FILE * restrict stream, char const * restrict format, va_list arg);
int      vfscanf(FILE * restrict stream, char const * restrict format, va_list arg);
int      vprintf(char const * restrict format, va_list arg);
int      vscanf(char const * restrict format, va_list arg);
int      vsnprintf(char * restrict s, size_t n, char const * restrict format, va_list arg);
int      vsprintf(char * restrict s, char const * restrict format, va_list arg);
int      vsscanf(char const * restrict s, char const * restrict format, va_list arg);
int      fgetc(FILE * stream);
char *   fgets(char * restrict s, int n, FILE * restrict stream);
int      fputc(int c, FILE * stream);
int      fputs(char const * restrict s, FILE * restrict stream);
int      getc(FILE * stream);
int      getchar(void);
int      putc(int c, FILE * stream);
int      putchar(int c);
int      puts(char const * s);
int      ungetc(int c, FILE * stream);
size_t   fread(void * restrict ptr, size_t size, size_t nmemb,
               FILE * restrict stream);
size_t   fwrite(void const * restrict ptr, size_t size, size_t nmemb,
                FILE * restrict stream);
int      fgetpos(FILE * restrict stream, fpos_t * restrict pos);
int      fseek(FILE * stream, long int offset, int whence);
int      fsetpos(FILE * stream, fpos_t const * pos);
long int ftell(FILE * stream);
void     rewind(FILE * stream);
void     clearerr(FILE * stream);
int      feof(FILE * stream);
int      ferror(FILE * stream);
void     perror(char const * s);
int      fprintf(FILE * restrict stream, char const * restrict format, ...);
int      fscanf(FILE * restrict stream, char const * restrict format, ...);

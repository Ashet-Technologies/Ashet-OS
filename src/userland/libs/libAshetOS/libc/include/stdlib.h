#ifndef _FOUNDATION_LIBC_STDLIB_H_
#define _FOUNDATION_LIBC_STDLIB_H_

#include <stddef.h>
#include <stdint.h>

// TODO: void                   call_once(once_flag * flag, void (*func)(void));

double                 atof(char const * nptr);
int                    atoi(char const * nptr);
long int               atol(char const * nptr);
long long int          atoll(char const * nptr);
int                    strfromd(char * restrict s, size_t n, char const * restrict format, double fp);
int                    strfromf(char * restrict s, size_t n, char const * restrict format, float fp);
int                    strfroml(char * restrict s, size_t n, char const * restrict format, long double fp);
double                 strtod(char const * restrict nptr, char ** restrict endptr);
float                  strtof(char const * restrict nptr, char ** restrict endptr);
long double            strtold(char const * restrict nptr, char ** restrict endptr);
long int               strtol(char const * restrict nptr, char ** restrict endptr, int base);
long long int          strtoll(char const * restrict nptr, char ** restrict endptr, int base);
unsigned long int      strtoul(char const * restrict nptr, char ** restrict endptr, int base);
unsigned long long int strtoull(char const * restrict nptr,
                                char ** restrict endptr, int base);
int                    rand(void);
void                   srand(unsigned int seed);
void *                 aligned_alloc(size_t alignment, size_t size);
void *                 calloc(size_t nmemb, size_t size);
void                   free(void * ptr);
void                   free_sized(void * ptr, size_t size);
void                   free_aligned_sized(void * ptr, size_t alignment, size_t size);
void *                 malloc(size_t size);
void *                 realloc(void * ptr, size_t size);
[[noreturn]] void      abort(void);
int                    atexit(void (*func)(void));
int                    at_quick_exit(void (*func)(void));
[[noreturn]] void      exit(int status);
[[noreturn]] void      _Exit(int status);
char *                 getenv(char const * name);
[[noreturn]] void      quick_exit(int status);
int                    system(char const * string);
// void *                 bsearch(void const * key, void const * ptr, size_t count, size_t size,
//                                int (*comp)(void const *, void const *));

// void *                 bsearch_s(void const * key, void const * ptr, rsize_t count, rsize_t size,
//                                  int (*comp)(void const *, void const *, void *),
//                                  void * context);

void          qsort(void * base, size_t nmemb, size_t size,
                    int (*compar)(void const *, void const *));
int           abs(int j);
long int      labs(long int j);
long long int llabs(long long int j);

typedef struct _ashet_div {
    int quot;
    int rem;
} div_t;
div_t div(int numer, int denom);

typedef struct _ashet_ldiv {
    long quot;
    long rem;
} ldiv_t;
ldiv_t ldiv(long int numer, long int denom);

typedef struct _ashet_lldiv {
    long long quot;
    long long rem;
} lldiv_t;
lldiv_t lldiv(long long int numer, long long int denom);

int     mblen(char const * s, size_t n);
int     mbtowc(wchar_t * restrict pwc, char const * restrict s, size_t n);
int     wctomb(char * s, wchar_t wc);
size_t  mbstowcs(wchar_t * restrict pwcs, char const * restrict s, size_t n);
size_t  wcstombs(char * restrict s, wchar_t const * restrict pwcs, size_t n);
size_t  memalignment(void const * p);

#endif

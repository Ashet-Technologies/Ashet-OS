#pragma once

#include <stddef.h>
#include <stdint.h>

#define __inhibit_loop_to_libcall

static inline void *__inhibit_loop_to_libcall
memcpy(void *__restrict dst0, const void *__restrict src0, size_t len0) {
  char *dst = (char *)dst0;
  char *src = (char *)src0;

  void *save = dst0;

  while (len0--) {
    *dst++ = *src++;
  }

  return save;
}

static inline void *__inhibit_loop_to_libcall memset(void *m, int c, size_t n) {
  char *s = (char *)m;
  while (n--)
    *s++ = (char)c;

  return m;
}

static inline int memcmp(const void *m1, const void *m2, size_t n) {
  unsigned char *s1 = (unsigned char *)m1;
  unsigned char *s2 = (unsigned char *)m2;

  while (n--) {
    if (*s1 != *s2) {
      return *s1 - *s2;
    }
    s1++;
    s2++;
  }
  return 0;
}

static inline char *strchr(const char *s1, int i) {
  const unsigned char *s = (const unsigned char *)s1;
  unsigned char c = i;

  while (*s && *s != c)
    s++;
  if (*s == c)
    return (char *)s;
  return NULL;
}
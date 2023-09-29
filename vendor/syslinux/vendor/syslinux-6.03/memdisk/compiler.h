
#ifdef __WATCOMC__
# define MEMDISK_PACKED_PREFIX _Packed
# define MEMDISK_PACKED_POSTFIX
#else
/* Assume GNU C for now */
# define MEMDISK_PACKED_PREFIX
# define MEMDISK_PACKED_POSTFIX __attribute__((packed))
#endif

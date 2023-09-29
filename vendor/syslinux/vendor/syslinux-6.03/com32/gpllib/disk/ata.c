#include <inttypes.h>
#include <string.h>

/**
 *      ata_id_string - Convert IDENTIFY DEVICE page into string
 *      @id: IDENTIFY DEVICE results we will examine
 *      @s: string into which data is output
 *      @ofs: offset into identify device page
 *      @len: length of string to return. must be an even number.
 *
 *      The strings in the IDENTIFY DEVICE page are broken up into
 *      16-bit chunks.  Run through the string, and output each
 *      8-bit chunk linearly, regardless of platform.
 *
 *      LOCKING:
 *      caller.
 */
void ata_id_string(const uint16_t * id, unsigned char *s,
		   unsigned int ofs, unsigned int len)
{
    unsigned int c;

    while (len > 0) {
	c = id[ofs] >> 8;
	*s = c;
	s++;

	c = id[ofs] & 0xff;
	*s = c;
	s++;

	ofs++;
	len -= 2;
    }
}

/**
 *      ata_id_c_string - Convert IDENTIFY DEVICE page into C string
 *      @id: IDENTIFY DEVICE results we will examine
 *      @s: string into which data is output
 *      @ofs: offset into identify device page
 *      @len: length of string to return. must be an odd number.
 *
 *      This function is identical to ata_id_string except that it
 *      trims trailing spaces and terminates the resulting string with
 *      null.  @len must be actual maximum length (even number) + 1.
 *
 *      LOCKING:
 *      caller.
 */
void ata_id_c_string(const uint16_t * id, unsigned char *s,
		     unsigned int ofs, unsigned int len)
{
    unsigned char *p;

    ata_id_string(id, s, ofs, len - 1);

    p = s + strnlen((const char *)s, len - 1);
    while (p > s && p[-1] == ' ')
	p--;
    *p = '\0';
}

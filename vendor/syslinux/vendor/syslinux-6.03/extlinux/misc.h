/*
 * Copyright (c) 2012 Paulo Alcantara <pcacjr@zytor.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it would be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write the Free Software Foundation,
 * Inc.,  51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#ifndef MISC_H_
#define MISC_H_

/* Return a 64-bit litte-endian value from a given 64-bit big-endian one */
static inline uint64_t be64_to_cpu(uint64_t val)
{
    return (uint64_t)((((uint64_t)val & (uint64_t)0x00000000000000ffULL) << 56) |
		      (((uint64_t)val & (uint64_t)0x000000000000ff00ULL) << 40) |
		      (((uint64_t)val & (uint64_t)0x0000000000ff0000ULL) << 24) |
		      (((uint64_t)val & (uint64_t)0x00000000ff000000ULL) <<  8) |
		      (((uint64_t)val & (uint64_t)0x000000ff00000000ULL) >>  8) |
		      (((uint64_t)val & (uint64_t)0x0000ff0000000000ULL) >> 24) |
		      (((uint64_t)val & (uint64_t)0x00ff000000000000ULL) >> 40) |
		      (((uint64_t)val & (uint64_t)0xff00000000000000ULL) >> 56));
}

/* Return a 32-bit litte-endian value from a given 32-bit big-endian one */
static inline uint32_t be32_to_cpu(uint32_t val)
{
    return (uint32_t)((((uint32_t)val & (uint32_t)0x000000ffUL) << 24) |
		      (((uint32_t)val & (uint32_t)0x0000ff00UL) <<  8) |
		      (((uint32_t)val & (uint32_t)0x00ff0000UL) >>  8) |
		      (((uint32_t)val & (uint32_t)0xff000000UL) >> 24));
}

/* Return a 16-bit litte-endian value from a given 16-bit big-endian one */
static inline uint16_t be16_to_cpu(uint16_t val)
{
    return (uint16_t)((((uint16_t)val & (uint16_t)0x00ffU) << 8) |
		      (((uint16_t)val & (uint16_t)0xff00U) >> 8));
}

#endif /* MISC_H_ */

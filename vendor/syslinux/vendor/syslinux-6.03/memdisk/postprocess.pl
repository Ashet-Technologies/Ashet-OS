#!/usr/bin/perl
## -----------------------------------------------------------------------
##
##   Copyright 2001-2008 H. Peter Anvin - All Rights Reserved
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

#
# Postprocess the memdisk binary.  Used during the 'make' process.
# We write memdisk16.bin out to the final memdisk kernel, pad it to an
# integral 512-byte sector length, write this number of sectors into the
# kernel header field "setup_sects", then append memdisk32.bin

eval { use bytes; };

($out,$file16,$file32) = @ARGV;

open(OUT, "> $out\0") or die "$0: Cannot create file: $out\n";
eval { binmode OUT; };
open(FILE, "< $file16\0") or die "$0: Cannot open file: $file16\n";
eval { binmode FILE };

@info = stat(FILE);
$size = $info[7];

$sectors = ($size + 511) >> 9;
$xsize = $sectors << 9;

read(FILE, $f16, $size);

print OUT $f16;

if ( $size != $xsize ) {
    # Pad to a sector boundary
    print OUT "\0" x ($xsize-$size);
}

seek(OUT, 0x1f1, SEEK_SET);	# setup_sects
# All sectors are setup except the first
print OUT pack("C", $sectors-1);

seek(OUT, $xsize, SEEK_SET);
close(FILE);

open(FILE, "+< $file32\0") or die "$0: Cannot open file: $file32\n";

while ( ($n = read(FILE, $f32, 65536)) > 0 ) {
    print OUT $f32;
}

close(FILE);
close(OUT);

#!/usr/bin/perl
## -----------------------------------------------------------------------
##
##   Copyright (C) 2010 P J P <pj.pandit@yahoo.co.in>
##
##   Permission is hereby granted, free of charge, to any person
##   obtaining a copy of this software and associated documentation
##   files (the "Software"), to deal in the Software without
##   restriction, including without limitation the rights to use,
##   copy, modify, merge, publish, distribute, sublicense, and/or
##   sell copies of the Software, and to permit persons to whom
##   the Software is furnished to do so, subject to the following
##   conditions:
##
##   The above copyright notice and this permission notice shall
##   be included in all copies or substantial portions of the Software.
##
##   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
##   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
##   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
##   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
##   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
##   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
##   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
##   OTHER DEALINGS IN THE SOFTWARE.
##
## -----------------------------------------------------------------------

use strict;
use warnings;

binmode STDIN;

print "#include <inttypes.h>\n";
print "#include \"isohybrid.h\"\n";
print "\n";
print "uint8_t isohdpfx[][MBRSIZE] =\n";
print "{\n";

foreach my $file (@ARGV) {
    my $len = 0;
    my $ch;

    open(IN, '<', $file) or die "$0: $file: $!\n";
    printf("    {\n");
    while (read(IN, $ch, 1))
    {
	printf("\t/* 0x%03x */ ", $len) if (!($len % 8));
	printf("0x%02x,", ord($ch));
	$len++;
    
	print("\n") if (!($len % 8));
    }
    print "    },\n";
    close(IN);
}
print "};\n";

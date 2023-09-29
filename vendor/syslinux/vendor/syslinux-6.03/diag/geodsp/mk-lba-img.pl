## -----------------------------------------------------------------------
##
##   Copyright 2011 Gene Cumm
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

##
## mk-lba-img.pl
##
## Make an image where each sector contains the LBA of the sector with
## a head of an input file.
##

# use bytes;

use constant SECTOR_SIZE => 512;
use constant LBA_SIZE => 8;
use constant LONG_SIZE => 4;
use constant NUM_SECTORS => (256*63+1);
# use constant NUM_SECTORS => 5;
use constant DEBUG => 1;

# sub dprint
# {
#     if (DEBUG) {
# 	print($_);
#     }
# }

($ifilen, $ofilen) = @ARGV;

if ((!defined($ifilen)) || ($ifilen eq "-")) {	# 
    print(STDERR "Using stdin\n");
    $IFILE = STDIN;
} else {
    open($IFILE, '<', $ifilen) or die "open:$!";
    print(STDERR "Using $ifilen\n");
}

binmode($ifile);

if (!defined($ofilen)) {
    $OFILE = STDOUT;
} else {
    open($OFILE, '>', $ofilen) or die "open:$!";
    print(STDERR "Using $ofilen\n");
}

binmode($OFILE);

# $pk0 = pack('L', 0);
$n_long = (SECTOR_SIZE/LONG_SIZE);
$n_lba = (SECTOR_SIZE/LBA_SIZE);

$len=0;
while ( read($IFILE, $ch, 1) ) {
    print($OFILE $ch);
    $len++;
}
$tail = (SECTOR_SIZE - ($len % SECTOR_SIZE)) % SECTOR_SIZE;
$ch = pack("C", 0);
print("Len: $len\ttail: $tail\n");
for ($i=0; $i<$tail; $i++) {
    print($OFILE $ch);
}

$st = ($len + $tail) / SECTOR_SIZE;

for ($i=$st; $i<(NUM_SECTORS); $i++) {
    @ia = ();
    for ($j=0; $j< $n_lba; $j++) {
	push(@ia, $i, 0);
    }
    @ipk = pack("L[$n_long]", @ia);
	# There is a 64-bit INT conversion but it normally isn't usable
	# on a 32-bit platform
    print($OFILE @ipk);	# Gently simulate a 64-bit LBA
}

if (defined($ifilen) && (!($ifilen eq "-"))) {
    close($IFILE);
}

if (defined($ofilen)) {
    close($OFILE);
}

exit 0;

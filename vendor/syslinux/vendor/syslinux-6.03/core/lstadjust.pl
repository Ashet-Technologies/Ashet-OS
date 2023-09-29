#!/usr/bin/perl
#
# Take a NASM list and map file and make the offsets in the list file
# absolute.  This makes debugging a lot easier.
#
# Usage:
#
#  lstadjust.pl listfile mapfile outfile
#

($listfile, $mapfile, $outfile) = @ARGV;

open(LST, "< $listfile\0")
    or die "$0: cannot open: $listfile: $!\n";
open(MAP, "< $mapfile\0")
    or die "$0: cannot open: $mapfile: $!\n";
open(OUT, "> $outfile\0")
    or die "$0: cannot create: $outfile: $!\n";

%vstart = ();

while (defined($line = <MAP>)) {
    if ($line =~ /^\s*([0-9]+)\s+(\S+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+2\*\*([0-9]+)/i) {
	$vstart{$2} = hex $4;
    }
}
close(MAP);

$offset = 0;
@ostack = ();

while (defined($line = <LST>)) {
    chomp $line;

    $source = substr($line, 40);
    if ($source =~ /^([^;]*);/) {
	$source = $1;
    }

    ($label, $op, $arg, $tail) = split(/\s+/, $source);
    if ($op =~ /^(|\[)section$/i) {
	$offset = $vstart{$arg};
    } elsif ($op =~ /^(absolute|\[absolute)$/i) {
	$offset = 0;
    } elsif ($op =~ /^struc$/i) {
	push(@ostack, $offset);
	$offset = 0;
    } elsif ($op =~ /^endstruc$/i) {
	$offset = pop(@ostack);
    }

    if ($line =~ /^(\s*[0-9]+ )([0-9A-F]{8})(\s.*)$/) {
	$line = sprintf("%s%08X%s", $1, (hex $2)+$offset, $3);
    }

    print OUT $line, "\n";
}

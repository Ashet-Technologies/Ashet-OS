#!/usr/bin/perl
#
# Generate a subset of the UnicodeData.txt file, available from
# ftp://ftp.unicode.org/Public/UNIDATA/UnicodeData.txt
#
# Usage:
#   gensubset.pl [subset files] < UnicodeData.txt > MiniUCD.txt
#

%need_these = ();

# Mark as needed all the characters mentioned in the relevant files
foreach $file (@ARGV) {
    open(F, '<', $file) or die;
    while (defined($line = <F>)) {
	$line =~ s/\s*(\#.*|)$//; # Remove comments and final blanks
	@f = split(/\s+/, $line);
	next if (scalar @f != 2);
	$need_these{hex $f[1]}++;
    }
    close(F);
}

# Also mark as needed any case variants of those
# (Note: this doesn't necessarily provide the full transitive closure,
# but we shouldn't need it.)
while (defined($line = <STDIN>)) {
    @f = split(/;/, $line);
    if ($f[0] =~ /^([0-9a-f]+)$/i) {
	$r = hex $f[0];
	if ($need_these{$r}) {
	    $need_these{hex $f[12]}++ if ($f[12] ne '');
	    $need_these{hex $f[13]}++ if ($f[13] ne '');
	    $need_these{hex $f[14]}++ if ($f[14] ne '');
	}
    }
}

# Finally, write out the subset
seek(STDIN, 0, 0);
while (defined($line = <STDIN>)) {
    ($v, $l) = split(/;/, $line, 2);
    if ($v =~ /^([0-9a-f]+)\-([0-9a-f]+)$/i) {
	# This isn't actually the format... fix that if it ever matters
	$r1 = hex $1;
	$r2 = hex $2;
    } elsif ($v =~ /^([0-9a-f]+)$/i) {
	$r1 = $r2 = hex $1;
    } else {
	next;
    }
    for ($r = $r1; $r <= $r2; $r++) {
	printf "%04X;%s", $r, $l if ($need_these{$r});
    }
}

	

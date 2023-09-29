#!/usr/bin/perl
#
# Generate hash values for keywords
#

eval { use bytes; };

while ( defined($keywd = <STDIN>) ) {
    chomp $keywd;

    ($keywd,$keywdname) = split(/\s+/, $keywd);
    $keywdname = $keywd unless ( $keywdname );

    $l = length($keywd);
    $h = 0;
    for ( $i = 0 ; $i < $l ; $i++ ) {
	$c = ord(substr($keywd,$i,1)) | 0x20;
	$h = ((($h << 5)|($h >> 27)) ^ $c) & 0xFFFFFFFF;
    }
    if ( $seenhash{$h} ) {
	printf STDERR "$0: hash collision (0x%08x) %s %s\n",
	$h, $keywd, $seenhash{$h};
    }
    $seenhash{$h} = $keywd;
    printf("%-23s equ 0x%08x\n", "hash_${keywdname}", $h);
}

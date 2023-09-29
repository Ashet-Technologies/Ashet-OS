#!/usr/bin/perl
#
# Try automatic generation of geometries
#

($k) = @ARGV;
$sec = int($k*2+0.5);

if ($sec < 320*2) {
    $c = 40;
    $h = 1;
    $type = 1;
} elsif ($sec < 640*2) {
    $c = 40;
    $h = 2;
    $type = 1;
} elsif ($sec < 1200*2) {
    $c = 80;
    $h = 2;
    $type = 3;
} elsif ($sec < 1440*2) {
    $c = 80;
    $h = 2;
    $type = 2;
} elsif ($sec < 2880*2) {
    $c = 80;
    $h = 2;
    $type = 4;
} elsif ($sec < 4096*2) {
    $c = 80;
    $h = 2;
    $type = 6;
} else {
    printf "%.1fK, %d sectors: ", $sec/2, $sec;
    print "Considered a hard disk\n";
    exit 2;
}

$ok = 0;
while ($c < 256) {
    $s = int($sec/($c*$h)+0.5);
    if ($s <= 63 && $sec == $c*$h*$s) {
	$ok = 1;
	last;
    }
    $c++;
}

printf "%.1fK, %d sectors: ", $sec/2, $sec;
if ($ok) {
    print "c=$c, h=$h, s=$s, type=$type\n";
    exit 0;
} else {
    print "No valid geometry found (MEMDISK will fake it)\n";
    exit 1;
}

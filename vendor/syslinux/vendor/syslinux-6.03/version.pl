#!/usr/bin/perl
#
# Read the "version" file and produce some macro declarations
#

use Fcntl;

sub defx($$$) {
    my($def, $name, $val) = @_;

    $def =~ s/\</${name}/g;
    $def =~ s/\@/${val}/g;

    return $def."\n";
}

($vfile, $vout, $def) = @ARGV;
sysopen(VERSION, $vfile, O_RDONLY) or die "$0: Cannot open $vfile\n";
$vfile = <VERSION>;
chomp $vfile;
close(VERSION);

unless ( $vfile =~ /^(([0-9]+)\.([0-9]+))\s+([0-9]+)$/ ) {
    die "$0: Cannot parse version format\n";
}
$version = $1;
$vma = $2+0;
$vmi = $3+0;
$year = $4;

sysopen(VI, $vout, O_WRONLY|O_CREAT|O_TRUNC)
    or die "$0: Cannot create $vout: $!\n";
print VI defx($def, 'VERSION',       $version);
print VI defx($def, 'VERSION_STR',   '"'.$version.'"');
print VI defx($def, 'VERSION_MAJOR', $vma);
print VI defx($def, 'VERSION_MINOR', $vmi);
print VI defx($def, 'YEAR',          $year);
print VI defx($def, 'YEAR_STR',      '"'.$year.'"');
close(VI);

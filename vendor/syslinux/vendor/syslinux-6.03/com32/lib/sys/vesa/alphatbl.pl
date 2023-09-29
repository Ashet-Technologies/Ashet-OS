#!/usr/bin/perl
#
# Produce gamma-correction tables for alpha blending, assuming sRGB space.
#

sub srgb_to_linear($)
{
    my($s) = @_;

    if ($s <= 10) {
	return $s/(255*12.92);
    } else {
	return (($s+14.025)/269.025)**2.4;
    }
}

sub linear_to_srgb($)
{
    my($l) = @_;
    my $s;

    if ($l <= 0.00304) {
	$s = 12.92*$l;
    } else {
	$s = 1.055*$l**(1.0/2.4) - 0.055;
    }

    return int($s*255+0.5);
}

# Header
print "#include <inttypes.h>\n\n";

#
# Table 1: convert 8-bit sRGB values to 16-bit linear values
#

print "const uint16_t __vesacon_srgb_to_linear[256] = {\n";
for ($i = 0; $i <= 255; $i++) {
    printf "\t%5d,\n", int(srgb_to_linear($i)*65535+0.5);
}
print "};\n\n";

#
# Table 2: convert linear values in the range [0, 65535*255],
#          shifted right by 12 bits, to sRGB
#

print "const uint8_t __vesacon_linear_to_srgb[4080] = {\n";
for ($i = 0; $i <= 4079; $i++) {
    printf "\t%3d,\n", linear_to_srgb(($i+0.5)/4079.937744);
}
print "};\n\n";

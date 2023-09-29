#!/usr/bin/perl
#
# Perl script to convert a Syslinux-format screen to PC-ANSI
# to display in a color xterm or on the Linux console
#

@ansicol = (0,4,2,6,1,5,3,7);

$getting_file = 0;
$enable = 1;

while ( read(STDIN, $ch, 1) > 0 ) {
    if ( $ch eq "\x1A" ) {	# <SUB> <Ctrl-Z> EOF
	last;
    } elsif ( $ch eq "\x0C" ) {	# <FF>  <Ctrl-L> Clear screen
	print "\x1b[2J" if ( $enable && !$getting_file );
    } elsif ( $ch eq "\x0F" ) {	# <SI>  <Ctrl-O> Attribute change
	if ( !$getting_file ) {
	    if ( read(STDIN, $attr, 2) == 2 ) {
		$attr = hex $attr;
		if ( $enable ) {
		    print "\x1b[0;";
		    if ( $attr & 0x80 ) {
			print "5;";
			$attr &= ~0x80;
		    }
		    if ( $attr & 0x08 ) {
			print "1;";
			$attr &= ~0x08;
		    }
		    printf "%d;%dm",
		    $ansicol[$attr >> 4] + 40, $ansicol[$attr & 7] + 30;
		}
	    }
	}
    } elsif ( $ch eq "\x18" ) {	# <CAN> <Ctrl-X> Display image
	# We can't display an image; pretend to be a text screen
	# Ignore all input until end of line
	$getting_file = 1;
    } elsif ( (ord($ch) & ~07) == 0x10 ) { # Mode controls
	$enable = (ord($ch) & 0x01); # Emulate the text screen
    } elsif ( $ch eq "\x0D" ) {	# <CR>  <Ctrl-M> Carriage return
	# Ignore
    } elsif ( $ch eq "\x0A" ) { # <LF>  <Ctrl-J> Line feed
	if ( $getting_file ) {
	    $getting_file = 0;
	} else {
	    print $ch if ( $enable );
	}
    } else {
	print $ch if ( $enable && !$getting_file );
    }
}

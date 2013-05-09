package ANSI::Unicode;

use Moose;

use Encode qw (from_to encode _utf8_on _utf8_off);
use Data::Dumper;

has 'cols' => (
    is => 'rw',
    isa => 'Int',
    default => 80,
);

has 'no_color' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has 'format' => (
    is => 'rw',
    isa => 'Str',
    default => 'irc',
);

has 'input_filename' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

my $esc = "\x1b";

*color2mirc_bg = \&color2mirc_fg;

my %ans2mircmap = (
    30 => 1,                    # black
    31 => 4,                    # red
    32 => 9,                    # green
    33 => 8,                    # yellow
    34 => 2,                    # blue
    35 => 13,                   # pink (should be purple?)
    36 => 11,                   # cyan
    37 => 0,                    # white
    39 => 0,                    # white
);

# generate background colors
foreach my $k (keys %ans2mircmap) {
    $ans2mircmap{$k + 10} = $ans2mircmap{$k};
}
$ans2mircmap{49} = 1; # default is black not white for background color

my %mirc2colormap = (
    0  => 'white',
    1  => 'black',
    2  => 'blue',
    3  => 'green',
    4  => 'red',
    5  => 'brown',
    6  => 'purple',
    7  => 'orange',
    8  => '#8F8F00',                  # dark yellow
    9  => '#33FF33',                  # ltgreen
    10 => 'teal',
    11 => 'cyan',
    12 => '#3333FF',                  # ltblue,
    13 => '#FFA0AB',                  # pink
    14 => 'grey',
    15 => 'ltgrey',

    # extra mappings for high intensity colors to mirc
    6  => 'yellow',             # dark yellow -> orange
);

# normal -> high intensity colors (for ANSI 'bold')
my %color2hi = (
    '#8F8F00' => 'yellow',
);

my %color2mircmap;
@color2mircmap{values %mirc2colormap} = keys %mirc2colormap;

sub convert {
    my $mirc_last_fg = '';
    my @map = ();
    my @colormap = ();
    my $row = 0;
    my $col = 0;
    my $linewrap;

    while (my $ln = <$infh>) {
        next unless $ln;

        # filter out stuff we don't care about
        $linewrap ||= $ln =~ s/$esc\[.?7h//g; # enable linewrap

        # go through each character
        my $idx = 0;
        while ($ln) {
            last if $idx >= length $ln;

            my $c = substr($ln, $idx, 1);
            $idx++;

            if ($c eq $esc) {
                # escape sequence, oh noes!
                my $seq = substr($ln, $idx);
                if ($seq =~ s/^\[(\d+)?C//) {
                    # move forward
                    $col += $1 || 1;
                } elsif ($seq =~ s/^\[(\d+)?D//) {
                    # move back
                    if ($1 && $1 > 254) {
                        $col = 0;
                    } else {
                        $col -= $1 || 1;
                    }
                } elsif ($seq =~ s/^\[(\d+)?A//) {
                    # move up
                    $row -= $1 || 1;
                } elsif ($seq =~ s/^\[(\d+)?B//) {
                    # move down
                    $row += $1 || 1;
                } elsif ($seq =~ s/^\[(\d+)m//) {
                    if ($1 == 0) {
                        # reset
                        $colormap[$row][$col] = {fgcolor => 'white', bgcolor => 'black'};
                    } elsif ($1 < 30) {
                        # ignore font/color attribute for now
                    } elsif ($1 >= 30 && $1 < 40) {
                        $colormap[$row][$col] = {fgcolor => ans2color($1)};
                    } elsif ($1 >= 40 && $1 < 50) {
                        $colormap[$row][$col] = {bgcolor => ans2color($1)};
                    } else {
                        print STDERR "Unknown ANSI color code: $1\n";
                    }
                } elsif ($seq =~ s/^\[(\d*);(\d*);?(\d*)m//) {
                    my $color_info = {};
                    my @attrs = ($1, $2, $3);
                    my $force;
                    while (@attrs) {
                        my $attr = shift @attrs;
                        next if ! defined $attr || $attr eq '';

                        if ($attr == 0) {
                            # reset
                            $color_info = {fgcolor => 'white', bgcolor => 'black'};
                        } elsif ($attr < 30) {
                            if ($attr == 1) {
                                # bold, but seems to mean set the fg color to ltgrey if fg and bg are white
                                #unless (grep { ans2color($_) ne 'black'
                                #               && ans2color($_) ne 'white' } @attrs) {
                                    #$color_info->{fgcolor} = 'ltgrey';
                                    #$color_info->{bgcolor} = 'white';
                                    #$force = 1;
                                #}
                                #$color_info->{bgcolor} = 'black';
                                $color_info->{bold} = 1;
                            } else {
                                #print STDERR "Unhandled attribute $attr\n";
                            }
                            # other color/text attribute. ignore for now.
                        } elsif ($attr < 40) {
                            # fg
                            $color_info->{fgcolor} = ans2color($attr) unless $force;
                        } elsif ($attr < 50) {
                            #bg
                            $color_info->{bgcolor} = ans2color($attr) unless $force;
                        } elsif (! $force) {
                            print STDERR "Unrecognized ANSI color code: $attr\n";
                        }
                    }

                    # don't allow white on white text
                    if ($color_info->{fgcolor} && $color_info->{bgcolor}) {
                        $color_info->{fgcolor} = 'ltgrey'
                            if $color_info->{fgcolor} eq $color_info->{bgcolor};
                    }

                    $colormap[$row][$col] = $color_info;
                } elsif ($seq =~ /\[2J/) {
                    # erase display and reset cursor... okay
                    $seq = '';
                } else {
                    print STDERR "Unrecognized ANSI escape sequence, chunk='" .
                        substr($seq, 0, 7) . "'\n";
                }

                # change the rest of $ln past $idx to $seq
                substr($ln, $idx) = $seq;
            } elsif ($c eq "\n") {
                $row++;
            } elsif ($c eq "\r") {
                $col = 0;
            } else {
                # otherwise it's a normal char
                cp437_to_unicode(\$c) if ord($c) > 127;
                $map[$row][$col] = $c;
                $col++;
            }

            if ($col >= $self->cols) {
                # linewrap
                $col = $col % $self->cols;
                $row++;
            }
        }
    }

    close $infh;

    ############ OUTPUT ##############
    my $outfilename = shift @ARGV;
    my $output_fh;
    if ($outfilename) {
        open($output_fh, ">$outfilename") or die "Could not write to file $outfilename: $!\n";
    } else {
        open($output_fh, ">&=", STDOUT);
    }

    my $format = $self->format;
    if ($format eq 'html') {
        html_output();
    } elsif ($format eq 'irc') {
        # default
        irc_output();
    } else {
        die "Unknown format $format";
    }

    close $output_fh;
}

sub html_output {
    print $output_fh qq {<table style="font-family: monospace; font-size: 11px;" cellspacing="0" cellpadding="0">} . "\n";

    my $rows = $row;
    my $last_style = '';
    my ($fgcolor, $bgcolor);
    my $color_info = {fgcolor => 'white', bgcolor => 'black'};

    for ($row = 0; $row <= $rows; $row++) {
        print $output_fh '<tr bgcolor="black">';

        for ($col = 0; $col < $self->cols; $col++) {
            my $c = $map[$row][$col];

            if ($colormap[$row][$col]) {
                foreach my $attr (qw/ fgcolor bgcolor bold /) {
                    next unless my $newattr = $colormap[$row][$col]->{$attr};
                    $color_info->{$attr} = $newattr;
                }
            }

            $fgcolor = $color_info->{fgcolor} if $color_info->{fgcolor};
            $bgcolor = $color_info->{bgcolor} if $color_info->{bgcolor};

            if ($color_info->{bold}) {
                # bold really doesn't mean bold, it means use the high-intensity version of the color
                $fgcolor = color_hi($fgcolor);
            }

            my $char_uni_html = '';

            my ($td_fgcolor, $td_bgcolor);

            # look up $c's unicode value
            if (! defined $c) {
                # no char, make this a blank cell
                $bgcolor = '#000';
                $char_uni_html = '&nbsp;';
            } elsif ($c eq ' ') {
                # turn space into nbsp
                $char_uni_html = '&nbsp;';
            } else {
                # convert char to unicode
                cp437_to_unicode(\$c);
                _utf8_on($c);
                $char_uni_html = '&#' . ord($c) . ';';
            }

            $td_fgcolor ||= qq{ style="color: $fgcolor"};
            $td_bgcolor ||= qq{ bgcolor="$bgcolor"};

            $td_bgcolor = '' if $bgcolor eq '#000' || $bgcolor eq 'black';

            print $output_fh "<td$td_bgcolor$td_fgcolor>$char_uni_html</td>";
        }

        print $output_fh "</tr>\n";
    }

    print $output_fh "</table>\n";
}

sub irc_output {
    my $rows = $row;
    my $lastcolor;
    my $ret;

    $ret .= colorinfo2mirc({fgcolor => "white", bgcolor => "black"});
    my $color_info;

    for ($row = 0; $row <= $rows; $row++) {
        my $mirc_color;
        my $last_color;

        for ($col = 0; $col < $self->cols; $col++) {
            if ($colormap[$row][$col]) {
                foreach my $attr (qw/ fgcolor bgcolor bold /) {
                    my $newattr = $colormap[$row][$col]->{$attr};
                    next unless defined $newattr;
                    $color_info->{$attr} = $newattr;
                }
            }

            my $c = $map[$row][$col];

            if (defined $c) {
                $mirc_color = colorinfo2mirc($color_info) || '';

                # print out new color code if we have a new color
                $ret .= "$mirc_color"
                    if ($mirc_color && ! $last_color) || ($last_color && $mirc_color && $mirc_color ne $last_color);

                $last_color = $mirc_color;

                # output char
                $ret .= $c;
            } else {
                $ret .= " ";
            }
        }

        $ret .= "\n";

        # new line, keep last color
        $ret .= $mirc_color if $mirc_color;
    }

    # dont output utf8 to irssi/whatever, it won't be happy
    _utf8_off($ret);

    my @lines = split("\n", $ret);
    foreach my $line (@lines) {
        print $output_fh "$line\n";
        select undef, undef, undef, 0.05;
    }
}

# takes strref
sub cp437_to_unicode {
    my $strref = shift;
    from_to($$strref, "IBM437", "utf8");
    #_utf8_on($$strref);
    my $mapped = Encode::encode_utf8($$strref);
    $strref = \$mapped;

    # fix perl's gay mapping
    $$strref =~ s/\x{004}/\x{2666}/g;
}

# returns the high-intensity version of this color, if available
sub color_hi {
    my $color = shift;
    return $color2hi{$color} || $color;
}

sub color2mirc_fg {
    my $color = shift;
    return $color2mircmap{$color};
}

sub colorinfo2mirc {
    my $color = shift;

    my $fgcolor = $color->{fgcolor};
    my $bgcolor = $color->{bgcolor};

    #    return '' if $termout;
    return '' unless $fgcolor || $bgcolor;

    my $fg = $fgcolor ? color2mirc_fg($fgcolor) : '';
    my $bg = $bgcolor ? color2mirc_bg($bgcolor) : '';

    $fg = color2mirc_fg(color_hi($fgcolor)) if $fgcolor && $color->{bold};

    # return "\033[$fgcolor;$bgcolor;m" if $self->termout;

    if ($bg) {
        $fg ||= 0;
        return "\003$fg,$bg";
    }

    return "\003$fg";
}

sub ans2color {
    my $ans = shift;
    return '' unless $ans;
    my $mirc_color = $ans2mircmap{$ans};
    return '' unless defined $mirc_color;
    return $mirc2colormap{$mirc_color};
}

__PACKAGE__->meta->make_immutable;

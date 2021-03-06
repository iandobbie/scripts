#!/usr/bin/env perl
use utf8;

## Copyright (C) 2018 David Miguel Susano Pinto <david.pinto@bioch.ox.ac.uk>
##
## Copying and distribution of this file, with or without modification,
## are permitted in any medium without royalty provided the copyright
## notice and this notice are preserved.  This file is offered as-is,
## without any warranty.

## A script to convert SoftWoRx's dvlenses.tab file into the case
## statement for bioformats DeltavisionReader.java
##
## Usage:
##     perl dvlenses2readercases.pl < dvlenses.tab > file-to-insert

use strict;
use warnings;
use 5.010;

my $pipe = \*STDIN;

my %immersions = (
    'air' => 'Air',
    'glycerine' => 'Glycerol',
    'multi' => 'Multi',
    'oil' => 'Oil',
    'oil/gly/water' => 'Multi',
    ## silicon objectives is not part of the ome model.  See
    ## https://github.com/ome/ome-model/issues/82
    'sil' => 'Other',
    'water' => 'Water',
    );

## This is messy.  Regular expressions to guess correction types from
## the objective names.
my %corrections = (
    '[DU] ?Apo' => 'Apo',

    ## Two negative lookbehind because there's no support for variable
    ## length negative lookbehind.
    '(?<!Plan - )(?<!Plan )Apochromat' => 'Apo',
    'Plan( - | )?Apo(chromat)?' => 'PlanApo',

    'Achromat' => 'Achromat',
    'U?Plan ?Fl(uor)?' => 'PlanFluor',

    'Super Fluor' => 'SuperFluor',
    'Neofluor' => 'Neofluor',
    'Plan - NEOFLUAR' => 'PlanNeofluar',
    'Fluar' => 'Fluar',

    ## UV is a problem because while we can match for UV, most of them
    ## also have other type of corrections.
#    'UV' => 'UV',
     );


sub print_lenses {
    my $lenses = shift;
    die "no id for %{$lenses}" unless defined $lenses->{id};
    die "no name for %{$lenses}" unless defined $lenses->{name};
    my $id = $lenses->{id};
    my $name = $lenses->{name};

    ## Print the name as comment because of the way we "guess" the
    ## correction.  It should help anyone reading the actual generated
    ## source code.
    say "      case $id: // $name";
    say "        lensNA = $lenses->{na};";

    if (defined $lenses->{magn}) {
        say "        magnification = $lenses->{magn};";
    } else {
        warn "no magnification for objective id $id '$name'";
    }

    my $wd = $lenses->{wd};
    if (defined $wd && $wd != 0.0) {
        $wd = "$wd." unless $wd =~ /\./; # needs to be a Double
        say "        workingDistance = $wd;";
    }

    my $val = $immersions{$lenses->{type}};
    die "no imersion for $lenses->{type}" unless $val;
    say "        immersion = MetadataTools.getImmersion(\"$val\");";

    if (defined $lenses->{pn} && $lenses->{pn} ne '?') {
        say "        model = \"$lenses->{pn}\";";
    }

    ## TODO: we should probably be using vendor specific regexp to
    ## guess the correct type of correction.
    my $correction;
    ## This may not return stable results.  If there's multiple
    ## matches we don't know which of the corrections types it will
    ## pick.
    foreach my $match (keys %corrections) {
        if ($name =~ m/\b$match\b/i) {
            $correction = $corrections{$match};
            last;
        }
    }
    ## If an objective has UV correction that trumps.  We think that
    ## all UV corrected objectives are also PlanApochromatic at least
    ## but they would still have that written on the name.
    $correction = "UV" if $name =~ m/\bUV\b/;

    if (defined $correction) {
        say "        correction = MetadataTools.getCorrection(\"$correction\");";
    } else {
        warn "no correction found for '$name'";
    }

    if ($id < 10000) {
        $name =~ m/\b(Olympus|Nikon|Leitz|Zeiss)\b/;
        my $manufacturer = $1;
        if ($manufacturer) {
            say "        manufacturer = \"$manufacturer\";";
        } else {
            ## There are a few real cases without manufacturer specified.
            warn "no manufacturer from '$name'";
        }
    }
    say '        break;';
    return;
}

my %lenses;
my $inblock = 0;
while (my $line = <$pipe>) {
    next if $line =~ m/^\#/;
    chomp $line;

    if (! $line) {
        print_lenses(\%lenses) if %lenses and $lenses{id} != 0;
        undef %lenses;
        next;
    }

    ## There's also 'api#' field so a # is only start of comment if
    ## it's on the value side.
    $line =~ m/^(.*)=(.*)$/;
    my $field = $1;
    my $value = $2;

    $value =~ s/\#.*$//;
    ## Remove trailing whitespace.  See https://github.com/openmicroscopy/bioformats/pull/3204/files/3b8c2849fabaeeacf025eb45e670ec7bfd0e3e55#r212598980
    $value =~ s/\s+$//;
    $lenses{$field} = $value;
}

#!/pro/bin/perl

use strict;
use warnings;

use Text::CSV_XS;
use Text::CSV_PP;
use Time::HiRes qw( gettimeofday tv_interval );

my ($csv, $fh, $n, @row);

my %test = (
    splt => sub {
		while (<$fh>) {
		    @row = split m/,/ => $_, -1;
		    $n++;
		    $row[2] eq "Text::CSV_XS" or die "Parse error";
		    }
		},
    perl => sub {
		while (<$fh>) {
		    $csv->parse ($_) or die $csv->error_diag;
		    $n++;
		    @row = $csv->fields;
		    $row[2] eq "Text::CSV_XS" or die "Parse error";
		    }
		},
    gtln => sub {
		while (my $row = $csv->getline ($fh)) {
		    $n++;
		    $row->[2] eq "Text::CSV_XS" or die "Parse error";
		    }
		},
    bndc => sub {
		$csv->bind_columns (\(@row));
		while ($csv->getline ($fh)) {
		    $n++;
		    $row[2] eq "Text::CSV_XS" or die "Parse error";
		    }
		},
    );

my %res;
print <<EOH;
perl-$]
Text::CSV_XS-$Text::CSV_XS::VERSION
Text::CSV_PP-$Text::CSV_PP::VERSION

test       lines     cols  file size file
-------  ---------   ---- ---------- --------
EOH
foreach my $nc (4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048) {
    #foreach my $nr (4, 16, 1024, 10240, 102400) {
    foreach my $nr (1024) {
	$nr * $nc > 48_000_000 and next;
	my $fnm = "test.csv";	END { unlink $fnm }
	system "gencsv.pl", "-n", "-o", $fnm, $nc, $nr + 1;
	my $fsz = -s $fnm or next;	# Failed to create test file
	printf "-------  %9d x %4d %10d %s\n", $nr, $nc, $fsz, $fnm;
	my $slowest;
	foreach my $typ ("xs", "pp") {
	    #$typ eq "pp" && $fsz > 10_000_000 and next;
	    foreach my $test ("perl", "gtln", "bndc", "splt") {
		"$typ$test" eq "ppsplt" and next; # Only run once
		#$typ eq "pp" && $test eq "bndc" && $nc > 250 and next; # NYI
		open $fh, "<", $fnm or die "$fnm: $!";
		if ($test eq "splt") {
		    @row = split m/,/ => scalar <$fh>;
		    }
		else {
		    $csv = "Text::CSV_\U$typ"->new ({ binary => 1 });
		    $csv->parse (scalar <$fh>) or die $csv->error_diag;
		    @row = $csv->fields;
		    }
		my $ncol = @row;
		my $start = [ gettimeofday ];
		$n = 0;
		$test{$test}->();
		my $used = tv_interval ($start, [ gettimeofday ]);
		$slowest //= $used;
		my $speed = int (100 * $used / $slowest);
		printf "$typ $test: %9d x %4d parsed in %9.3f seconds - %4d\n",
		    $n, $ncol, $used, $speed;
		eof   $fh or die $csv->error_diag;
		close $fh or die "$fnm: $!";
		$nr == 1024 and $res{$nc}{"$typ $test"} = $speed;
		}
	    }
	}
    }

binmode STDOUT, ":utf8";
$csv = Text::CSV_XS->new ({ eol => "\r\n" });
foreach my $nc (sort { $a <=> $b } keys %res) {
    $csv->print (*STDOUT, [ $nc, @{$res{$nc}}{
	  "xs perl", "xs gtln", "xs bndc", "pp perl", "pp gtln", "pp bndc",
	  "pp splt" } ]);
    }

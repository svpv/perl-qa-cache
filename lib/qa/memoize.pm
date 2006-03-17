package qa::memoize;

use strict;
our $NOCACHE ||= $ENV{QA_NOCACHE};

use qa::cache;
use File::stat qw(stat);

sub memoize_st1 ($) {
	return if $NOCACHE;
	my $id  = shift;
	my $pkg = caller;
	my $sym = $pkg . '::' . $id;
	no strict 'refs';
	my $code = *{$sym}{CODE};
	my $cache;
	no warnings 'redefine';
	*$sym = sub ($) {
		goto $code if $NOCACHE;
		my $f = shift;
		$cache ||= qa::cache->TIEHASH($id);
		my $st0 = stat($f) or die "$id: $f: $!";
		my @ism0 = ($st0->ino, $st0->size, $st0->mtime);
		my $v = $cache->FETCH("@ism0");
		return $v if defined $v;
		$v = $code->($f);
		my $st1 = stat($f) or die "$id: $f: $!";
		my @ism1 = ($st1->ino, $st1->size, $st1->mtime);
		die "$id: $f: file has changed" unless "@ism0" eq "@ism1";
		$cache->STORE("@ism0", $v) if defined $v;
		return $v;
	}
}

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(memoize_st1);

1;

package qa::memoize;

use strict;
our $NOCACHE ||= $ENV{QA_NOCACHE};

use constant {
	st_ino => 1,
	st_size => 7,
	st_mtime => 9,
};

use constant {
	ISM => 0,
	BSM => 1,
};

sub basename ($) {
	$_[0] =~ m#(?>.*/)(.*[^.].*)#s or
	$_[0] =~ m#(?:.*/)?([^/]*[^/.][^/]*)/*\z#s or
		die "$_[0]: no valid basename";
	return $1;
}

sub memoize_st1_ ($$) {
	return if $NOCACHE;
	my $id  = shift;
	my $how = shift;
	my $pkg = caller;
	my $sym = $pkg . '::' . $id;
	no strict 'refs';
	my $code = *{$sym}{CODE};
	my $cache;
	no warnings 'redefine';
	*$sym = sub ($) {
		goto $code if $NOCACHE;
		$cache ||= do {
			require qa::cache;
			qa::cache->TIEHASH($id);
		};
		my $f = shift;
		my @st0 = stat($f) or die "$id: $f: $!";
		my $ism0 = join " " => @st0[st_ino,st_size,st_mtime];
		my $k = ($how == ISM) ? $ism0 :
			join " " => basename($f), @st0[st_size,st_mtime];
		my $v = $cache->FETCH($k);
		return $v if defined $v;
		$v = $code->($f);
		my @st1 = stat($f) or die "$id: $f: $!";
		my $ism1 = join " " => @st1[st_ino,st_size,st_mtime];
		die "$id: $f: file has changed" unless $ism0 eq $ism1;
		$cache->STORE($k, $v) if defined $v;
		return $v;
	}
}

# memoize a function which takes single file argument by (ino,size,mtime)
sub memoize_ism ($) {
	push @_, ISM;
	goto &memoize_st1_;
}

# memoize a function which takes single file argument by (basename,size,mtime)
sub memoize_bsm ($) {
	push @_, BSM;
	goto &memoize_st1_;
}

# compat
*memoize_st1 = \&memoize_ism;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(memoize_ism memoize_bsm);
our @EXPORT_OK = qw(memoize_st1 basename);

1;

package qa::cache;

use strict;
our $VERSION = '0.11';

require XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

our $topdir = "$ENV{HOME}/.qa-cache";

my %blessed;

sub TIEHASH ($$) {
	my ($class, $id) = @_;
	return $blessed{$id} if $blessed{$id};
	my $dir = "$topdir/$id";
	use constant EEXIST => 17; # since v7
	mkdir $_ and warn "created directory $_"
		or $! == EEXIST or warn "$_: $!"
			for $topdir, $dir;
	my $self = $class->raw_open($dir)
		or die "cannot open cache in $dir";
	$blessed{$id} = $self;
	use Scalar::Util qw(weaken);
	weaken $blessed{$id};
	return $self;
}

use Storable qw(freeze thaw);

sub STORE ($$$) {
	my ($self, $k, $v) = @_;
	$k = freeze($k) if ref $k;
	if (ref $v) {
		$v = freeze($v);
		$v .= "\x02";
	}
	elsif ($v ne "") {
		$v .= "\x00";
	}
	$self->raw_put($k, $v);
}

sub FETCH ($$) {
	my ($self, $k) = @_;
	$k = freeze($k) if ref $k;
	my $v = $self->raw_get($k);
	return unless defined $v;
	return $v if $v eq "";
	$v = thaw($v) if chop($v) eq "\x02";
	return $v;
}

sub EXISTS ($$) {
	my ($self, $k) = @_;
	$k = freeze($k) if ref($k);
	return $self->raw_exists($k);
}

sub DESTROY {
	my $self = shift;
	$self->raw_close;
}

sub clean {
	my ($self, $days) = (@_, 33);
	$self->raw_clean($days);
}

1;

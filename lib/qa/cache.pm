package qa::cache;

use strict;
our $VERSION = '0.02';

use BerkeleyDB 0.34;
die "db 4.4 required (got $BerkeleyDB::db_version)"
	if $BerkeleyDB::db_version < 4.4;

our $topdir = "$ENV{HOME}/.qa-cache";
my $dbenv;

sub init_dbenv () {
	-d $topdir or mkdir $topdir;
	my %args = (
		-Home => $topdir,
		-Flags => DB_CREATE | DB_INIT_CDB | DB_INIT_MPOOL,
		-ErrFile => *STDERR, -ErrPrefix => __PACKAGE__,
		-ThreadCount => 16);
	$dbenv = BerkeleyDB::Env->new(%args)
		or die $BerkeleyDB::Error;
	$dbenv->set_isalive == 0 and $dbenv->failchk == 0
		or die $BerkeleyDB::Error;
}

my %blessed;
my $pagesize;

sub TIEHASH ($$) {
	my ($class, $id) = @_;
	return $blessed{$id} if $blessed{$id};
	init_dbenv() unless $dbenv;
	my $dir = "$topdir/$id";
	-d $dir or mkdir $dir;
	my %args = (
		-Env => $dbenv,
		-Filename => "$id/cache.db",
		-Flags => DB_CREATE);
	my $db = BerkeleyDB::Hash->new(%args)
		or die $BerkeleyDB::Error;
	$pagesize ||= $db->db_stat->{hash_pagesize};
	my $self = bless [ $dir, $db ] => $class;
	$blessed{$id} = $self;
	use Scalar::Util qw(weaken);
	weaken $blessed{$id};
	return $self;
}

use Storable qw(freeze thaw);
use Compress::LZO qw(compress decompress);
use Digest::SHA1 qw(sha1);

use constant {
	V_STO	=> 1<<1,	# STO is Special Theory of Relativity
	V_LZO	=> 1<<2,	# LZO is real-time compressor
};

my $today = int($^T / 3600 / 24);

sub STORE ($$$) {
	my ($self, $k, $v) = @_;
	$k = freeze($k) if ref $k;
	$k = sha1($k);
	my $vflags = 0;
	if (ref $v) {
		$v = freeze($v);
		$vflags |= V_STO;
	}
	if (length($v) > 768) {
		$v = compress($v);
		$vflags |= V_LZO;
	}
	my ($dir, $db) = @$self;
	if (length($v) > $pagesize / 2) {
		my ($subdir, $file) = unpack "H2H*", $k;
		$subdir = "$dir/$subdir";
		$file = "$subdir/$file";
		-d $subdir or mkdir $subdir;
		open my $fh, ">", "$file.$$"
			or die "$file.$$: $!";
		local ($\, $,);
		print $fh pack("S", $vflags), $v
			or die "$file.$$: $!";
		close $fh
			or die "$file.$$: $!";
		rename "$file.$$", $file
			or die "$file.$$: $!";
	}
	else {	# SSS: mtime, atime, vflags
		$db->db_put($k, pack("SSS", $today, $today, $vflags) . $v) == 0
			or die $BerkeleyDB::Error;
	}
}

sub FETCH ($$) {
	my ($self, $k) = @_;
	$k = freeze($k) if ref $k;
	$k = sha1($k);
	my ($dir, $db) = @$self;
	my ($vflags, $v);
	if ($db->db_get($k, $v) == 0) {
		(my $m, my $a, $vflags) = unpack "SSS", $v;
		substr $v, 0, 6, "";
		$db->db_put($k, pack("SSS", $m, $today, $vflags) . $v)
			if $a != $today; # XXX not atomic
	}
	else {
		my ($subdir, $file) = unpack "H2H*", $k;
		$subdir = "$dir/$subdir";
		$file = "$subdir/$file";
		open my $fh, "<", $file or return;
		local $/;
		$v = <$fh>;
		$vflags = unpack "S", $v;
		substr $v, 0, 2, "";
	}
	$v = decompress($v) if $vflags & V_LZO;
	$v = thaw($v) if $vflags & V_STO;
	return $v;
}

sub EXISTS ($$) {
	my ($self, $k) = @_;
	$k = freeze($k) if ref($k);
	$k = sha1($k);
	my ($dir, $db) = @$self;
	return 1 if $db->db_get($k, my $v) == 0;
	my ($subdir, $file) = unpack "H2H*", $k;
	$subdir = "$dir/$subdir";
	$file = "$subdir/$file";
	return -f $file;
}

sub DELETE ($$) {
	my ($self, $k) = @_;
	$k = freeze($k) if ref($k);
	$k = sha1($k);
	my ($dir, $db) = @$self;
	$db->db_del($k);
	my ($subdir, $file) = unpack "H2H*", $k;
	$subdir = "$dir/$subdir";
	$file = "$subdir/$file";
	unlink $file;
}

# execute the END when interrupted by a signal --
# it is VERY important to release all locks and shut down gracefully
use sigtrap qw(die untrapped normal-signals);

# Purge entries that have not been accessed for that many days.
our $expire = 33;

sub autoclean ($) {
	my $self = shift;
	my ($dir, $db) = @$self;
	my $cur = $db->_db_write_cursor() or return;
	if ($db->db_get("cleanup", my $cleanup) != 0) {
		$db->db_put("cleanup", $today);
		return;
	}
	elsif ($cleanup == $today) {
		return;
	}
	while ($cur->c_get(my $k, my $v, DB_NEXT) == 0) {
		next if $k eq "cleanup";
		my ($m, $a, $vflags) = unpack "SSS", $v;
		next if $a + $expire > $today;
		next if $m + $expire > $today;
		$cur->c_del();
	}
	$db->db_sync;
	my $wanted = sub {
		stat or return;
		-f _ and -M _ > $expire and -A _ > $expire and unlink;
	};
	require File::Find;
	File::Find::find($wanted, $dir);
}

# Note that this END block is executed right before BerkeleyDB END block,
# which will force BerkeleyDB shutdown.  This seems to be the right place
# to attempt cleanup and release resources.
END {
	undef $dbenv;
	while (my ($id, $self) = each %blessed) {
		next unless $self and @$self;
		# do not cleanup on abnormal exit
		$self->autoclean if $? == 0;
		undef @$self;
	}
}

# It seems that DESTROY gets called after END, which is good for us,
# because END provides a chance to cancel cleanup on abnormal exit.
# However, we should not rely on this behaviour.
sub DESTROY {
	my $self = shift;
	return unless $self and @$self;
	$self->autoclean;
	undef @$self;
}

1;

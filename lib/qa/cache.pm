package qa::cache;

use strict;
use BerkeleyDB;

our $topdir = "$ENV{HOME}/.qa-cache";
my $topdir_fd;
my $dbenv;

sub init_dbenv () {
	use Fcntl qw(:flock O_DIRECTORY);
	-d $topdir or mkdir $topdir;
	sysopen $topdir_fd, $topdir, O_DIRECTORY or die "$topdir: $!";
	if (flock $topdir_fd, LOCK_EX | LOCK_NB) {
		$dbenv = BerkeleyDB::Env->new(-Home => $topdir,
			-Verbose => 1, -ErrFile => *STDERR,
			-Flags => DB_CREATE | DB_INIT_CDB | DB_INIT_MPOOL)
				or die $BerkeleyDB::Error;
		# TODO: drop all locks
		flock $topdir_fd, LOCK_SH;
	}
	else {
		flock $topdir_fd, LOCK_SH;
		$dbenv = BerkeleyDB::Env->new(-Home => $topdir,
			-Verbose => 1, -ErrFile => *STDERR,
			-Flags => DB_JOINENV)
				or die $BerkeleyDB::Error;
	}
}

my %blessed;
my $pagesize;

sub TIEHASH ($$) {
	my ($class, $id) = @_;
	return $blessed{$id} if $blessed{$id};
	init_dbenv() unless $dbenv;
	my $dir = "$topdir/$id";
	-d $dir or mkdir $dir;
	my $db = BerkeleyDB::Hash->new(-Filename => "$id/cache.db",
		-Env => $dbenv, -Flags => DB_CREATE)
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
	V_STO	=> 2**1,	# STO is Special Theory of Relativity
	V_LZO	=> 2**2,	# LZO is real-time compressor
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
		open my $fh, ">", "$file.$$" or die $!;
		syswrite $fh, pack("S", $vflags);
		syswrite $fh, $v;
		close $fh;
		rename "$file.$$", $file;
	}
	else {	# SSS: mtime, atime, vflags
		$db->db_put($k, pack("SSS", $today, 0, $vflags) . $v);
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

# BerkeleyDB cleans up at the END, so do I
my $global_destruction;

# execute the END when interrupted by a signal --
# it is VERY important to release all locks and shut down gracefully
use sigtrap qw(die untrapped normal-signals);

our $expire = 33;

sub DESTROY ($) {
	return if $global_destruction;
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
		next if $a + 33 > $today;
		next if $m + 33 > $today;
		$cur->c_del();
	}
	my $wanted = sub {
		stat or return;
		-f _ and -M _ > $expire and -A _ > $expire and unlink;
		-d _ and rmdir;
	};
	require File::Find;
	File::Find::finddepth($wanted, $dir);
}

END {
	undef $dbenv;
	while (my ($id, $self) = each %blessed) {
		next unless $self;
		$self->DESTROY();
		undef @$self;
	}
	$global_destruction = 1;
}

1;

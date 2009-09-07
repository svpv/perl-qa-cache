package qa::cache;

use strict;
our $VERSION = '0.04';

use BerkeleyDB 0.39;
die "db 4.4 required (got $BerkeleyDB::db_version)"
	if $BerkeleyDB::db_version < 4.4;

our $topdir = "$ENV{HOME}/.qa-cache";
my $dbenv;

sub init_dbenv () {
	-d $topdir or mkdir $topdir;
	# Serialize dbenv open by locking topdir fd.
	# Note that the fd will be autoclosed.
	use Fcntl qw(O_RDONLY O_DIRECTORY LOCK_EX);
	sysopen my $fd, $topdir, O_RDONLY | O_DIRECTORY
		or die "$topdir: $!";
	flock $fd, LOCK_EX
		or die "$topdir: $!";
	my %args = (
		-Home => $topdir,
		-Flags => DB_CREATE | DB_INIT_CDB | DB_INIT_MPOOL,
		-ErrFile => *STDERR, -ErrPrefix => __PACKAGE__,
		-MsgFile => \*STDERR, # rt.cpan.org #46313
		-ThreadCount => 16);
	$dbenv = BerkeleyDB::Env->new(%args)
		or die $BerkeleyDB::Error;
	# This will remove stale read locks.  Stale write locks cannot be
	# recovered automatically, since it is likely that database was left
	# in inconsistent state.  Thus, one has to remove the entire cache
	# manually.  Otherwise, at the risk of corrupted data, one may try
	# to remove the environment:
	#	rm ~/.qa-cache/__db*
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

# In DB_INIT_CDB mode, internal locks are obtained automatically for each
# databse access.  Since write locks cannot be recovered, we need to block
# signals for critical ops like db_put.
{
	use POSIX qw(sigprocmask SIG_BLOCK SIG_SETMASK);

	my $sigset_all = POSIX::SigSet->new;
	$sigset_all->fillset;

	my $sigset_old = POSIX::SigSet->new;

	sub block_signals () {
		defined sigprocmask(SIG_BLOCK, $sigset_all, $sigset_old)
			or die "cannot block signals: $!";
	}

	sub unblock_signals () {
		defined sigprocmask(SIG_SETMASK, $sigset_old)
			or die "cannot unblock signals: $!";
	}
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
		# Big cache entries are stored under $dir.
		# To improve cache capacity, we use two leading hex digits
		# for subdir.  The same technique is used in git(1).
		my ($subdir, $file) = unpack "H2H*", $k;
		$subdir = "$dir/$subdir";
		$file = "$subdir/$file";
		-d $subdir or mkdir $subdir;
		open my $fh, ">", "$file.$$"
			or die "$file.$$: $!";
		local ($\, $,);
		# File format: vflags, data.
		print $fh pack("S", $vflags), $v
			or die "$file.$$: $!";
		close $fh
			or die "$file.$$: $!";
		# Note that rename is atomic.  By using temporary file,
		# we try to avoid simultaneous writes.  And by using rename,
		# we try to avoid partially written files.
		rename "$file.$$", $file
			or die "$file.$$: $!";
	}
	else {
		# Small cache entries are stored in $db.
		block_signals;
		# Data format: mtime, atime, vflags, data.
		my $rc = $db->db_put($k, pack("SSS", $today, $today, $vflags) . $v);
		unblock_signals;
		die "db_put: $rc"
			unless $rc == 0;
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
		if ($a != $today) {
			block_signals;
			# We check errors only on first-time STORE.
			# After all, what they request here is only a FETCH.
			$db->db_put($k, pack("SSS", $m, $today, $vflags) . $v);
			unblock_signals;
		}
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

# Purge entries that have not been accessed for that many days.
our $expire = 33;

sub autoclean ($) {
	my $self = shift;
	my ($dir, $db) = @$self;

	# Check if cleanup is needed.
	# Cleanup is performed on a daily basis.
	my $need_cleanup;
	{
		block_signals;
		# Cleanup date must be checked and updated atomically -
		# otherwise, we end up running two simultaneous cleanups.
		# For this reason, we need to obtain a write cursor.
		my $cur = $db->_db_write_cursor;
		# Note that we use SHA1 keys for user data, so it is not
		# a problem to use shorter text keys for our special purpose.
		if ($db->db_get("cleanup", my $cleanup) != 0) {
			# First-time cleanup: store the date and do nothing.
			$db->db_put("cleanup", $today);
		}
		elsif ($cleanup != $today) {
			# Store the date and proceed with cleanup.
			$db->db_put("cleanup", $today);
			$need_cleanup = 1;
		}
		unblock_signals;
	}
	return unless $need_cleanup;

	# Cleanup $db.
	{
		# To traverse the cache, we obtain only a read cursor,
		# so that graceful recovery is possible.
		my $cur = $db->db_cursor;
		while ($cur->c_get(my $k, my $v, DB_NEXT) == 0) {
			# Due to SHA1, user keys are 20 bytes long.
			# This provides an easy way to skip our "cleanup" key.
			next unless length($k) == 20;
			my ($m, $a, $vflags) = unpack "SSS", $v;
			next if $a + $expire > $today;
			next if $m + $expire > $today;
			block_signals;
			$db->db_del($k);
			unblock_signals;
		}
	}

	# Cleanup $dir.
	{
		my $wanted = sub {
			# We remove only files with user data, and also
			# temporary files with .$$ suffix created before atomic
			# rename.  Due to SHA1 naming, files with user data are
			# 38 bytes long.  This provides an easy way to skip
			# cache.db and environment files.
			length >= 38 and lstat and -f _ or return;
			-M _ > $expire and -A _ > $expire and unlink;
		};
		require File::Find;
		File::Find::find($wanted, $dir);
	}
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

# When the cache object is referenced by a lexical variable, DESTROY usually
# happens before the END block.  However, it is possible that DESTROY actually
# gets called after the END block (e.g., in qa::memoize module, the cache
# object is stored in CV pad).  Note that END before DESTROY provides a chance
# to cancel cleanup on abnormal exit.
sub DESTROY {
	my $self = shift;
	return unless $self and @$self;
	$self->autoclean;
	undef @$self;
}

1;

%define dist qa-cache
Name: perl-%dist
Version: 0.07
Release: alt1

Summary: Simple and efficient cache for memoization
License: GPL or Artistic
Group: Development/Perl

URL: %CPAN %dist
Source: %dist-%version.tar

BuildArch: noarch

# Automatically added by buildreq on Fri May 22 2009 (-bi)
BuildRequires: perl-BerkeleyDB perl-Compress-LZO perl-Digest-SHA1 perl-Storable perl-devel

%description
no description

%prep
%setup -q -n %dist-%version

%build
%perl_vendor_build

%install
%perl_vendor_install

%files
%perl_vendor_privlib/qa*

%changelog
* Sun Aug 15 2010 Alexey Tourbin <at@altlinux.ru> 0.07-alt1
- qa/cache.pm: increase db/fs theshold size (1/2 -> 3/4 pagesize)

* Tue Aug 10 2010 Alexey Tourbin <at@altlinux.ru> 0.06-alt1
- qa/cache.pm: set -MsgFile => \*STDERR
- qa/cache.pm: downgrade db_put error to a warning
- qa/cache.pm: require non-leaking Digest::SHA1 2.13

* Mon Aug 17 2009 Alexey Tourbin <at@altlinux.ru> 0.05-alt1
- qa/cache.pm: better diagnostics on db_put failure

* Mon Jul 20 2009 Alexey Tourbin <at@altlinux.ru> 0.04-alt1
- qa/cache.pm: serialize dbenv open by locking topdir fd

* Fri May 22 2009 Alexey Tourbin <at@altlinux.ru> 0.03-alt1
- qa/cache.pm: updated BerkeleyDB code
  + enabled automatic recovery for stale read locks
  + reimplemented signal handling for write ops

* Sun Apr 05 2009 Alexey Tourbin <at@altlinux.ru> 0.02-alt1
- qa/memoize.pm: implemented (basename,size,mtime) mode
- qa/cache.pm: cleanup and better error handling

* Mon Feb 16 2009 Alexey Tourbin <at@altlinux.ru> 0.01-alt1
- initial release, based on Mar 2006 version

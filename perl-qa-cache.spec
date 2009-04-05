%define dist qa-cache
Name: perl-%dist
Version: 0.02
Release: alt1

Summary: Simple and efficient cache for memoization
License: GPL or Artistic
Group: Development/Perl

URL: %CPAN %dist
Source: %dist-%version.tar

BuildArch: noarch

# Automatically added by buildreq on Mon Feb 16 2009 (-bi)
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
* Sun Apr 05 2009 Alexey Tourbin <at@altlinux.ru> 0.02-alt1
- qa/memoize.pm: implemented (basename,size,mtime) mode
- qa/cache.pm: cleanup and better error handling

* Mon Feb 16 2009 Alexey Tourbin <at@altlinux.ru> 0.01-alt1
- initial release, based on Mar 2006 version

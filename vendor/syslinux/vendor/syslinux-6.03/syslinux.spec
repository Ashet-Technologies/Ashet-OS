# -*- rpm -*-
%define RPMVERSION 6.03
%define VERSION    6.03
Summary: Kernel loader which uses a FAT, ext2/3 or iso9660 filesystem or a PXE network
Name: syslinux
Version: %{RPMVERSION}
Release: 1
License: GPL
Group: System/Boot
Source0: ftp://ftp.kernel.org/pub/linux/utils/boot/syslinux/%{name}-%{VERSION}.tar.gz
ExclusiveArch: i386 i486 i586 i686 athlon pentium4 x86_64
Packager: H. Peter Anvin <hpa@zytor.com>
Buildroot: %{_tmppath}/%{name}-%{VERSION}-root
BuildRequires: nasm >= 2.03, perl
Autoreq: 0
%ifarch x86_64
Requires: mtools, libc.so.6()(64bit)
%define my_cc gcc
%else
Requires: mtools, libc.so.6
%define my_cc gcc -m32
%endif

# NOTE: extlinux belongs in /sbin, not in /usr/sbin, since it is typically
# a system bootloader, and may be necessary for system recovery.
%define _sbindir /sbin

%package devel
Summary: Development environment for SYSLINUX add-on modules
Group: Development/Libraries
Requires: syslinux

%description
SYSLINUX is a suite of bootloaders, currently supporting DOS FAT
filesystems, Linux ext2/ext3 filesystems (EXTLINUX), PXE network boots
(PXELINUX), or ISO 9660 CD-ROMs (ISOLINUX).  It also includes a tool,
MEMDISK, which loads legacy operating systems from these media.

%description devel
The SYSLINUX boot loader contains an API, called COM32, for writing
sophisticated add-on modules.  This package contains the libraries
necessary to compile such modules.

%package extlinux
Summary: The EXTLINUX bootloader, for booting the local system.
Group: System/Boot
Requires: syslinux

%description extlinux
The EXTLINUX bootloader, for booting the local system, as well as all
the SYSLINUX/PXELINUX modules in /boot.

%package tftpboot
Summary: SYSLINUX modules in /tftpboot, available for network booting
Group: Applications/Internet
Requires: syslinux

%description tftpboot
All the SYSLINUX/PXELINUX modules directly available for network
booting in the /tftpboot directory.

%prep
%setup -q -n syslinux-%{VERSION}

%build
make CC='%{my_cc}' clean
make CC='%{my_cc}' installer
make CC='%{my_cc}' -C sample tidy

%install
rm -rf %{buildroot}
make CC='%{my_cc}' install-all \
	INSTALLROOT=%{buildroot} BINDIR=%{_bindir} SBINDIR=%{_sbindir} \
	LIBDIR=%{_libdir} DATADIR=%{_datadir} \
	MANDIR=%{_mandir} INCDIR=%{_includedir} \
	TFTPBOOT=/tftpboot EXTLINUXDIR=/boot/extlinux
make CC='%{my_cc}' -C sample tidy
mkdir -p %{buildroot}/etc
( cd %{buildroot}/etc && ln -s ../boot/extlinux/extlinux.conf . )

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root)
%doc COPYING NEWS doc/*
%doc sample
%{_mandir}/man*/*
%{_bindir}/*
%{_datadir}/syslinux/*.com
%{_datadir}/syslinux/*.exe
%{_datadir}/syslinux/*.c32
%{_datadir}/syslinux/*.bin
%{_datadir}/syslinux/*.0
%{_datadir}/syslinux/memdisk
%{_datadir}/syslinux/dosutil/*
%{_datadir}/syslinux/diag/*

%files devel
%{_datadir}/syslinux/com32

%files extlinux
%{_sbindir}/extlinux
/boot/extlinux
%config /etc/extlinux.conf

%files tftpboot
/tftpboot

%post extlinux
# If we have a /boot/extlinux.conf file, assume extlinux is our bootloader
# and update it.
if [ -f /boot/extlinux/extlinux.conf ]; then \
	extlinux --update /boot/extlinux ; \
elif [ -f /boot/extlinux.conf ]; then \
	mkdir -p /boot/extlinux && \
	mv /boot/extlinux.conf /boot/extlinux/extlinux.conf && \
	extlinux --update /boot/extlinux ; \
fi

%postun

%changelog
* Fri Dec 18 2009 H. Peter Anvin <hpa@zytor.com>
- Require NASM 2.03
- Package dosutil

* Thu May 29 2008 H. Peter Anvin <hpa@zytor.com>
- Use install targets; clean up various paths.

* Thu Jan 10 2008 H. Peter Anvin <hpa@zytor.com>
- Add man pages.

* Mon Nov 19 2007 Bernard Li <bernard@vanhpc.org>
- Added netpbm-progs (provides pngtopnm) to BuildPrereq (this should be
  changed to BuildRequires since it is deprecated...)

* Thu Mar 15 2007 H. Peter Anvin <hpa@zytor.com>
- Move extlinux /boot stuff into /boot/extlinux.

* Thu Jan 25 2007 H. Peter Anvin <hpa@zytor.com>
- Hacks to make the 32-bit version build correctly on 64-bit machines.

* Mon Sep 19 2006 H. Peter Anvin <hpa@zytor.com>
- Add a syslinux-tftpboot module.
- Factor extlinux into its own package.
- Move to %{_datadir} (/usr/share).

* Wed Sep 21 2005 H. Peter Anvin <hpa@zytor.com>
- If /boot/extlinux.conf exist, run extlinux --update.

* Fri Sep  9 2005 H. Peter Anvin <hpa@zytor.com>
- Copy, don't link, *.c32 into /boot; rpm doesn't like breaking links.

* Tue Aug 23 2005 H. Peter Anvin <hpa@zytor.com>
- Put *.c32 into /boot.

* Thu Dec 30 2004 H. Peter Anvin <hpa@zytor.com>
- libsyslinux dropped in syslinux 3.00.
- Additional documentation.
- Add extlinux.

* Tue Dec 14 2004 H. Peter Anvin <hpa@zytor.com>
- Add a devel package for the com32 library added in 2.12.

* Wed Apr 16 2003 H. Peter Anvin <hpa@zytor.com> 2.04-1
- 2.04 release
- Add support for libsyslinux.so*
- Templatize for inclusion in CVS tree

* Thu Apr 10 2003 H. Peter Anvin <hpa@zytor.com>
- 2.03 release
- Add support for libsyslinux.a
- Add keytab-lilo.pl to the /usr/lib/syslinux directory
- Modernize syntax
- Support building on x86-64

* Thu Feb 13 2003 H. Peter Anvin <hpa@zytor.com>
- 2.02 release; no longer setuid

* Thu Jan 30 2003 H. Peter Anvin <hpa@zytor.com>
- Prepare for 2.01 release; make /usr/bin/syslinux setuid root

* Fri Oct 25 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 2.00.

* Tue Aug 27 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.76.

* Fri Jun 14 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.75.

* Sat Jun  1 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.74.

* Sun May 26 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.73.

* Tue Apr 23 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.72.

* Wed Apr 17 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.71.
- Update the title.

* Wed Apr 17 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.70.

* Sat Feb  3 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.67.

* Tue Jan  1 2002 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.66.

* Sat Dec 15 2001 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.65; make appropriate changes.

* Sat Aug 24 2001 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.64.

* Mon Aug  6 2001 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.63.
- Use make install since the stock SYSLINUX distribution now supports
  INSTALLROOT.

* Sat Apr 24 2001 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.62.

* Sat Apr 14 2001 H. Peter Anvin <hpa@zytor.com>
- Fix missing %files; correct modes.

* Fri Apr 13 2001 H. Peter Anvin <hpa@zytor.com>
- Upgrade to 1.61
- Install auxilliary programs in /usr/lib/syslinux

* Sat Feb 10 2001 Matt Wilson <msw@redhat.com>
- 1.52

* Wed Jan 24 2001 Matt Wilson <msw@redhat.com>
- 1.51pre7

* Mon Jan 22 2001 Matt Wilson <msw@redhat.com>
- 1.51pre5

* Fri Jan 19 2001 Matt Wilson <msw@redhat.com>
- 1.51pre3, with e820 detection

* Tue Dec 12 2000 Than Ngo <than@redhat.com>
- rebuilt with fixed fileutils

* Thu Nov 9 2000 Than Ngo <than@redhat.com>
- update to 1.49
- update ftp site
- clean up specfile
- add some useful documents

* Tue Jul 18 2000 Nalin Dahyabhai <nalin@redhat.com>
- add %%defattr (release 4)

* Wed Jul 12 2000 Prospector <bugzilla@redhat.com>
- automatic rebuild

* Thu Jul 06 2000 Trond Eivind Glomsrød <teg@redhat.com>
- use %%{_tmppath}
- change application group (Applications/Internet doesn't seem
  right to me)
- added BuildRequires

* Tue Apr 04 2000 Erik Troan <ewt@redhat.com>
- initial packaging

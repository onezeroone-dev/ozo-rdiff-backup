Name:      ozo-rdiff-backup
Version:   1.0.0
Release:   1%{?dist}
Summary:   Automates the use of rdiff-backup
BuildArch: noarch

License:   GPL
Source0:   %{name}-%{version}.tar.gz

Requires:  bash

%description
This script automates the use of rdiff-backup to perform incremental backups of remote linux systems over SSH. It will mount a dedicated volume, generate an increment, perform increment maintenancce, and unmount the volume.

%prep
%setup -q

%install
rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/etc
cp ozo-rdiff-backup.conf $RPM_BUILD_ROOT/etc

mkdir -p $RPM_BUILD_ROOT/etc/cron.d
cp ozo-rdiff-backup $RPM_BUILD_ROOT/etc/cron.d

mkdir -p $RPM_BUILD_ROOT/etc/ozo-rdiff-backup.conf.d
cp ozo-rdiff-remote-host.conf.example $RPM_BUILD_ROOT/etc/ozo-rdiff-backup.conf.d

mkdir -p $RPM_BUILD_ROOT/usr/sbin
cp ozo-rdiff-backup.sh $RPM_BUILD_ROOT/usr/sbin

%files
%attr (0644,root,root) %config(noreplace) /etc/ozo-rdiff-backup.conf
%attr (0644,root,root) %config(noreplace) /etc/cron.d/ozo-rdiff-backup
%attr (0644,root,root) /etc/ozo-rdiff-backup.conf.d/ozo-rdiff-remote-host.conf.example
%attr (0700,root,root) /usr/sbin/ozo-rdiff-backup.sh

%post
if [[ ! -d /srv/ozo-rdiff ]]
then
    mkdir -p /srv/ozo-rdiff
    chmod 700 /srv/ozo-rdiff
fi

%changelog
* Fri Feb 26 2021 One Zero One RPM Manager <repositories@onezeroone.dev> - 1.0.0-1
- Initial release

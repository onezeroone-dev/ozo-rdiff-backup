Name:      onezeroone-release
Version:   1.0.0
Release:   1%{?dist}
Summary:   One Zero One Packages for Enterprise Linux
BuildArch: noarch

License:   GPL
Source0:   %{name}-%{version}.tar.gz

Requires:  bash

%description
Installs the One Zero One EL repository and public key file.

%prep
%setup -q

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/etc/pki/rpm-gpg
cp RPM-GPG-KEY-ONEZEROONE $RPM_BUILD_ROOT/etc/pki/rpm-gpg

mkdir -p $RPM_BUILD_ROOT/etc/yum.repos.d
cp onezeroone.repo $RPM_BUILD_ROOT/etc/yum.repos.d
cp onezeroone-test.repo $RPM_BUILD_ROOT/etc/yum.repos.d

%files
%attr (0644,root,root) /etc/pki/rpm-gpg/RPM-GPG-KEY-ONEZEROONE
%attr (0644,root,root) /etc/yum.repos.d/onezeroone.repo
%attr (0644,root,root) %config(noreplace) /etc/yum.repos.d/onezeroone-test.repo

%changelog
* Sat Aug 02 2025 One Zero One RPM Manager <repositories@onezeroone.dev> - 1.0.0-1
- Initial release

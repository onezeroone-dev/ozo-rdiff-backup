# OZO Rdiff Backup Installation and Configuration
## Overview
This script automates the use of `rdiff-backup` to perform incremental backups of remote linux systems over SSH. It will mount a dedicated volume to `/srv/ozo-rdiff`, generate an increment, perform increment maintenance, and unmount the volume. It runs with no arguments. When executed, it iterates through the _CONF_ files in `/etc/ozo-rdiff-backup.conf.d` and performs the job.

## Installation and Configuration
Choose an _rdiff-backup system_ for running the script and storing the incremental backups. The hosts that are backed up are the _remote system(s)_.

### Installation
To install this script on your rdiff-backup system, you must first register the One Zero One repository.

#### AlmaLinux 10, Red Hat Enterprise Linux 10, Rocky Linux 10 (RPM)
In a `root` shell:

```bash
rpm -Uvh https://repositories.onezeroone.dev/el/10/noarch/onezeroone-release-latest.el10.noarch.rpm
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-ONEZEROONE
dnf repolist
dnf -y install ozo-rdiff-backup
```

#### AlmaLinux 9, Red Hat Enterprise Linux 9, Rocky Linux 9 (RPM)
In a `root` shell:

```bash
rpm -Uvh https://repositories.onezeroone.dev/el/9/noarch/onezeroone-release-latest.el9.noarch.rpm
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-ONEZEROONE
dnf repolist
dnf -y install ozo-rdiff-backup
```

#### Debian (DEB)
PENDING.

### Configuration
#### Designate a Partition for Rdiff-Backup Operations
This script requires a dedicated volume that is mounted before running rdiff-backup jobs and unmounted when they are complete. On the rdiff-backup system (as `root`):

* Designate a partition (this could be on an external device) for storing rdiff increments and format it with the filesystem of your choice.
* Obtain the UUID of your filesystem with the `blkid` command.
* Test mounting the partition by UUID with with e.g., where "xxx..." is your `UUID`:

    `mount UUID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" /srv/ozo-rdiff`

* Unmount the partition

    `umount /srv/ozo-rdiff`

* Add a *noauto* entry in `/etc/fstab` for your UUID, e.g.:

    `UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /srv/ozo-rdiff xfs  noauto   0 0`

#### Configure ozo-rdiff-backup.conf
Edit `/etc/ozo-rdiff-backup.conf` and set `LUUID` to the UUID you identified above. Review the remaining variables:

|Variable|Value|Description|
|--------|-----|-----------|
|LBACKUP_DIRNAME|`backup`|Name of the subdirectory of `/srv/ozo-rdiff` where rdiff increments will be stored.|
|LRESTORE_DIRNAME|`restore`|Name of the subdirectory of `/srv/ozo-rdiff` that can be used for restore operations.|
|RDEF_INCLUDES|`/etc,/home,/root,/usr/local,/var`|Directories that will be _included_ in backup jobs for _all_ remote systems.|
|RDEF_EXCLUDES|`/,/var/lib/mysql`|Directories that will be _excluded_ from backup jobs for _all_ remote systems.|
|LFSCK_DAY|`1`|Day to run fsck, Sunday=0, Monday=1, Tuesday=2, Wednesday=3, Thursday=4, Friday=5, and Saturday=6.|

#### Create Remote Host Configuration File(s)
In `/etc/rdiff-backup.conf.d`, using `ozo-rdiff-remote-host.conf.example` as a template, create a *CONF* file for each remote system. Configuration file names must end in `.conf`.

|Variable|Example Value|Description|
|--------|-------------|-----------|
|RHOSTUSER|`root`|User that performs rdiff-backup on the remote system.|
|RHOSTFQDN|`"rdiff-host.example.com"`|Fully qualified domain name of the remote system.|
|RSSHPORT|`22`|SSH port for establishing a connection to the remote host.|
|RHOST_INCLUDES|`"/srv/plex,/usr/lib/plexmediaserver"`|Comma-separated list of *additional* inclusions for this remote system.|
|RHOST_EXCLUDES|`"/var/lib/pgsql"`|Comma-separated list of *additional* exclusions for this remote system.|
|RAGE|`180`|How many increments to keep (days)|

### Configure Cron
Modify `/etc/cron.d/ozo-rdiff-backup` to suit your scheduling needs. The default configuration runs `ozo-rdiff-backup.sh` every day at 6:00am.

####  Configure Local and Remote SSH
##### Rdiff-Backup System
On the rdiff-backup system (as `root`):

* Generate SSH keys for the `root` user:

    `# ssh keygen`

* Install your `root` user SSH keys to each of the Remote System(s) with e.g.:

    `ssh-copy-id -i root@rdiff-host.example.com`

##### Remote System(s)
On the remote system(s) (as `root`), install `rdiff-backup`.

* AlmaLinux, Red Hat Enterprise Linux, Rocky Linux (DNF): `dnf install rdiff-backup`
* Debian (APT): `apt-get install rdiff-backup`

Edit `/root/.ssh/authorized_keys` and prepend the shared key with:

`command="rdiff-backup server --restrict-mode read-only"`

## Notes
Please visit [One Zero One](https://onezeroone.dev) to learn more about other work.

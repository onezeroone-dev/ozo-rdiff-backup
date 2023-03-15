# OZO Rdiff Backup

This script automates the use of rdiff-backup to perform incremental backups of remote linux systems over SSH. It will mount a dedicated volume, generate an increment, perform increment maintenance, and unmount the volume.

It runs with no arguments. When executed, it iterates through the *CONF* files in `LCONF_DIR` (`/etc/ozo-rdiff-backup.conf.d`) and performs the configured rdiff-backup job.

Please visit https://onezeroone.dev to learn more about this script and my other work.

## Setup and Configuration

Choose an "Rdiff-Backup System" for running the script and storing the incremental backups. The hosts that are backed up are the "Remote System(s)"

### Designate a Partition for Rdiff-Backup Operations

This script requires a dedicated volume that is mounted before running rdiff-backup jobs and unmounted when they are complete. On the Rdiff-Backup System (as `root`):

- Create a partition (this could be on an external device) for storing rdiff increments and format it with the filesystem of your choice. This example uses *XFS*.
- Obtain the UUID of your filesystem with the `blkid` command.
- Create a mountpoint e.g., `/srv/rdiff`.
- Test mounting the partition by UUID with with e.g., where "xxx..." is your `UUID`:

    `# mount UUID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" /srv/rdiff`

- Unmount the partition with `# umount /srv/rdiff`
- Add a *noauto* entry in `/etc/fstab` for your UUID, e.g.:

    `UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /srv/rdiff xfs  noauto   0 0`

### Clone the Repository and Copy Files

Clone this repository to a temporary directory on the Rdiff-Backup System. Then (as `root`):

- Copy `rdiff-backup.sh` to `/etc/cron.daily` and set permissions to `rwx------` (`0700`)
- Copy `rdiff-backup.conf` to `/etc`
- Modify `/etc/rdiff-backup.conf` to suit your environment:

  |Variable|Example Value|Description|
  |--------|-------------|-----------|
  |LCONF_DIR|`"/etc/rdiff-backup.conf.d"`|Directory where the scipt will find rdiff-backup job CONF files|
  |LUUID|`"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"`|The UUID of the partition designated for rdiff-backup operations|
  |LMOUNTPOINT|`"/srv/rdiff"`|The mountpoint for the rdiff-backup volume|
  |LBACKUP_DIRNAME|`"backup"`|Name of the subdirectory of LMOUNTPOINT for storing backup increments|
  LRESTORE_DIRNAME|`"restore"`|Name of the subdirectory of LMOUNTPOINT that can be used for restore operations|
  |RDEF_INCLUDES|`"/etc,/home,/root,/usr/local,/var"`|Directories to include for every job|
  |RDEF_EXCLUDES|`"/,/var/lib/mysql"`|Directories to exclude from every job|
  |LFSCK_DAY|`1`|Day to run `fsck` on the `UUID`; Sunday=0 through Saturday=6|

- Create `/etc/rdiff-backup.conf.d`
- Use `rdiff-host.example.com.conf` as a template to create a *CONF* file in `/etc/rdiff-backup.conf.d` for each Remote System.

    |Variable|Example Value|Description|
    |--------|-------------|-----------|
    |RHOSTUSER|`root`|User that performs rdiff-backup on the Remote System|
    |RHOSTFQDN|`"rdiff-host.example.com"`|Fully qualified domain name of the Remote System|
    |RSSHPORT|`22`|SSH port for establishing a connection to the remote host|
    |RHOST_INCLUDES|`"/srv/plex,/usr/lib/plexmediaserver"`|Comma-separated list of *additional* inclusions for this remote system.|
    |RHOST_EXCLUDES|`"/var/lib/pgsql"`|Comma-separated list of *additional* exclusions for this remote system.|
    |RAGE|`180`|How many increments to keep (days)|

###  SSH Setup

#### Rdiff-Backup System

On the Rdiff-Backup System (as `root`):

- Generate SSH keys for the `root` user:

    `# ssh keygen`

- Install your `root` user SSH keys to each of the Remote System(s) with e.g.:

    `ssh-copy-id -i root@rdiff-host.example.com`

#### Remote System(s)

On the Remote System(s) (as `root`), install `rdiff-backup`.

- RedHat: `dnf install rdiff-backup`
- Debian: `apt-get install rdiff-backup`

Edit `/root/.ssh/authorized_keys` and prepend the shared key with:

`command="rdiff-backup server --restrict-mode read-only"`

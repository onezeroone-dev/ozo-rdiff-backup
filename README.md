# rdiff-backup.sh

This script automates the use of rdiff-backup to perform incremental backups of remote linux systems over SSH. It will mount a dedicated volume, generate an increment, perform increment maintenance, and unmount the volume.

Place this script in `/usr/local/sbin`. It expects a single command-line argument specifying the path to a job configuration file.

Please visit https://onezeroone.dev/automating-rdiff-backup-with-bash for more information.

## Prerequisite Local Configuration

- Generate your `root` user SSH keys with `# ssh keygen`
- Install your `root` user SSH keys to the remote host with e.g., `ssh-copy-id -i root@rdiff-host.example.com`
- Create a directory for configuration files e.g., `/etc/rdiff-backup.conf.d`
- Create a configuration file for the remote host containing:

    |Variable|Example Value|Description|
    |--------|-------------|-----------| 
    |HOST|`"rdiff-host.example.com"`|Fully qualified domain name for the remote linux host|
    |AGE|`180`|How long to keep increments (days)|
    |SSHPORT|`22`|SSH port for establishing a connection to the remote host|
    |HOST_INCLUDES|`"/srv/plex,/usr/lib/plexmediaserver"`|Comma-separated list of *additional* inclusions (see *default inclusions*, below)|
    |HOST_EXCLUDES|`"/var/lib/pgsql"`|Comma-separated list of *additional* exclusions (see *default exclusions*, below)|

    E.g., `/etc/rdiff-backup.conf.d/rdiff-host.example.com.conf`:

    ```sh
    HOST="rdiff-host.example.com"
    AGE="180"
    SSHPORT="22"
    HOST_INCLUDES=""
    HOST_EXCLUDES=""
    ```

- Create a partition (this could be on an external device) for storing rdiff increments, format it, and create a mountpoint e.g., `/srv/rdiff`. Obtain the UUID for this volume with `blkid`.

- Update `/usr/local/sbin/rdiff-backup.sh` with the `MOUNTPOINT` and `UUID` you generated, above.

- Add an entry in `/etc/fstab` e.g., for an `xfs`-formatted volume:

    `UUID=9e865845-f9a6-4995-aab5-d9ae952f7be0 /srv/rdiff xfs  noauto   0 0`

- Create a cron job that executes an rdiff-backup increment on your desired interval e.g., `/etc/cron.d/rdiff-backup` containing:

    `00 04  *  *  * root /usr/local/sbin/rdiff-backup.sh /etc/rdiff-backup.conf.d/rdiff-host.example.com.conf`

## Prerequisite Remote Configuration

- Install `rdiff-backup`:
  - RedHat: `dnf -y install rdiff-backup`
  - Debian: `apt-get install rdiff-backup`
- Edit `/root/.ssh/authorized_keys` and prepend the shared key with:
    `command="/usr/bin/rdiff-backup --server --restrict-read-only /"`

## Default Inclusions

```sh
/etc
/home
/usr/local
/var
```

### Default Exclusions

```sh
/
/var/lib/mysql
${MOUNTPOINT}
```

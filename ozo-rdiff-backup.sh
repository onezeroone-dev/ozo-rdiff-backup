#!/bin/bash
# Script Name: ozo-rdiff-backup.sh
# Version    : 1.0.1
# Description: This script automates the use of rdiff-backup to perform incremental backups of remote linux systems over SSH. It will mount a dedicated volume, generate an increment, perform increment maintenancce, and unmount the volume.
# Usage      : /usr/sbin/ozo-rdiff-backup.sh
# Author     : Andy Lievertz <alievertz@onezeroone.dev>
# Link       : https://github.com/onezeroone-dev/ozo-rdiff-backup/blob/main/README.md

# FUNCTIONS
function ozo-log {
    # Function   : ozo-log
    # Description: Logs output to the system log
    # Arguments  :
    #   LEVEL    : The log level. Allowed values are "err", "info", or "warning". Defaults to "info".
    #   MESSAGE  : The message to log.
    #   RHOSTFQDN: The fully-qualified domain name of the remote host.

    # Determine if LEVEL is null
    if [[ -z "${LEVEL}" ]]
    then
        # Level is null; set to "info"
        LEVEL="info"
    fi
    # Determine if RHOSTFQDN is not null
    if [[ -n "${RHOSTFQDN}" ]]
    then
        # RHOSTFQDN is not null; prepend MESSAGE with RHOSTFQDN
        MESSAGE="${RHOSTFQDN}: ${MESSAGE}"
    fi
    # Determine if MESSAGE is not null
    if [[ -n "${MESSAGE}" ]]
    then
        # Message is not null; log the MESSAGE with LEVEL
        logger -p local0.${LEVEL} -t "OZO Rdiff-Backup" "${MESSAGE}"
    fi
}

function ozo-mount-uuid {
    # Function   : ozo-mount-uuid
    # Description: Mounts the LUUID to the LMOUNTPOINT. Returns 0 (TRUE) if the mount is successful and 1 (FALSE) if the mount fails.

    # Control variable
    local RETURN=0
    # Determine if the mount command is available
    if which mount
    then
        # Determine if the rdiff-backup device is present in the system
        if ls /dev/disk/by-uuid/${LUUID} > /dev/null
        then
            # Device is present; determine if it is already mounted to LMOUNTPOINT
            if mount | grep "$(readlink -f /dev/disk/by-uuid/${LUUID}) on ${LMOUNTPOINT}" > /dev/null
            then
                # Device is present and mounted to LMOUNTPOINT; log
                LEVEL="err" MESSAGE="Device ${LUUID} is already mounted to ${LMOUNTPOINT}." ozo-log
                RETURN=1
            elif mount | grep "$(readlink -f /dev/disk/by-uuid/${LUUID})"
            then
                # Device is mounted but not to LMOUNTPOINT; log
                LEVEL="err" MESSAGE="Found ${LUUID} mounted to a directory other than ${LMOUNTPOINT}." ozo-log
                RETURN=1
            else
                # Device is present but not mounted; check if mountpoint exists
                if [[ -d "${LMOUNTPOINT}" ]]
                then
                    # Mountpoint exists; attempt to mount
                    if mount UUID=${LUUID} "${LMOUNTPOINT}"
                    then
                        # Mount succeeded; attempt to create backup and restore directories
                        if mkdir -p "${LMOUNTPOINT}/${LBACKUP_DIRNAME}" "${LMOUNTPOINT}/${LRESTORE_DIRNAME}"
                        then
                            # Created backup and restore directories
                            LEVEL="info" MESSAGE="Created ${LMOUNTPOINT}/${LBACKUP_DIRNAME} and ${LMOUNTPOINT}/${LRESTORE_DIRNAME}." ozo-log
                        else
                            # Failed to create backup and restore directories
                            LEVEL="err" MESSAGE="Unable to create ${LMOUNTPOINT}/${LBACKUP_DIRNAME} and ${LMOUNTPOINT}/${LRESTORE_DIRNAME}." ozo-log
                            RETURN=1
                        fi
                    else
                        # Mount failed; log
                        LEVEL="err" MESSAGE="Unable to mount ${LUUID} to ${LMOUNTPOINT}." ozo-log
                        RETURN=1
                    fi
                else
                    # Mountpoint doesn't exist; log
                    LEVEL="err" MESSAGE="Mountpoint ${LMOUNTPOINT} does not exist." ozo-log
                    RETURN=1
                fi
            fi
        else
            # Missing LUUID
            LEVEL="err" MESSAGE="Could not find ${LUUID} on this system." ozo-log
            RETURN=1
        fi
    else
        # Missing mount command
        LEVEL="err" MESSAGE="Missing 'mount' command" ozo-log
        RETURN=1
    fi
    # Return
    return ${RETURN}
}

function ozo-umount-uuid {
    # Function   : ozo-umount-uuid
    # Description: Unmounts UUID from LMOUNTPOINT. Returns 0 (TRUE) if the umount is sucessful and 1 (FALSE) if it fails.

    # Control variable
    local RETURN=0
    # Determine if the LUUID is mounted to the volume
    if mount | grep $(readlink -f /dev/disk/by-uuid/${LUUID}) | grep ${LMOUNTPOINT} > /dev/null
    then
        # LUUID is mounted to LMOUNTPOINT; attempt to unmount
        if ! umount ${LMOUNTPOINT}
        then
            # umount failed; log
            LEVEL="err" MESSAGE="Could not unmount ${LMOUNTPOINT} (is it busy?)" ozo-log
            RETURN=1
        fi
    else
        # Volume is already unmounted; log
        LEVEL="warning" MESSAGE="Volume ${LUUID} was not found mounted to ${LMOUNTPOINT}." ozo-log
    fi
    # Return
    return ${RETURN}
}

function ozo-fsck-uuid {
    # Function   : ozo-fsck-uuid
    # Description: Checks if it's fsck day and if yes, performs an fsck of the Rdiff-Backup volume. Returns 0 (TRUE) if it's not fsck day OR if it is and it's successful and 1 (FALSE) if it's fsck day but fails.

    # Control variable
    local RETURN=0
    # Determine if today is fsck day
    if [[ "$( date +%u )" == "${LFSCK_DAY}" ]]
    then
        # Today is fsck day; make sure the volume is unmounted
        if ozo-umount-uuid
        then
            # Volume is unmounted; determine if fsck fails
            if ! /sbin/fsck UUID=${LUUID}
            then
                # fsck failed
                RETURN=1
            fi
        else
            # Volume did not unmount
            LEVEL="err" MESSAGE="Volume ${LUUID} is not unmounted; unable to fsck." ozo-log
            RETURN=1
        fi
    fi
    # Return
    return ${RETURN}
}

function ozo-validate-configuration {
    # Function   : ozo-validate-configuration
    # Description: Performs a series of checks against the script configuration. Returns 0 (TRUE) if all checks pass and 1 (FALSE) if any check fails.

    # Control variable
    local RETURN=0
    # Iterate through the user-defined variables
    for USERDEFVAR in LBACKUP_DIRNAME LRESTORE_DIRNAME RDEF_INCLUDES RDEF_EXCLUDES LFSCK_DAY
    do
        # Determine if the variable is not set
        if [[ -z "${!USERDEFVAR}" ]]
        then
            # Variable is not set
            LEVEL="err" MESSAGE="User-defined variable ${USERDEFVAR} is not set." ozo-log
            RETURN=1
        fi
    done
    # Determine if the number of job configuration files is less than one
    if [[ "$(ls ${LCONF_DIR})" < "1" ]]
    then
        # Number of job configuration files is less than one
        LEVEL="err" MESSAGE="No job configuration files found in ${LCONF_DIR}." ozo-log
        RETURN=1
    fi
    # Determine if that the device is present and mounted
    if ozo-mount-uuid
    then
        # Device is present and mounted; determine if it cannot be unmounted
        if ! ozo-umount-uuid
        then
            # Device could not be unmounted
            RETURN=1
        fi
    else
        RETURN=1
    fi
    # Determine if rdiff-backup is not installed
    if ! which rdiff-backup
    then
        # rdiff-backup is not installed
        LEVEL="err" MESSAGE="Rdiff-Backup System is missing rdiff-backup". ozo-log
        RETURN=1
    fi
    # Return
    return ${RETURN}
}

function ozo-validate-job {
    # Function   : ozo-validate-job
    # Description: Performs a series of checks against the job configuration. Returns 0 (TRUE) if all checks pass and 1 (FALSE) if any check fails.

    # Control variable
    local RETURN=0
    # Iterate through the user-defined variables
    for USERDEFVAR in RHOSTUSER RHOSTFQDN RAGE
    do
        # Determine if the variable is not set
        if [[ -z "${!USERDEFVAR}" ]]
        then
            # Variable is not set
            LEVEL="err" MESSAGE="User-defined variable ${USERDEFVAR} is not set." ozo-log
            RETURN=1
        fi
    done
    # Determine if RSSHPORT is not set
    if [[ -z "${RSSHPORT}" ]]
    then
        # RSSHPORT is not set; set it to 22
        RSSHPORT=22
    fi
    # Determine if RHOST_INCLUDES is not null
    if [[ -n "${RHOST_INCLUDES}" ]]
    then
        # RHOST_INCLUDES is not null; concatenate with RDEF_INCLUDES
        JOB_INCLUDES="${RDEF_INCLUDES},${RHOST_INCLUDES}"
    else
        # RHOST_INCLUDES is null; set JOB_INCLUDES to RDEF_INCLUDES
        JOB_INCLUDES="${RDEF_INCLUDES}"
    fi
    # Determine of RHOST_EXCLUDES is not null
    if [[ -n "${RHOST_EXCLUDES}" ]]
    then
        # RHOST_EXCLUDES is not null; concatenate with RDEF_EXCLUDES
        JOB_EXCLUDES="${RDEF_EXCLUDES},${RHOST_EXCLUDES}"
    else
        # RHOST_EXCLUDES is null; set JOB_EXCLUDES to RDEF_EXCLUDES
        JOB_EXCLUDES="${RDEF_EXCLUDES}"
    fi
    # Parse comma-separated list into rdiff-backup include/exclude flags
    JOB_INCLUDES="${JOB_INCLUDES//,/ --include }"
    JOB_EXCLUDES="${JOB_EXCLUDES//,/ --exclude }"
    # Set directory for storing increments for this job
    RHOSTFQDN_INCREMENTS_DIR="${LMOUNTPOINT}/${LBACKUP_DIRNAME}/${RHOSTFQDN}"
    # Determine if creating job directory failed
    if ! mkdir -p ${RHOSTFQDN_INCREMENTS_DIR}
    then
        # Creating job directory failed
        LEVEL="err" MESSAGE="Unable to create ${RHOSTFQDN_INCREMENTS_DIR} to store increments for ${RHOSTFQDN}." ozo-log
        RETURN=1
    fi
    # Determine if the SSH client binary exists
    if which ssh
    then
        # SSH client binary exists; determine if SSH with keys is possible
        if ssh -p ${RSSHPORT} -o BatchMode=yes ${RHOSTUSER}@${RHOSTFQDN} true
        then
            # SSH with keys is possible; Determine if remote system does not have rdiff-backup
            if ! ssh -p ${RSSHPORT} ${RHOSTUSER}@${RHOSTFQDN} which rdiff-backup
            then
                # Remote system does not have rdiff-backup
                LEVEL="err" MESSAGE="Remote host ${RHOSTFQDN} is missing rdiff-backup." ozo-log
                RETURN=1
            fi
        else
            # SSH with keys is not possible
            LEVEL="err" MESSAGE="Unable to SSH to ${RHOSTFQDN} with keys." ozo-log
            RETURN=1
        fi
    else
        # SSH client binary does not exist
        LEVEL="err" MESSAGE="Local system is missing SSH." ozo-log
        RETURN=1
    fi
    # Return
    return ${RETURN}
}

function ozo-rdiff-backup {
    # Function   : ozo-rdiff-backup
    # Description: Performs the configured rdiff-backup for a remote host. Returns 0 (TRUE) if the job is successful and 1 (FALSE) if there are any errors.

    # Control variable
    local RETURN=0
    # Log an operation start message
    LEVEL="info" MESSAGE="Starting Rdiff-Backup job." ozo-log
    # Determine if the rdiff-backup operation is successful
    if rdiff-backup -v 0 --remote-schema "ssh -C -p ${RSSHPORT} {h} rdiff-backup server --restrict-mode read-only" backup --create-full-path --include ${JOB_INCLUDES} --exclude ${JOB_EXCLUDES} --exclude-if-present ${LMOUNTPOINT} --exclude-device-files --exclude-fifos ${RHOSTUSER}@${RHOSTFQDN}::/ ${RHOSTFQDN_INCREMENTS_DIR}
    then
        # rdiff-backup succeeded; log
        LEVEL="info" MESSAGE="Rdiff-Backup job finished with success." ozo-log
    else
        # rdiff-backup failed; log
        LEVEL="err" MESSAGE="Rdiff-Backup job failed." ozo-log
        RETURN=1
    fi
    # Return
    return ${RETURN}
}

function ozo-rdiff-maintenance {
    # Function   : ozo-rdiff-maintenance
    # Description: Performs maintenance on an rdiff-backup increment set. Returns 0 (TRUE) if maintenance is successful and 1 (FALSE) if it fails.

    # Control variable
    local RETURN=0
    # Log a maintenance start message
    LEVEL="info" MESSAGE="Performing maintenance on increments for ${RHOSTFQDN}." ozo-log
    # Determine if there are any increments older than RAGE
    if [[ "$(rdiff-backup list increments ${RHOSTFQDN_INCREMENTS_DIR} | head -n -1 | tail -n -1 | wc -l)" > "${RAGE}" ]]
    then
        # There are increments older than RAGE; determine if removing increments is successful
        if rdiff-backup remove increments --force --older-than ${RAGE}D ${RHOSTFQDN_INCREMENTS_DIR}
        then
            # Removing increments is successful
            LEVEL="info" MESSAGE="Successfully removed increments older than ${RAGE} days for ${RHOSTFQDN}." ozo-log
        else
            # Removing increments is not successful
            LEVEL="err" MESSAGE="Unable to remove increments older than ${RAGE} days for ${RHOSTFQDN}." ozo-log
            RETURN=1
        fi
    else
        # There are no increments older than RAGE
        LEVEL="warning" MESSAGE="Found fewer than ${RAGE} increments in ${RHOSTFQDN_INCREMENTS_DIR}, skipping maintenance". ozo-log
    fi
    # Return
    return ${RETURN}
}

function ozo-program-loop {
    # Function   : ozo-program-loop
    # Description: Validates the script configuration, validates and runs jobs, performs increments and filesystem maintenance. Returns 0 (TRUE) if the configuration validates and all jobs run and 1 (FALSE) if the configuration does not validate or any job fails.

    # Control variable
    local RETURN=0
    # Determine if the configuration file exists and is readable
    if [[ -f "${CONFIGURATION}" ]]
    then
        # Configuration file exists and is readable; source
        source "${CONFIGURATION}"
        # Determine if the configuration validates
        if ozo-validate-configuration
        then
            # Configuration validates; Determine if the LUUID mounts
            if ozo-mount-uuid
            then
                # LUUID is mounted, iterate through the jobs
                for CONF in $(ls ${LCONF_DIR}/*conf)
                do
                    # Unset user-defined variables
                    unset RHOSTUSER RHOSTFQDN RSSHPORT RHOST_INCLUDES RHOST_EXCLUDES
                    # Source the job configuration
                    source ${CONF}
                    # Determine if the job validates
                    if ozo-validate-job
                    then
                        # Job validates; determine if the backup is successful
                        if ozo-rdiff-backup
                        then
                            # Backup is successful; Determine if increment maintenance is not successful
                            if ! ozo-rdiff-maintenance
                            then
                                # Increment maintenance failed
                                RETURN=1
                            fi
                        else
                            # Backup failed
                            RETURN=1
                        fi
                    else
                        # Job did not validate
                        RETURN=1
                    fi
                done
                # All jobs processed; determine if LUUID is unmounted
                if ozo-umount-uuid
                then
                    # UUID unmounted; determine if fsck fails
                    if ! ozo-fsck-uuid
                    then
                        # fsck failed
                        RETURN=1
                    fi
                else
                    # umount UUID failed
                    RETURN=1
                fi
            else
                # mount UUID failed
                RETURN=1
            fi
        else
            # Configuration validation failed
            RETURN=1
        fi
    else
        # Configuraiton file does not exist or is not readable
        LEVEL="err" MESSAGE="Configuration file ${CONFIGURATION} does not exist or is not readable." ozo-log
    fi
    # Return
    return ${RETURN}
}

# MAIN
# Control variable
EXIT=0
# Set variables
LCONF_DIR="/etc/ozo-rdiff-backup.conf.d"
LMOUNTPOINT="/srv/ozo-rdiff"
CONFIGURATION="/etc/ozo-rdiff-backup.conf"
# Log a process start message
LEVEL="info" MESSAGE="Rdiff-Backup process starting." ozo-log
# Determine if the process finished with success
if ozo-program-loop > /dev/null 2>&1
then
    # Process finished with success; log
    LEVEL="info" MESSAGE="Rdiff-Backup finished with success." ozo-log
else
    # Process failed; unset variables
    unset RHOSTUSER RHOSTFQDN RSSHPORT RHOST_INCLUDES RHOST_EXCLUDES
    # Log
    LEVEL="err" MESSAGE="Rdiff-Backup finished with errors." ozo-log
    EXIT=1
fi
# Log a process end message
LEVEL="info" MESSAGE="Rdiff-Backup process finished." ozo-log
# Exit
exit ${EXIT}

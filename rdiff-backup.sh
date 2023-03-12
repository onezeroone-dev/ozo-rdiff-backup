#!/bin/bash

# FUNCTIONS
function ozo-log {
  ### Logs output to the system log
  if [[ -z "${LEVEL}" ]]
  then
    LEVEL="info"
  fi
  if [[ -n "${RHOSTFQDN}" ]]
  then
    MESSAGE="${RHOSTFQDN}: ${MESSAGE}"
  fi
  if [[ -n "${MESSAGE}" ]]
  then
    logger -p local0.${LEVEL} -t "OZO Rdiff-Backup" "${MESSAGE}"
  fi
}

function ozo-mount-uuid {
  ### Mounts the LUUID to the LMOUNTPOINT
  ### Returns 0 (TRUE) if the mount is successful and 1 (FALSE) if the mount fails
  local RETURN=0
  # check that the mount command is available
  if which mount
  then
    # check if our device is present in the system
    if ls /dev/disk/by-uuid/${LUUID} > /dev/null
    then
      # device is present; check if it is already mounted to LMOUNTPOINT
      if mount | grep "$(readlink -f /dev/disk/by-uuid/${LUUID}) on ${LMOUNTPOINT}" > /dev/null
      then
        # device is present and mounted to LMOUNTPOINT; log
        LEVEL="err" MESSAGE="Device ${LUUID} is already mounted to ${LMOUNTPOINT}." ozo-log
        RETURN=1
      elif mount | grep "$(readlink -f /dev/disk/by-uuid/${LUUID})"
        # device is mounted but not to LMOUNTPOINT; log
        LEVEL="err" MESSAGE="Found ${LUUID} mounted to a directory other than ${LMOUNTPOINT}." ozo-log
        RETURN=1
      else
        # our device is present but not mounted; check if mountpoint exists
        if [[ -d "${LMOUNTPOINT}" ]]
        then
          # mountpoint exists; attempt to mount
          if mount ${LUUID} ${LMOUNTPOINT}
          then
            # mount succeeded; attempt to create backup and restore directories
            if mkdir -p "${LMOUNTPOINT}/${LBACKUP_DIRNAME}","${LMOUNTPOINT}/${LRESTORE_DIRNAME}"
            then
              # created backup and restore directories
              LEVEL="info" MESSAGE="Created ${LMOUNTPOINT}/${LBACKUP_DIRNAME} and ${LMOUNTPOINT}/${LRESTORE_DIRNAME}." ozo-log
            else
              # failed to create backup and restore directories
              LEVEL="err" MESSAGE="Unable to create ${LMOUNTPOINT}/${LBACKUP_DIRNAME} and ${LMOUNTPOINT}/${LRESTORE_DIRNAME}." ozo-log
              RETURN=1
            fi
          else
            # mount failed; log
            LEVEL="err" MESSAGE="Unable to mount ${LUUID} to ${LMOUNTPOINT}." ozo-log
            RETURN=1
          fi
        else
          # mountpoint doesn't exist; log
          LEVEL="err" MESSAGE="Mountpoint ${LMOUNTPOINT} does not exist." ozo-log
          RETURN=1
        fi
      fi
    else
      # missing LUUID
      LEVEL="err" MESSAGE="Could not find ${LUUID} on this system." ozo-log
      RETURN=1
    fi
  else
    # missing mount command
    LEVEL="err" MESSAGE="Missing 'mount' command" ozo-log
    RETURN=1
  fi
  return ${RETURN}
}

function ozo-umount-uuid {
  ### Unmounts UUID from LMOUNTPOINT
  ### Returns 0 (TRUE) if the umount is sucessful and 1 (FALSE) if it fails
  local RETURN=0
  # check if the UUID is mounted to the volume
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
    # volume is already unmounted; log
    LEVEL="warning" MESSAGE="Volume ${LUUID} was not found mounted to ${LMOUNTPOINT}." ozo-log
  fi
  return ${RETURN}
}

function ozo-fsck-uuid {
  ### Performs an fsck of the Rdiff-Backup volume
  ### Returns 0 (TRUE) if successful and 1 (FALSE) if not
  local RETURN=0
  if ozo-umount-uuid
  then
    if ! /sbin/fsck UUID=${LUUID}
    then
      RETURN=1
    fi
  else
    LEVEL="err" MESSAGE="Volume ${LUUID} cannot be unmounted; unable to fsck." ozo-log
  fi
  return ${RETURN}
}

function ozo-validate-configuration {
  ### Performs a series of checks against the script configuration
  ### Returns 0 (TRUE) if all checks pass and 1 (FALSE) if any check fails
  local RETURN=0
  # check that all user-defined variables are set
  for USERDEFVAR in LCONF_DIR LUUID LMOUNTPOINT LBACKUP_DIRNAME LRESTORE_DIRNAME RDEF_INCLUDES RDEF_EXCLUDES LFSCK_DAY
  do
    if [[ -z "${!USERDEFVAR}" ]]
    then
      RETURN=1
      LEVEL="err" MESSAGE="User-defined variable ${USERDEFVAR} is not set." ozo-log
    fi
  done
  # check that at least one job configuration file has been specified
  if [[ $(ls ${LCONF_DIR}) < 1 ]]
  then
    LEVEL="err" MESSAGE="No job configuration files found in ${LCONF_DIR}." ozo-log
    RETURN=1
  fi
  # check that the device is present and mountable
  if ozo-mount-uuid
  then
    # device is present and mounting was successful; unmount
    if ! ozo-umount-uuid
    then
      # device could not be unmounted
      RETURN=1
  else
    RETURN=1
  fi
  # check that the ssh binary exists
  if which ssh
  then
    # check that SSH with keys is possible
    if ssh -p ${RSSHPORT} -o BatchMode=yes ${RHOSTUSER}@${RHOSTFQDN} true
    then
      # check that the remote system has zfs
      if ! ssh -p ${RSSHPORT} ${RUSER}@${RHOSTFQDN} which rdiff-backup
      then
        LEVEL="err" MESSAGE="Remote host ${RHOSTFQDN} is missing Rdiff-backup." ozo-log
        RETURN=1
      fi
    else
      RETURN=1
      LEVEL="err" MESSAGE="Unable to SSH to ${RHOSTFQDN} with keys." ozo-log
    fi  
  else
    LEVEL="err" MESSAGE="Local system is missing SSH." ozo-log
    RETURN=1
  fi
  return ${RETURN}
}

function ozo-validate-job {
  ### Performs a series of checks against the job configuration
  ### Returns 0 (TRUE) if all checks pass and 1 (FALSE) if any check fails
  local RETURN=0
  # check that all user-defined variables are set
  for USERDEFVAR in RHOSTUSER RHOSTFQDN RAGE
  do
    if [[ -z "${!USERDEFVAR}" ]]
    then
      LEVEL="err" MESSAGE="User-defined variable ${USERDEFVAR} is not set." ozo-log
      RETURN=1
    fi
  done
  # if RSSHPORT is omitted, set it to 22 and hope for the best
  if [[ -z "${RSSHPORT}" ]]
  then
    RSSHPORT=22
  fi
  # job specific (derived) variables
  # create the "inclusions" string from $RDEF_INCLUDES and (if set) $RHOST_INCLUDES
  INCLUDES="--include ${RDEF_INCLUDES//,/ --include }"
  if [ -n "${RHOST_INCLUDES}" ]
  then
    INCLUDES="${INCLUDES} --include ${RHOST_INCLUDES//,/ --include }"
  fi
  # create the "exclusions" string from $RDEF_EXCLUDES and (if set) $RHOST_EXCLUDES
  EXCLUDES="--exclude ${RDEF_EXCLUDES//,/ --exclude }"
  if [ -n "${RHOST_EXCLUDES}" ]
  then
    EXCLUDES="${EXCLUDES} --exclude ${RHOST_EXCLUDES//,/ --exclude }"
  fi
  # exclude the rdiff volume mount point (this handles the case where the Remote System is the Rdiff-Backup System)
  EXCLUDES="${EXCLUDES},${LMOUNTPOINT}"
  # directory for storing increments for this job
  RHOSTFQDN_INCREMENTS_DIR="${LMOUNTPOINT}/${LBACKUP_DIRNAME}/${RHOSTFQDN}"
  # attempt to create job increments directory
  if ! mkdir -p ${RHOSTFQDN_INCREMENTS_DIR}
  then
    LEVEL="err" MESSAGE="Unable to create ${RHOSTFQDN_INCREMENTS_DIR} to store increments for ${RHOSTFQDN}." ozo-log
    RETURN=1
  fi
}

function ozo-rdiff-backup {
  ### Performs the configured rdiff-backup for a remote host
  ### Returns 0 (TRUE) if the job is successful and 1 (FALSE) if there are any errors
  local RETURN=0
  LEVEL="info" MESSAGE="Starting Rdiff-Backup job." ozo-log
  if $(/usr/bin/rdiff-backup --verbosity 0 --create-full-path --remote-schema "/usr/bin/ssh -p ${SSHPORT} -C  %s /usr/bin/rdiff-backup --server --restrict-read-only /" ${INCLUDES} ${EXCLUDES} root@${HOST}::/ ${RHOSTFQDN_INCREMENTS_DIR})
  then
    # rdiff-backup succeeded; log
    LEVEL="info" MESSAGE="Rdiff-Backup job finished with success." ozo-log
  else
    # rdiff-backup failed; log
    LEVEL="err" MESSAGE="Rdiff-Backup job failed." ozo-log
    RETURN=1
  fi   
}

function ozo-rdiff-maintenance {
  ### Performs maintenance on an rdiff-backup increment set
  ### Returns 0 (TRUE) if maintenance is successful and 1 (FALSE) if it fails
  local RETURN=0
  # attempt to remove old increments
  LEVEL="info" MESSAGE="Performing maintenance on increments for ${RHOSTFQDN}." ozo-log
  if /usr/bin/rdiff-backup --force --remove-older-than ${RAGE}D ${RHOSTFQDN_INCREMENTS_DIR}
  then
    LEVEL="info" MESSAGE="Successfully removed increments older than ${RAGE} days for ${RHOSTFQDN}." ozo-log
  else
    LEVEL="err" MESSAGE="Unable to remove increments older than ${RAGE} days for ${RHOSTFQDN}." ozo-log
    RETURN=1
  fi
  return ${RETURN}
}

function ozo-program-loop {
  ### Validates the script configuration
  ### Validates and runs jobs
  ### Performs increments maintenance
  ### Performs filesystem maintenance
  ### Returns 0 (TRUE) if the configuration validates and all jobs run and 1 (FALSE) if the configuration does not validate or any job fails
  local RETURN=0
  local CONFIGURATION="/etc/rdiff-backup.conf"
  # check if the configuration file exists and is readable
  if [[ -f "${CONFIGURATION}" ]]
  then
    # file is readable; source
    source "${CONFIGURATION}"
    # validate the configuration
    if ozo-validate-configuration
    then
      # configuration validates; mount UUID
      if ozo-mount-uuid
      then
        # UUID mounted, iterate through the jobs
        for JOB in $(ls "${LCONF_DIR}/*conf")
        do
          # validate the job
          if ozo-validate-job
          then
            # job validates; perform backup
            if ozo-rdiff-backup
            then
              # backup succeeded; perform increments maintenance
              if ! ozo-rdiff-maintenance
              then
                # increments maintenance failed
                RETURN=1
              fi
            else
              # backup failed
              RETURN=1
            fi
          else
            # job did not validate
            RETURN=1
          fi
        done
        # iteration complete; attempt to umount UUID
        if ozo-umount-uuid
        then
          # UUID unmounted; check if it's fsck day
          if [[ "$( date +%u )" == "${LFSCK_DAY}" ]]
          then
            # it's fsck day!; attempt to fsck
            if ! ozo-fsck-uuid
            then
              # fsck failed
              RETURN=1
            fi
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
      # configuration validation failed
      RETURN=1
    fi    
  else
    # configuraiton file does not exist or is not readable
    LEVEL="err" MESSAGE="Configuration file ${CONFIGURATION} does not exist or is not readable." ozo-log
  fi
  return ${RETURN}
}

# MAIN
LEVEL="info" MESSAGE="Rdiff-Backup starting." ozo-log
if ozo-program-loop
then
  # run was successful
  LEVEL="info" MESSAGE="Rdiff-Backup finished with success." ozo-log
else
  # run failed one or more jobs
  LEVEL="err" MESSAGE="Rdiff-Backup finished with errors." ozo-log
fi

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
      then
        # device is mounted but not to LMOUNTPOINT; log
        LEVEL="err" MESSAGE="Found ${LUUID} mounted to a directory other than ${LMOUNTPOINT}." ozo-log
        RETURN=1
      else
        # our device is present but not mounted; check if mountpoint exists
        if [[ -d "${LMOUNTPOINT}" ]]
        then
          # mountpoint exists; attempt to mount
          if mount UUID=${LUUID} "${LMOUNTPOINT}"
          then
            # mount succeeded; attempt to create backup and restore directories
            if mkdir -p "${LMOUNTPOINT}/${LBACKUP_DIRNAME}" "${LMOUNTPOINT}/${LRESTORE_DIRNAME}"
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
  ### Checks if it's fsck day and if yes, performs an fsck of the Rdiff-Backup volume
  ### Returns 0 (TRUE) if it's not fsck day OR if it is and it's successful and 1 (FALSE) if it's fsck day but fails
  local RETURN=0
  # check if it's fsck day
  if [[ "$( date +%u )" == "${LFSCK_DAY}" ]]
  then
    # its fsck day, make sure the volume is unmounted
    if ozo-umount-uuid
    then
      # volume is unmounted, attempt to fsck
      if ! /sbin/fsck UUID=${LUUID}
      then
        # fsck failed
        RETURN=1
      fi
    else
      # volume did not unmount
      LEVEL="err" MESSAGE="Volume ${LUUID} is not unmounted; unable to fsck." ozo-log
      RETURN=1
    fi
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
  if [[ "$(ls ${LCONF_DIR})" < "1" ]]
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
    fi
  else
    RETURN=1
  fi
  # check that rdiff-backup is installed
  if ! which rdiff-backup
  then
    LEVEL="err" MESSAGE="Rdiff-Backup System is missing rdiff-backup". ozo-log
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
  # concatenate RDEF_INCLUDES and (if set) RHOST_INCLUDES
  if [[ -n "${RHOST_INCLUDES}" ]]
  then
    JOB_INCLUDES="${RDEF_INCLUDES},${RHOST_INCLUDES}"
  else
    JOB_INCLUDES="${RDEF_INCLUDES}"
  fi
  # concatenate RDEF_EXCLUDES, LMOUNTPOINT and (if set) RHOST_EXCLUDES
  if [[ -n "${RHOST_EXCLUDES}" ]]
  then
    JOB_EXCLUDES="${RDEF_EXCLUDES},${RHOST_EXCLUDES}"
  else
    JOB_EXCLUDES="${RDEF_EXCLUDES}"
  fi
  # parse commas into rdiff-backup include/exclude flags
  JOB_INCLUDES="${JOB_INCLUDES//,/ --include }"
  JOB_EXCLUDES="${JOB_EXCLUDES//,/ --exclude }"
  # directory for storing increments for this job
  RHOSTFQDN_INCREMENTS_DIR="${LMOUNTPOINT}/${LBACKUP_DIRNAME}/${RHOSTFQDN}"
  # attempt to create job increments directory
  if ! mkdir -p ${RHOSTFQDN_INCREMENTS_DIR}
  then
    LEVEL="err" MESSAGE="Unable to create ${RHOSTFQDN_INCREMENTS_DIR} to store increments for ${RHOSTFQDN}." ozo-log
    RETURN=1
  fi
  # check that the ssh binary exists
  if which ssh
  then
    # check that SSH with keys is possible
    if ssh -p ${RSSHPORT} -o BatchMode=yes ${RHOSTUSER}@${RHOSTFQDN} true
    then
      # check that the remote system has rdiff-backup
      if ! ssh -p ${RSSHPORT} ${RHOSTUSER}@${RHOSTFQDN} which rdiff-backup
      then
        LEVEL="err" MESSAGE="Remote host ${RHOSTFQDN} is missing rdiff-backup." ozo-log
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

function ozo-rdiff-backup {
  ### Performs the configured rdiff-backup for a remote host
  ### Returns 0 (TRUE) if the job is successful and 1 (FALSE) if there are any errors
  local RETURN=0
  LEVEL="info" MESSAGE="Starting Rdiff-Backup job." ozo-log
  if rdiff-backup -v 0 --remote-schema "ssh -C -p ${RSSHPORT} {h} rdiff-backup server --restrict-mode read-only" backup --create-full-path --include ${JOB_INCLUDES} --exclude ${JOB_EXCLUDES} --exclude-if-present ${LMOUNTPOINT} --exclude-device-files --exclude-fifos ${RHOSTUSER}@${RHOSTFQDN}::/ ${RHOSTFQDN_INCREMENTS_DIR}
  then
    # rdiff-backup succeeded; log
    LEVEL="info" MESSAGE="Rdiff-Backup job finished with success." ozo-log
  else
    # rdiff-backup failed; log
    LEVEL="err" MESSAGE="Rdiff-Backup job failed." ozo-log
    RETURN=1
  fi   
  return ${RETURN}
}

function ozo-rdiff-maintenance {
  ### Performs maintenance on an rdiff-backup increment set
  ### Returns 0 (TRUE) if maintenance is successful and 1 (FALSE) if it fails
  local RETURN=0
  # attempt to remove old increments
  LEVEL="info" MESSAGE="Performing maintenance on increments for ${RHOSTFQDN}." ozo-log
  if [[ "$(rdiff-backup list increments ${RHOSTFQDN_INCREMENTS_DIR} | head -n -1 | tail -n -1 | wc -l)" > "${RAGE}" ]]
  then
    if rdiff-backup remove increments --force --older-than ${RAGE}D ${RHOSTFQDN_INCREMENTS_DIR}
    then
      LEVEL="info" MESSAGE="Successfully removed increments older than ${RAGE} days for ${RHOSTFQDN}." ozo-log
    else
      LEVEL="err" MESSAGE="Unable to remove increments older than ${RAGE} days for ${RHOSTFQDN}." ozo-log
      RETURN=1
    fi
  else
    LEVEL="warning" MESSAGE="Found fewer than ${RAGE} increments in ${RHOSTFQDN_INCREMENTS_DIR}, skipping maintenance". ozo-log
  fi
  return ${RETURN}
}

function ozo-program-loop {
  ### Validates the script configuration, validates and runs jobs, performs increments and filesystem maintenance
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
        for CONF in $(ls ${LCONF_DIR}/*conf)
        do
          unset RHOSTUSER RHOSTFQDN RSSHPORT RHOST_INCLUDES RHOST_EXCLUDES
          source ${CONF}
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
          # UUID unmounted; fsck
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
EXIT=0

LEVEL="info" MESSAGE="Rdiff-Backup starting." ozo-log
#if ozo-program-loop
if ozo-program-loop > /dev/null 2>&1
then
  # run was successful
  LEVEL="info" MESSAGE="Rdiff-Backup finished with success." ozo-log
else
  # run failed one or more jobs
  unset RHOSTUSER RHOSTFQDN RSSHPORT RHOST_INCLUDES RHOST_EXCLUDES
  LEVEL="err" MESSAGE="Rdiff-Backup finished with errors." ozo-log
  EXIT=1
fi

exit ${EXIT}

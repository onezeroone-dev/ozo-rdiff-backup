#!/bin/bash

# This script automates the use of rdiff-backup to perform incremental backups
# of remote linux systems over SSH. It will mount and unmount a dedicated
# volume for storing rdiff-backup increments.

# Place this script in /usr/local/sbin.  It expects a single command-line
# argument specifying the path to a job configuration file.

# Please visit https://onezeroone.dev/automating-rdiff-backup-with-bash for
# more information.

# === PREREQUISITE LOCAL SETUP ================================================
# ssh-copy-id -i root@[HOSTNAME]
# Create a directory for configuration files e.g., /etc/rdiff-backup.conf.d
# Create a configuration file for the remote host containing:
# 
# HOST: Fully qualified domain name for the remote linux host.
# AGE: How long to keep increments in days
# SSHPORT: SSH port to use to establish a connection to the remote host
# HOST_INCLUDES: Comma-separated list of host-specific directory inclusions
# HOST_EXCLUDES: Comma-separated list of host-specific directory exclusions
#
# For example, /etc/rdiff-backup/onezeroone.dev.conf:
#
# HOST="onezeroone.dev"
# AGE="180"
# SSHPORT="22"
# HOST_INCLUDES=""
# HOST_EXCLUDES=""
#
# Finally, create a cron job that executes an rdiff-backup increment on your
# desired interval e.g. /etc/cron.d/rdiff-backup containing:
#
# 00 04  *  *  * root /usr/local/sbin/rdiff-backup.sh /etc/rdiff-backup.conf.d/onezeroone.dev.conf

# === PREREQUISITE REMOTE SETUP ===============================================
# Install rdiff-backup:
# - RedHat/CentOS: yum install rdiff-backup
# - Debian/Ubuntu: apt-get install rdiff-backup
# Edit /root/.ssh/authorized_keys and prepend the shared key with:
# command="/usr/bin/rdiff-backup --server --restrict-read-only /"

# === USER DEFINABLE VARIABLES ================================================
# UUID of the formatted rdiff-backup volume for storing increments which can be
# determined by executing 'blkid' in a root shell.
UUID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# The mount point for the rdiff-backup volume
MOUNTPOINT="/srv/rdiff"
# Location for configuration files
CONF_DIR="/etc/rdiff-backup.conf.d"
# Default directories to include for all hosts
DEF_INCLUDES="/etc,/home,/root,/usr/local,/var"
# Default directories to exclude for all hosts
DEF_EXCLUDES="/,/var/lib/mysql"
# Day to run fsck, Sunday=0 through Saturday=6
FSCK_DAY=1

# === MAIN ====================================================================
# === DO NOT MODIFY ANYTHING BEYOND THIS POINT ================================
# =============================================================================

# Exclude the rdiff volume mount point
DEF_EXCLUDES="${DEF_EXCLUDES},${MOUNTPOINT}"

# Check that a configuration file was specified
if [ -n "${1}" ]
then
	# Configuration file exists; source it
	. ${1}
	# Check that the configuration file has HOST and AGE set
	if [ "x${HOST}" == "x" -o "x${AGE}" == "x" ]
	then
		echo ""
		echo "Configuration file ${1} does not contain values for HOST and/or AGE."
		echo ""
		exit 1
	#else
		# Configuration file has values for HOST and AGE
	fi
else
	# Configuration file was not specified
	echo "A configuration file was not specified. Usage:"
	echo ""
	echo "${0} /etc/rdiff-backup.conf.d/[HOSTNAME].conf"
	echo ""
	exit 1
fi

# check if our device is present in the system
if ls /dev/disk/by-uuid/${UUID} > /dev/null
then
	# device is present.
	# check if our device is already mounted 
	if ! /bin/mount | grep ${MOUNTPOINT} > /dev/null
	then
		# our device is not mounted
		# try to mount it
		if ! /bin/mount UUID=${UUID} ${MOUNTPOINT}
		then
			# our device did not mount 
			echo "failed to mount the destination device"
			exit 1
		#else
			# our device mounted properly
		fi
	#else
		# our device is already mounted
	fi
	# define and create the destination directory
	DESTINATION="${MOUNTPOINT}/backup"
	mkdir -p ${DESTINATION}
else
	# device is not present
	echo "destination device is not present"
	exit 1
fi

# create the "inclusions" string from $DEF_INCLUDES and $HOST_INCLUDES (if set)
INCLUDES="--include ${DEF_INCLUDES//,/ --include }"
if [ -n "${HOST_INCLUDES}" ]
then
	INCLUDES="${INCLUDES} --include ${HOST_INCLUDES//,/ --include }"
fi

# create the "exclusions" string from $DEF_EXCLUDES and $HOST_EXCLUDES (if set)
EXCLUDES="--exclude ${DEF_EXCLUDES//,/ --exclude }"
if [ -n "${HOST_EXCLUDES}" ]
then
	EXCLUDES="${EXCLUDES} --exclude ${HOST_EXCLUDES//,/ --exclude }"
fi

# perform the rdiff-backup
INCREMENTS_DIR="${DESTINATION}/${HOST}"
mkdir -p ${INCREMENTS_DIR}
if $( /usr/bin/rdiff-backup --verbosity 0 --create-full-path --remote-schema "/usr/bin/ssh -p ${SSHPORT} -C  %s /usr/bin/rdiff-backup --server --restrict-read-only /" ${INCLUDES} ${EXCLUDES} root@${HOST}::/ ${INCREMENTS_DIR} )
then
	# rdiff-backup was successful
	# remove old increments
	if ! /usr/bin/rdiff-backup --force --remove-older-than ${AGE}D ${INCREMENTS_DIR}
	then
		echo "unable to remove old increments"
	#else
		# the increments were removed successfully
	fi
else
	# rdiff-backup was not successful
	echo "rdiff did not complete successfully"
fi

# unmount the destination
if ! umount ${MOUNTPOINT}
then
	# destination did not unmount
	echo "failed to unmount destination device. is it busy?"
	exit 1
else
	# destination unmounted
	# if Monday (1), run an fsck
	if [ $( date +%u ) == ${FSCK_DAY} ]
	then
		/sbin/fsck UUID=${UUID}
	fi
fi

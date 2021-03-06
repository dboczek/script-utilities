#!/usr/bin/env bash

#																																																											  
# Copyright (c) 2012 CodePill Sp. z o.o.
# Author: Krzysztof Ksiezyk <kksiezyk@gmail.com>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#	 notice, this list of conditions and the following disclaimer.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

##########################################################
# TO DO
##########################################################
# - check if network filesystems are installed
# - report errors in email in text format
##########################################################

##########################################################
# init
##########################################################
TIME_START=`date "+%Y-%m-%d %H:%M:%S"`
ERROR_MSG=""
HOST=`hostname`
DATE=`date "+%Y_%m_%d"`
source `dirname $0`/backup.conf

# system
CMD_UNAME=`/usr/bin/which uname`
RES=`$CMD_UNAME -s | tr '[:upper:]' '[:lower:]'`
if [ "$RES" = "freebsd" ]; then
	OS="FREEBSD"
elif [ "$RES" = "linux" ]; then
	if [ -f /etc/redhat-release ]; then
		OS="REDHAT"
	elif [ -f /etc/debian_version ]; then
		OS="DEBIAN"
	else
		echo "Unknown Linux OS"
		exit
	fi
else
	echo "Unknown OS"
	exit
fi

# bin locations
if [ ${ENABLE_FS} -eq 1 ]; then
	CMD_RSYNC=`/usr/bin/which rsync 2>/dev/null`
	if [ $? -ne 0 ]; then
		echo "Rsync is necessary when ENABLE_FS is set"
		exit
	fi 
fi
CMD_TAR=`/usr/bin/which tar 2>/dev/null`
if [ $? -ne 0 ]; then echo "TAR command is necessary..."; exit; fi
CMD_MKDIR=`/usr/bin/which mkdir 2>/dev/null`
if [ $? -ne 0 ]; then echo "mkdir command is necessary..."; exit; fi
CMD_RM=`/usr/bin/which rm 2>/dev/null`
if [ $? -ne 0 ]; then echo "rm command is necessary..."; exit; fi
if [ ${ENABLE_MYSQL} -eq 1 ]; then
	CMD_MYSQL=`/usr/bin/which mysql 2>/dev/null`
	if [ $? -ne 0 ]; then echo "mysql command is necessary when ENABLE_MYSQL is set"; exit; fi
	CMD_MYSQLDUMP=`/usr/bin/which mysqldump 2>/dev/null`
	if [ $? -ne 0 ]; then echo "mysqldump command is necessary when ENABLE_MYSQL is set"; exit; fi
fi
CMD_UMOUNT=`/usr/bin/which umount 2>/dev/null`
if [ $? -ne 0 ]; then echo "umount command is necessary..."; exit; fi
CMD_MAIL=`/usr/bin/which mail 2>/dev/null`

if [ $OS = "FREEBSD" ]; then
	CMD_MOUNT_NFS=`/usr/bin/which mount_nfs 2>/dev/null`
	CMD_MOUNT_SMB=`/usr/bin/which mount_smbfs 2>/dev/null`
	CMD_PKG=`/usr/bin/which pkg_info 2>/dev/null`
elif [ $OS = "REDHAT" ]; then
	CMD_MOUNT=`/usr/bin/which mount 2>/dev/null`
	CMD_MOUNT_SMB=`/usr/bin/which mount.cifs 2>/dev/null`
	CMD_PKG=`/usr/bin/which yum 2>/dev/null`
elif [ $OS = "DEBIAN" ]; then
	CMD_MOUNT=`/usr/bin/which mount 2>/dev/null`
	CMD_MOUNT_SMB=`/usr/bin/which mount.cifs 2>/dev/null`
	CMD_PKG=`/usr/bin/which dpkg 2>/dev/null`
fi

##########################################################

##########################################################
# creating directories
##########################################################
if [ ! -d $LOCAL_MNT ]; then
	$CMD_MKDIR -p ${LOCAL_MNT}
fi

if [ ${ENABLE_MYSQL} -eq 1 ]; then
	$CMD_MKDIR -p ${BACKUP_DIR}/mysql
	$CMD_RM ${BACKUP_DIR}/mysql/*.sql.gz 2>/dev/null
fi

if [ ${ENABLE_SVN} -eq 1 ]; then
	$CMD_MKDIR -p ${BACKUP_DIR}/svn
	$CMD_RM ${BACKUP_DIR}/svn/*.tgz 2>/dev/null
fi

if [ ${ENABLE_GIT} -eq 1 ]; then
	$CMD_MKDIR -p ${BACKUP_DIR}/git
	$CMD_RM ${BACKUP_DIR}/git/*.tgz 2>/dev/null
fi

if [ ${ENABLE_FILES} -eq 1 ]; then
	$CMD_MKDIR -p ${BACKUP_DIR}/files
	$CMD_RM ${BACKUP_DIR}/files/*gz 2>/dev/null
fi

##########################################################
# mounting NFS share
##########################################################
if [ $OS = "FREEBSD" ]; then
	if [ "${REMOTE_FS_TYPE_NORMAL}" = "nfs" ]; then
		$CMD_MOUNT_NFS -o nolockd ${BACKUP_HOST}:/backup/${HOST} $LOCAL_MNT
	elif [ "${REMOTE_FS_TYPE_NORMAL}" = "nfs4" ]; then
		$CMD_MOUNT_NFS -o nfsv4,suid ${BACKUP_HOST}:/backup/${HOST} $LOCAL_MNT
	elif [ "${REMOTE_FS_TYPE_NORMAL}" = "cifs" ]; then
		$CMD_MOUNT_SMB -I ${BACKUP_HOST} -N //${FS_USER}@${BACKUP_HOST}/backup.${HOST}/ $LOCAL_MNT
	fi
else
	if [ "${REMOTE_FS_TYPE_NORMAL}" = "nfs" ]; then
		$CMD_MOUNT -t ${REMOTE_FS_TYPE_NORMAL} -o nolock ${BACKUP_HOST}:/backup/${HOST} $LOCAL_MNT
	elif [ "${REMOTE_FS_TYPE_NORMAL}" = "nfs4" ]; then
		$CMD_MOUNT -t ${REMOTE_FS_TYPE_NORMAL} -o suid ${BACKUP_HOST}:/backup/${HOST} $LOCAL_MNT
	elif [ "${REMOTE_FS_TYPE_NORMAL}" = "cifs" ]; then
		$CMD_MOUNT_SMB //${BACKUP_HOST}/backup.${HOST}/ $LOCAL_MNT -o user=${FS_USER},password=${FS_PASS},directio
	fi
fi

RES=$?
if [ $RES -ne 0 ]; then
	echo "Error [${RES}] mounting share"
	ERROR_MSG="${ERROR_MSG}Error [${RES}] mounting share\n"
	ENABLE_MYSQL=0
	ENABLE_SVN=0
	ENABLE_GIT=0
	ENABLE_FILES=0
fi

##########################################################
# databases backup
##########################################################
if [ ${ENABLE_MYSQL} -eq 1 ]; then
	echo "# Backuping databases #"

	DBS=`$CMD_MYSQL -h $MYSQL_HOST --silent -u $MYSQL_USER -p$MYSQL_PASS -e "SHOW DATABASES"`
	RES=$?
	if [ $RES -ne 0 ]; then
		echo "Error fetching db list"
		ERROR_MSG="${ERROR_MSG}Error [${RES}] fetching db list\n"
	else
		TIME_DB_DUMP_START=`date +%s`
		for DB in ${DBS}; do
			 if [ "${DB}" == "" ]; then continue; fi;
			 if [ "${DB}" == "information_schema" ]; then continue; fi;
			 echo -en "\t${DB} - "
			 $CMD_MYSQLDUMP -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS -eC ${DB} | gzip >${BACKUP_DIR}/mysql/${DATE}_${DB}.sql.gz
			 RES=$?
			 if [ $RES -ne 0 ]; then
				echo "ERR!!!"
				  	ERROR_MSG="${ERROR_MSG}Error [${RES}] backuping database ${DB}\n"
			 else
				  echo "OK"
			 fi
		done
		TIME_DB_DUMP_END=`date +%s`
		echo "# Copying databases to backup host #"
		$CMD_MKDIR -p $LOCAL_MNT/mysql/${DATE}
		RES=$?
		if [ $RES -ne 0 ]; then
			 ERROR_MSG="${ERROR_MSG}Error [${RES}] creating directory for dumps on backup server\n"
		else
			TIME_DB_CP_START=`date +%s`
			cp -r ${BACKUP_DIR}/mysql/*.sql.gz $LOCAL_MNT/mysql/${DATE}
			RES=$?
			if [ $RES -ne 0 ]; then
				 ERROR_MSG="${ERROR_MSG}Error [${RES}] copying db dumps to backup server\n"
			fi
			TIME_DB_CP_END=`date +%s`
		fi
	fi
fi

##########################################################
# SVN
##########################################################
if [ ${ENABLE_SVN} -eq 1 ]; then
	echo "# Backuping SVN #"
	TIME_SVN_DUMP_START=`date +%s`
	cd ${SVN_ROOT}
	REPOS=`find . -mindepth 1 -maxdepth 1 -type d`
	for REPO in ${REPOS}; do
		REPO=`basename ${REPO}`
		echo -en "\t${REPO} - "
		$CMD_TAR -cpzf "${BACKUP_DIR}/svn/${DATE}_${REPO}.tgz" ${REPO}
		RES=$?
		if [ $RES -ne 0 ]; then
			echo "ERR!!!"
			ERROR_MSG="${ERROR_MSG}Error [${RES}] backuping SVN repository ${REPO}\n"
		else
			echo "OK"
		fi
	done;
	TIME_SVN_DUMP_END=`date +%s`
	echo "# Copying SVN repositories to backup host #"
	$CMD_MKDIR -p $LOCAL_MNT/svn/${DATE}
	RES=$?
	if [ $RES -ne 0 ]; then
		ERROR_MSG="${ERROR_MSG}Error [${RES}] creating directory for SVN repositories on backup server\n"
	else
		TIME_SVN_CP_START=`date +%s`
		cp -r ${BACKUP_DIR}/svn/*.tgz $LOCAL_MNT/svn/${DATE}
		RES=$?
		if [ $RES -ne 0 ]; then
			ERROR_MSG="${ERROR_MSG}Error [${RES}] copying SVN repositories to backup server\n"
		fi
		TIME_SVN_CP_END=`date +%s`
	fi
fi

##########################################################
# GIT
##########################################################
if [ ${ENABLE_GIT} -eq 1 ]; then
	echo "# Backuping GIT #"
	TIME_GIT_DUMP_START=`date +%s`
	cd ${GIT_ROOT}
	REPOS=`find . -mindepth 1 -maxdepth 1 -type d`
	for REPO in ${REPOS}; do
		REPO=`basename ${REPO}`
		echo -en "\t${REPO} - "
		$CMD_TAR -cpzf "${BACKUP_DIR}/git/${DATE}_${REPO}.tgz" ${REPO}
		RES=$?
		if [ $RES -ne 0 ]; then
			echo "ERR!!!"
			ERROR_MSG="${ERROR_MSG}Error [${RES}] backuping GIT repository ${REPO}\n"
		else
			echo "OK"
		fi
	done;
	TIME_GIT_DUMP_END=`date +%s`
	echo "# Copying GIT repositories to backup host #"
	$CMD_MKDIR -p $LOCAL_MNT/git/${DATE}
	RES=$?
	if [ $RES -ne 0 ]; then
		ERROR_MSG="${ERROR_MSG}Error [${RES}] creating directory for GIT repositories on backup server\n"
	else
		TIME_GIT_CP_START=`date +%s`
		cp -r ${BACKUP_DIR}/git/*.tgz $LOCAL_MNT/git/${DATE}
		RES=$?
		if [ $RES -ne 0 ]; then
			ERROR_MSG="${ERROR_MSG}Error [${RES}] copying GIT repositories to backup server\n"
		fi
		TIME_GIT_CP_END=`date +%s`
	fi
fi

##########################################################
# files
##########################################################
if [ ${ENABLE_FILES} -eq 1 ]; then
	echo "# Backuping files #"
	TIME_FILES_DUMP_START=`date +%s`
	$CMD_TAR -cpzf "${BACKUP_DIR}/files/${DATE}_files.tgz" ${FILES_INCLUDE} 2>/dev/null
	RES=$?
	if [ $RES -ne 0 ]; then
		ERROR_MSG="${ERROR_MSG}Error [${RES}] creating tar file\n"
	fi

	if [ $OS = "FREEBSD" ]; then
		$CMD_PKG | gzip >"${BACKUP_DIR}/files/${DATE}_packages.gz"
  	elif [ $OS = "REDHAT" ]; then
		$CMD_PKG list installed | gzip >"${BACKUP_DIR}/files/${DATE}_packages.gz"
	else
		$CMD_PKG -l | gzip >"${BACKUP_DIR}/files/${DATE}_packages.gz"
	fi

	RES=$?
	if [ $RES -ne 0 ]; then
		ERROR_MSG="${ERROR_MSG}Error [${RES}] fetching installed packages\n"
	fi
	TIME_FILES_DUMP_END=`date +%s`

	echo "# Sending files #"
	$CMD_MKDIR -p $LOCAL_MNT/files/${DATE}
	RES=$?
	if [ $RES -ne 0 ]; then
		ERROR_MSG="${ERROR_MSG}Error[${RES}] creating directory for files on backup server\n"
	else
		TIME_FILES_CP_START=`date +%s`
		cp -r ${BACKUP_DIR}/files/*gz $LOCAL_MNT/files/${DATE}
		RES=$?
		if [ $RES -ne 0 ]; then
			ERROR_MSG="${ERROR_MSG}Error [${RES}] copying files to backup server\n"
		fi
		TIME_FILES_CP_END=`date +%s`
	fi
fi

##########################################################
# cleanup
##########################################################
if [ ${ENABLE_MYSQL} -eq 1 ]; then
	$CMD_RM ${BACKUP_DIR}/mysql/*.sql.gz
fi

if [ ${ENABLE_SVN} -eq 1 ]; then
	$CMD_RM ${BACKUP_DIR}/svn/*.tgz
fi

if [ ${ENABLE_GIT} -eq 1 ]; then
	$CMD_RM ${BACKUP_DIR}/git/*.tgz
fi

if [ ${ENABLE_FILES} -eq 1 ]; then
	$CMD_RM ${BACKUP_DIR}/files/*gz
fi

##########################################################
# unmounting share
##########################################################
$CMD_UMOUNT $LOCAL_MNT
RES=$?
if [ $? -ne 0 ]; then
	echo "Error [${RES}] unmounting share"
	ERROR_MSG="${ERROR_MSG}Error [${RES}] unmounting share\n"
	ENABLE_FS=0
fi

##########################################################
# rsyncing filesystem
##########################################################
if [ ${ENABLE_FS} -eq 1 ]; then
	echo "# Rsyncing filesystem #"
	TIME_RSYNC_START=`date +%s`

	if [ $OS = "FREEBSD" ]; then
		if [ "${REMOTE_FS_TYPE_RSYNC}" = "nfs" ]; then
			$CMD_MOUNT_NFS -o nolock ${BACKUP_HOST}:/backup2/${HOST} $LOCAL_MNT
		elif [ "${REMOTE_FS_TYPE_RSYNC}" = "nfs4" ]; then
			$CMD_MOUNT_NFS -o nfsv4,suid ${BACKUP_HOST}:/backup2/${HOST} $LOCAL_MNT
		elif [ "${REMOTE_FS_TYPE_RSYNC}" = "cifs" ]; then
			$CMD_MOUNT_SMB -I ${BACKUP_HOST} -N //${FS_USER}@${BACKUP_HOST}/backup2.${HOST}/ $LOCAL_MNT
		fi
	else
		if [ "${REMOTE_FS_TYPE_RSYNC}" = "nfs" ]; then
			$CMD_MOUNT -t ${REMOTE_FS_TYPE_RSYNC} -o nolock ${BACKUP_HOST}:/backup2/${HOST} $LOCAL_MNT
		elif [ "${REMOTE_FS_TYPE_RSYNC}" = "nfs4" ]; then
			$CMD_MOUNT -t ${REMOTE_FS_TYPE_RSYNC} -o suid ${BACKUP_HOST}:/backup2/${HOST} $LOCAL_MNT
		elif [ "${REMOTE_FS_TYPE_RSYNC}" = "cifs" ]; then
			$CMD_MOUNT_SMB //${BACKUP_HOST}/backup2.${HOST}/ $LOCAL_MNT -o user=${FS_USER},password=${FS_PASS},directio
		fi
	fi

	RES=$?
	if [ $RES -ne 0 ]; then
		echo "Error [${RES}] mounting remote share"
		ERROR_MSG="${ERROR_MSG}Error [${RES}] mounting remote share\n"
	else
		$CMD_RSYNC -lrpogt --delete ${RSYNC_EXCLUDES} ${RSYNC_DIRS} $LOCAL_MNT
		RES=$?
		if [ $RES -ne 0 ] && [ $RES -ne 24 ]; then
			 echo "Error [${RES}] rsyncing files"
			 ERROR_MSG="${ERROR_MSG}Error [${RES}] rsyncing files\n"
		fi
		echo "# Creating BACKUP_COMPLETED file #"
		touch $LOCAL_MNT/BACKUP_COMPLETED
		$CMD_UMOUNT $LOCAL_MNT
		RES=$?
		if [ $RES -ne 0 ]; then
			echo "Error [${RES}] unmounting remote share"
			ERROR_MSG="${ERROR_MSG}Error [${RES}] unmounting remote share\n"
		fi
	fi
	TIME_RSYNC_END=`date +%s`
fi

##########################################################
# finishing
##########################################################
if [ "${ERROR_MSG}" == "" ]; then
	ERROR_IND=""
else
	ERROR_IND=" [ ERROR ]"
fi

##########################################################
# time calculations
##########################################################
TIME_END=`date "+%Y-%m-%d %H:%M:%S"`
TIME_MSG="\tSTART:\t${TIME_START}\n\tEND:\t${TIME_END}\n"
if [ ${ENABLE_MYSQL} -eq 1 ]; then
	T1=$((TIME_DB_DUMP_END-TIME_DB_DUMP_START))
	T2=$((TIME_DB_CP_END-TIME_DB_CP_START))
	TIME_MSG="${TIME_MSG}\tMYSQL:\tdmp:${T1} cp:${T2}\n"
fi
if [ ${ENABLE_SVN} -eq 1 ]; then
	T1=$((TIME_SVN_DUMP_END-TIME_SVN_DUMP_START))
	T2=$((TIME_SVN_CP_END-TIME_SVN_CP_START))
	TIME_MSG="${TIME_MSG}\tSVN:\tdmp:${T1} cp:${T2}\n"
fi
if [ ${ENABLE_GIT} -eq 1 ]; then
	T1=$((TIME_GIT_DUMP_END-TIME_GIT_DUMP_START))
	T2=$((TIME_GIT_CP_END-TIME_GIT_CP_START))
	TIME_MSG="${TIME_MSG}\tGIT:\tdmp:${T1} cp:${T2}\n"
fi
if [ ${ENABLE_FILES} -eq 1 ]; then
	T1=$((TIME_FILES_DUMP_END-TIME_FILES_DUMP_START))
	T2=$((TIME_FILES_CP_END-TIME_FILES_CP_START))
	TIME_MSG="${TIME_MSG}\tFILES:\tdmp:${T1} cp:${T2}\n"
fi
if [ ${ENABLE_FS} -eq 1 ]; then
	T1=$((TIME_RSYNC_END-TIME_RSYNC_START))
	TIME_MSG="${TIME_MSG}\tRSYNC:\t${T1}\n"
fi

##########################################################
# report
##########################################################
if [ "$CMD_MAIL" -a "$MAIL_TO" ]; then
	echo -e "Backup completed\nRemote filesystem: ${REMOTE_FS_TYPE_NORMAL} / ${REMOTE_FS_TYPE_RSYNC}\nTimes:\n${TIME_MSG}\n\n${ERROR_MSG}" | $CMD_MAIL -s "[ BACKUP ]${ERROR_IND} ${HOST}" ${MAIL_TO} 
fi
echo "# Backup completed #"

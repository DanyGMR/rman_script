#!/bin/bash

# Oracle Environment
# Set shell search paths
export ProgDir=/home/oracle/scripts
export START_SCRIPT=`date +%s`
export DOM=`date +%d`                          # Date of the Month e.g. 27
export DOW=`date +%u`                          # Date of the Month e.g. 27
. ~/.bash_profile
export DATECODE=`date +_%Y%m%d_%H%M`
CP=/bin/cp
export DATECODE=`date +_%Y%m%d_%H%M`
export DATECODE2=`date +%Y%m%d_%H%M`
export DATECODE1=`date +%Y%m%d%H%M`
export DSUBJ=`date +'%d/%B/%Y %A at %T'`
export RmanDir1=/backup1/rman/${DATECODE2}
export RmanDir2=/backup2/rman/${DATECODE2}
export RmanDir=/backup/rman
export RmanLogFile=/home/oracle/scripts/logs/hot_rman${DATECODE}.log
export EXEC_SCRIPT_TIME=$(date +"%Y%m%d%H%M")
export EXEC_SCRIPT_DATE=$(date +"%Y%m%d")
source ${ProgDir}/config.sh

rparallel=$1
if [ -n "$rparallel" ] ; then
rparallel=$1
else
rparallel=15
fi

rman target / log=$RmanLogFile append <<_EOS_
configure DEFAULT DEVICE TYPE TO DISK;
configure CHANNEL DEVICE TYPE DISK FORMAT '/backup/rman/aviv_%d_%D_%M_%Y_%s.bck';
#configure DEVICE TYPE DISK PARALLELISM 2 BACKUP TYPE TO COMPRESSED BACKUPSET;
configure DEVICE TYPE DISK PARALLELISM ${rparallel} BACKUP TYPE TO COMPRESSED BACKUPSET;
configure controlfile autobackup on;
configure CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/backup/rman/csfiles_%F';
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
exit
_EOS_


#!/bin/bash

# Oracle Environment
# Set shell search paths
SCRIPT_NAME=$(basename "$0")
LOCKFILE="/tmp/${SCRIPT_NAME}.lock"
PIDFILE="/tmp/${SCRIPT_NAME}.pid"
TEMPFILE="/tmp/${SCRIPT_NAME}.temp"
export ProgDir=/home/oracle/scripts
export LogDir=/home/oracle/scripts/logs
#START_SCRIPT=$(date +%s)
DOM=$(date +%d) # Date of the Month e.g. 27
DOW=$(date +%u) # Date of the Month e.g. 27
. /home/oracle/.bash_profile
#DATECODE=$(date +_%Y%m%d_%H%M)
CP=/usr/bin/cp
CAT=/usr/bin/cat
MV=/usr/bin/mv
RM=/usr/bin/rm
DATECODE=$(date +_%Y%m%d_%H%M%S)
DATECODE2=$(date +%Y%m%d_%H%M%S)
DATECODE1=$(date +%Y%m%d%H%M%S)
DSUBJ=$(date +'%d/%B/%Y %A at %T')
export RmanBaseDir1=/backup1/rman
export RmanBaseDir2=/backup2/rman
export RmanDir1=${RmanBaseDir1}/${DATECODE2}
export RmanDir2=${RmanBaseDir2}/${DATECODE2}
export RmanDir=/backup/rman
EXEC_SCRIPT_TIME=$(date +"%Y%m%d%H%M")
source ${ProgDir}/config.sh
rlvl=$1

###changes for only one LOG FILE
if [ -n "$rlvl" ] && [ "$rlvl" = "0" ]; then
        export Level=0
elif [ "$rlvl" = "1" ]; then
        export Level=1
elif [ "$rlvl" = "2" ]; then
        export Level=2
else
       if [ "$DOW" = "6" ]; then
                export Level=0
        elif [ "$DOW" = "z" ]; then
                export Level=2
        else
                export Level=1
        fi
fi

export RmanLogFile=/home/oracle/scripts/logs/hot_rman_lvl${Level}${DATECODE}.log
echo "$RmanLogFile"
###
# Check if the lock file exists

if [ -f "$LOCKFILE" ]; then
        if [ -s "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Script is already running. Exiting."
  exit 1
        else
         echo "Stale lock file found. Removing and continuing..."
    rm -f "$LOCKFILE" "$PIDFILE"
  fi
fi

# Create the lock file
echo $$ > "$PIDFILE"
touch "$LOCKFILE" 

# Function to remove the lock file on exit
cleanup() {
  rm -f "$LOCKFILE" "$PIDFILE" "$TEMPFILE"
}
#trap cleanup SIGTERM
trap cleanup EXIT

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> "${RmanLogFile}"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}


# Check PMON Process
check_pmon() {
    log "Checking PMON process for Oracle SID: $ORACLE_SID"
    if pgrep -f "ora_pmon_${ORACLE_SID}" > /dev/null; then
        echo "PMON process for ${ORACLE_SID} is running."
        log "PMON process for ${ORACLE_SID} is running."
    else
        echo "PMON process for ${ORACLE_SID} is not running. Exiting..."
        log "ERROR: PMON process for ${ORACLE_SID} is not running."
        conditional_mail mail_no_orcl
        exit 1
    fi
}

# Check Database Status with SQL*Plus
check_sqlplus() {
    log "Checking database operational status using SQL*Plus."
    db_status=$(sqlplus -s /nolog <<EOF
    --CONNECT ${ORACLE_USER}/${ORACLE_PASSWORD}@${ORACLE_SID}
    CONNECT \/ as sysdba
    SET HEADING OFF;
    SET FEEDBACK OFF;
    SELECT status FROM v\$instance;
    EXIT;
EOF
    )
    db_status=$(echo "$db_status" | xargs)
    if [[ "$db_status" != OPEN ]]; then
        echo "Oracle database is not available (Status: $db_status). Exiting..."
        log "ERROR: Oracle database is not available (Status: $db_status)"
	conditional_mail mail_no_orcl
        exit 1
    fi
    echo "Oracle database is available (Status: $db_status). Continuing..."
    log "Oracle database is available (Status: $db_status)"
}


# Function to perform RMAN backup
do_rman_backup() {
    local level=$1
    #local format_prefix=$2

    log "Starting RMAN level $level backup"
    rman target / log="$RmanLogFile" append <<_EOS_
crosscheck archivelog all;
crosscheck backup;
crosscheck backup of controlfile;
sql 'alter system switch logfile';
sql 'alter system archive log current';
sql 'alter system checkpoint';
run {
    backup incremental level $level database
    format '${RmanDir}/db_lvl${level}_%d_%I_${DATECODE2}_%U.rman'
    tag "${ORACLE_SID}_BAK_DB_${EXEC_SCRIPT_TIME}"
    plus archivelog not backed up delete input
    format '${RmanDir}/arc_%d_%I_${DATECODE2}_%U.rman'
    tag "${ORACLE_SID}_BAK_ARC_${EXEC_SCRIPT_TIME}";
}
crosscheck backup;
crosscheck backupset;
crosscheck archivelog all;
list expired backup;
list expired copy;
delete noprompt expired archivelog all;
delete noprompt expired backup;
delete noprompt obsolete;
delete force noprompt expired copy;
exit
_EOS_
}

# RMAN full hot backup

do_rman() {
	rman target / nocatalog @/home/oracle/scripts/rman_backup_hot_full.sql "${DATECODE1}" log "${RmanLogFile}"
	#/bin/find /home/oracle/scripts/logs/ -name "hot_rman*.log" -mtime +7 -exec rm {} \;
	#/bin/chmod -R 777 /backup/rman/*
	export Level=FULL
}

clean_log() {
	log "Starting Clean log"
	/bin/find ${LogDir} -type f -name "hot_rman*.log" -mtime +28 -exec rm {} \;
}

copybkp1() {
	mkdir -p "${RmanDir1}"
	$CP ${RmanDir}/* "${RmanDir1}"
	$CP "${RmanLogFile}" "${RmanDir1}"
	find ${RmanBaseDir1}/* -type d -ctime +1 -exec rm -rf {} +
}

copybkp2() {
	if [ "$DOM" = "01" ]; then
		mkdir -p "${RmanDir2}"
		$CP ${RmanDir}/* "${RmanDir2}"
		$CP ${LogDir}/hot_rman"$DATECODE".log "${RmanDir2}"
	fi
}

mail_error() {
	echo Log File Attached | /bin/mailx -r "${MailFrom}" -s "RMAN Level:${Level} !!!ERROR!!! Started ${DSUBJ} Running for ${SCR_TAKEN} ${ClientName} NEEDS YOUR ATTENTION" -a "${RmanLogFile}" "${MailList}"
}

mail_success() {
	echo Log File Attached | /bin/mailx -r "${MailFrom}" -s "RMAN Level:${Level} !!!SUCCESS!!! Started ${DSUBJ} Running for ${SCR_TAKEN} ${ClientName}" -a "${RmanLogFile}" "${MailList}"
}

mail_no_orcl() {
	echo Log File Attached | /bin/mailx -r "${MailFrom}" -s "ORACLE NOT RUNNING on ${ClientName}" -a "${RmanLogFile}" "${MailList}"
}

conditional_mail() {
    local mail_function="$1"  # The function to call (e.g., mail_error, mail_success)
    if [ "$USE_MAIL" = "Y" ]; then
        "$mail_function"  # Call the function passed as an argument
    fi
}

check_for_err() {
        if grep -q -i "rman-" "${RmanLogFile}"; then
                log "Error(s) detected in RMAN log."
		conditional_mail mail_error  # Only call mail_error if USE_MAIL = Y
        	#:
        else
                log "No errors detected in RMAN log."
		conditional_mail mail_success  # Only call mail_success if USE_MAIL = Y
        fi
}

#sleep 15
do_rman_incr() {
	#log "Starting RMAN incremental backup"
	do_rman_backup $Level
}

calculate_time() {
export RUN_HOURS=$((SECONDS / 3600))
export RUN_MINUTES=$(((SECONDS % 3600) / 60))
export RUN_REMAINING_SECONDS=$((SECONDS % 60))
SCR_TAKEN=$RUN_HOURS:$RUN_MINUTES:$RUN_REMAINING_SECONDS
echo $SCR_TAKEN
}

#do_rman
echo "rlvl:$rlvl"

main(){
do_rman_backup $Level
}

check_pmon
check_sqlplus
main
calculate_time
clean_log
check_for_err

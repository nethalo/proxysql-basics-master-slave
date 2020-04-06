#!/bin/bash
#
# Daniel Guzman Burgos <daniel.guzman.burgos@percona.com>
#

clear

set -o pipefail

# Initial values

lockFile="/var/lock/setup-server.lock"
errorFile="/var/log/setup-server.err"
logFile="/var/log/setup-server.log"
diskName="/dev/nvme1n1"
mountPoint="/data"
mysqlDir=${mountPoint}/mysql

# Function definitions

function destructor () {
        rm -f "$lockFile" 
}

# Setting TRAP in order to capture SIG and cleanup things
trap destructor EXIT INT TERM

function verifyExecution () {
        local exitCode="$1"
        local mustDie=${3-:"false"}
        if [ $exitCode -ne "0" ]
        then
                msg="[ERROR] Failed execution. ${2}"
                echo "$msg" >> ${errorFile}
                echo "$msg"
                if [ "$mustDie" == "true" ]; then
                        exit 1
                else
                        return 1
                fi
        fi
        return 0
}

function setLockFile () {
	echo "Setting the Lock File"	
    if [ -e "$lockFile" ]; then
            trap - EXIT INT TERM
            verifyExecution "1" "Script already running. $lockFile exists"
            exit 2
    else
            touch "$lockFile"
            rm -f "$errorFile" "$lockFile"
    fi
}

function logInfo (){
        echo "[$(date +%y%m%d-%H:%M:%S)] $1" >> $logFile
        echo "$1"
}

function addNVMeDisk () {
	
	echo "Adding the NMVe Disk"

	out=$(file -s $diskName 2>&1)
	if [[ $out == *"cannot"* ]]; then
		verifyExecution "1" "No $diskName disk available" true
	else
		logInfo "[OK] Found $diskName disk"
	fi

	out=$(mkfs -t xfs $diskName 2>&1)
    verifyExecution "$?" "Error formating disk with XFS. $out" true
    logInfo "[OK] XFS format to $diskName"

    out=$(mount $diskName /data 2>&1)
    verifyExecution "$?" "Error mounting $diskName disk to /data. $out" true
    logInfo "[OK] mounting $diskName disk to /data"
}

function setMySQLSymLinks () {
	
	out=$(mkdir -p /data/mysql 2>&1)
	verifyExecution "$?" "Can't create data dir /data/mysql. $out" true
	logInfo "[OK] /data/mysql created"

	out=$(ln -s /data/mysql /var/lib/mysql 2>&1)
	verifyExecution "$?" "Can't create symlink. $out" true
	logInfo "[OK] symklink /var/lib/mysql created"

	out=$(chmod -R 777 /data/mysql 2>&1)
	verifyExecution "$?" "Can't chmod 777 /data/mysql. $out" true
	logInfo "[OK] chmod 777 /data/mysql"

}

setLockFile
addNVMeDisk
setMySQLSymLinks

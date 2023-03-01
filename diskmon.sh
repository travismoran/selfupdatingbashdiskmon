#!/bin/bash
# set -x

ADMIN="root"
# set alert level 30% is default for testing
ALERT=30
# Exclude list of unwanted monitoring, if several partions then use "|" to separate the partitions.
# An example: EXCLUDE_LIST="/dev/hdd1|/dev/hdc5"
EXCLUDE_LIST="/snap|loop"
#
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#


VERSION="0.0.4"
### I'm storing the below variables in /etc/secrets/diskmon.env so they are not included in the public example, can use env vars in docker etc.
#slack_hook=""
#SCRIPT_URL=""
###
# source secrets
. /etc/secrets/diskmon.env
SCRIPT_DESCRIPTION="Disk Space Monitor"
SCRIPT_LOCATION="$0"

rm -f $(pwd)/updater.sh

update ()
{
    TMP_FILE=$(mktemp -p "" "XXXXX.sh")
    echo TMP_FILE= $TMP_FILE
    # future multi-script ipmlementation of SCRIPT_URL instead of absolute for each script
    #curl -s -L "$SCRIPT_URL$(basename $BASH_SOURCE)" > "$TMP_FILE"
    curl -s -L "$SCRIPT_URL" > "$TMP_FILE"
    echo TMP version= ; cat $TMP_FILE | grep -i "VERSION"
    NEW_VER=$(grep "^VERSION" "$TMP_FILE" | awk -F'[="]' '{print $3}')
    echo new_ver= $NEW_VER
    ABS_SCRIPT_PATH=$(readlink -f "$SCRIPT_LOCATION")
    echo abs= $ABS_SCRIPT_PATH

    if [ "$VERSION" \< "$NEW_VER" ]
    then
        printf "Updating script \e[31;1m%s\e[0m -> \e[32;1m%s\e[0m\n" "$VERSION" "$NEW_VER"

        echo "cp \"$TMP_FILE\" \"$ABS_SCRIPT_PATH\"" > updater.sh
        echo "rm -f \"$TMP_FILE\"" >> updater.sh
        echo "echo Running script again: `basename ${BASH_SOURCE[@]}` $@" >> updater.sh
        echo "exec \"$ABS_SCRIPT_PATH\" \"$@\"" >> updater.sh

        chmod +x updater.sh
        chmod +x "$TMP_FILE"
        exec $(pwd)/updater.sh
    else
        rm -f "$TMP_FILE"
    fi
}

update "$@" || getdisk

echo "$@"

# end updater portion

# begin disk monitor script
slack_alert () {

        message=$*

        [ ! -z "$message" ] && curl -X POST -H 'Content-type: application/json' --data "{
                      \"text\": \"${message}\"
              }" $slack_hook

}

scriptname () {
    script=/usr/local/bin/`basename "$0"`
}

gethostname () {
    monitor_host=`hostname -s`
}

getdisk () {
if [ "$EXCLUDE_LIST" != "" ] ; then
  df -H | grep -vE "^Filesystem|tmpfs|cdrom|${EXCLUDE_LIST}" | awk '{print $5 " " $6}' | main
else
  df -H | grep -vE "^Filesystem|tmpfs|cdrom" | awk '{print $5 " " $6}' | main
fi
}

main() {
while read -r output;
do
  scriptname
  gethostname

  usep=$(echo "$output" | awk '{ print $1}' | cut -d'%' -f1)
  partition=$(echo "$output" | awk '{print $2}')
  if [ $usep -ge $ALERT ] ; then
     echo  `echo "host: $monitor_host script: $script WARNING!!! Running out of space on filesystem: $partition capacity: ($usep%)"`
     slack_alert `echo "host: $monitor_host script: $script WARNING!!! Running out of space on filesystem: $partition capacity: ($usep%)"`
  fi
done
}
 
getdisk

#!/bin/sh
# set -x
# credit to https://gist.github.com/cubedtear/54434fc66439fc4e04e28bd658189701 for the updater portion
# credit to https://github.com/ruanyf/simple-bash-scripts/blob/master/scripts/disk-space.sh for disk space monitor example

# Reasoning for this script is to move towards a faas approach for cloud infrastructure with local copy to handle faas service outages.  I include a disk monitoring example at the bottom but my goal is to have the updater function be its own faas service and provide monitoring functions independently so there is a single source of truth and a single code base to update for all hosts in a cluster without the overhead of having to write ansible script and push updates manually.


ADMIN="root"
# set alert level 30% is default for testing
ALERT=30
# Exclude list of unwanted monitoring, if several partions then use "|" to separate the partitions.
# An example: EXCLUDE_LIST="/dev/hdd1|/dev/hdc5"
EXCLUDE_LIST="/snap|loop"
#
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#


VERSION="0.0.3"
### I'm storing the below variables in /etc/secrets/diskmon.sh so they are not included in the public example, can use env vars in docker etc.
#slack_hook=""
#SCRIPT_URL=""
###
# source secrets
. /etc/secrets/diskmon.sh
SCRIPT_DESCRIPTION="Disk Space Monitor"
SCRIPT_LOCATION="$0"

rm -f updater.sh

update ()
{
    TMP_FILE=$(mktemp -p "" "XXXXX.sh")
    curl -s -L "$SCRIPT_URL" > "$TMP_FILE"
    NEW_VER=$(grep "^VERSION" "$TMP_FILE" | awk -F'[="]' '{print $3}')
    ABS_SCRIPT_PATH=$(readlink -f "$SCRIPT_LOCATION")
    if [ "$VERSION" \< "$NEW_VER" ]
    then
        printf "Updating script \e[31;1m%s\e[0m -> \e[32;1m%s\e[0m\n" "$VERSION" "$NEW_VER"

        echo "cp \"$TMP_FILE\" \"$ABS_SCRIPT_PATH\"" > updater.sh
        echo "rm -f \"$TMP_FILE\"" >> updater.sh
        echo "echo Running script again: `basename ${BASH_SOURCE[@]}` $@" >> updater.sh
        echo "exec \"$ABS_SCRIPT_PATH\" \"$@\"" >> updater.sh

        chmod +x updater.sh
        chmod +x "$TMP_FILE"
        exec updater.sh
    else
        rm -f "$TMP_FILE"
    fi
}

update "$@"

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




#!/bin/bash
###
### Idea from
### http://wiki.kvs1.de/doku.php?id=pimp-fail2ban-with-blocklist.de
### https://github.com/TheAgentK/fail2ban_with_blocklist.de
###
 
### SERVICE: apache, bots, mail, imap, ftp, ssh oder voip, all
### With Default Values: ssh, mail, imap
### Requires a jail named <service>-blocklist
#service=${1-("ssh" "mail" "imap")}
#service=$1

if [ -z "$1" ]
then
   service=("apache" "ssh" "ftp" "mail" "imap" )
elif ! [ -z "$1" ]
then
  service=($1)
fi
 
### TIME: Unix time, hh:ii, hh.ii, difference in seconds
time=${2-3600}

mkdir -p /var/log/blocklist/

for i in "${service[@]}"
do
   :

	tmp=$(mktemp)
	 
	wget -qO $tmp "http://api.blocklist.de/getlast.php?service=$i&time=$time"
	 
	### Prepend date and time:
	### YYYY-MM-DD HH:II:SS : <IP>
	sed -i "s/^/$(date -Iseconds) : /g" $tmp
	 
	### Trigger fail2ban with new log file
	mv $tmp /var/log/blocklist/blocklist-$i.log
    echo ">>> /var/log/blocklist/blocklist-$i.log"
done
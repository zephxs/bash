#!/bin/bash
### 1.0 show current Wan IP + Geolocation from Duckduckgo
. /etc/profile.d/01-myecho-colors.sh
_BLU "######### IP DuckDuck Geoloc #########"
curl -s "https://duckduckgo.com/?q=ip+address" -o .tmpgeoloc
awk -F'Your IP address is |</a>","AnswerType":"ip",' '{print $2}' .tmpgeoloc |sed -r 's/<a href.*>//; s/\)//; s/\(//; s/,//g' |awk '{print "# IP        = "$1"\n# City      = "$3"\n# ZipCode   = "$6"\n# Province  = "$4"\n# Coutry    = "$5}'

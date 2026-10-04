#!/bin/bash
# bench/login.sh BASE COOKIE_JAR — sign in as david (the seed password) and keep the cookies.
B=$1; J=$2; rm -f $J
curl -s -c $J -b $J $B/session/new -o $J.login.html
T=$(grep -o 'name="_csrf_token" value="[^"]*"' $J.login.html | head -1 | sed 's/.*value="//;s/"//')
curl -s -c $J -b $J -o /dev/null -w 'login %{http_code}\n' -H "Origin: $B" --data-urlencode "_csrf_token=$T" --data-urlencode "email_address=david@37signals.com" --data-urlencode "password=secret123456" $B/session

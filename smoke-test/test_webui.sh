#!/bin/bash
set -o errexit
my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"

if [[ $ORCHESTRATOR == "openstack" ]] ; then
  source "$my_dir/../common/openrc"
  webui_ip=$(echo $OS_AUTH_URL | cut -d '/' -f3 | cut -d ':' -f 1)
else
  nodes=( $(echo $CONTROLLER_NODES | tr ',' ' ') )
  webui_ip=${nodes[0]}
fi

res=0
echo "INFO: check webui response on address $webui_ip:8143"
webui_page_size=`curl -I -k https://$webui_ip:8143/ 2>/dev/null | grep "Content-Length" | cut -d ' ' -f 2 | sed 's/\r$//'`
if (( webui_page_size < 1000 )) ; then
  echo "ERROR: response from port 8143 is smaller than 1000 bytes:"
  curl -I -k https://$webui_ip:8143/
  res=1
else
  echo "INFO: ok"
fi

exit $res

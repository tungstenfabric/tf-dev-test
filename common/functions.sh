#!/bin/bash

function wait_cmd_success() {
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-300}
  local silent=${4:-1}
  local i=0
  while ! eval "$cmd" 2>/dev/null; do
      if [[ "$silent" != "0" ]]; then
        printf "."
      fi
      i=$((i + 1))
      if (( i > max )) ; then
        return 1
      fi
      sleep $interval
  done
  return 0
}

function run_container() {
  local name=$1
  local image$2
  shift 2
  local opts=$@
  docker run --name $name -it --rm --network host --privileged \
    -e WORKSPACE=$WORKSPACE \
    -v $WORKSPACE:$WORKSPACE \
    -v "/var/run:/var/run" \
    $opts $image
  return $?
}
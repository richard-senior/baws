#!/bin/bash


#############
### DEBUG
#############

function bawsDebug {
    if [ ! -z "$BAWS_DEBUG" ]; then
        if [ "$BAWS_DEBUG"==1 ]; then
          set -x
          trap read debug
          return 0
        fi
    fi
    set +x
}

#############
### LOGGING
#############

function bawsWarn {
  RED="\e[31m"
  ENDCOLOR="\e[0m"
  if [ -z "$1" ]; then
     echo "must supply message in first parameter"
     return 1
  fi
  echo -e "$RED$1$ENDCOLOR"
}

function bawsLog {
  if [ -z "$1" ]; then
     echo "must supply message in first parameter"
     return 1
  fi
   echo ""
   echo "------- BAWS --------"
   echo " $1"
   echo "---------------------"
   echo ""
}

#############
### AWS
#############

function isCanConnect {
    local foo=$(aws --profile $PROFILE --region $REGION sts get-caller-identity 2>/dev/null | grep "UserId")
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    return 0
}

#############
### INTERNET
#############

function httpServerExists {
  if [ -z "$1" ]; then
     echo "must supply a url to check, in the first parameter"
     return 1
  fi
  curl --output /dev/null --silent --head --fail "$1"
  if [ $? -ne  0 ]; then
    return 1
  else
    return 0
  fi
}

function getExternalIP {
  local ip=$(curl -s http://whatismyip.akamai.com/)
  if [ -z "$ip" ]; then
    return
  fi
  echo "$ip"
}

function isValidCidrRange {
  if [ -z "$1" ]; then
     echo "must supply a cidr range in the first parameter"
     return 1
  fi
  # Parse "a.b.c.d/n" into five separate variables
  IFS="./" read -r ip1 ip2 ip3 ip4 N <<< "$1"
  # Convert IP address from quad notation to integer
  ip=$(($ip1 * 256 ** 3 + $ip2 * 256 ** 2 + $ip3 * 256 + $ip4))
  # Remove upper bits and check that all $N lower bits are 0
  if [ $(($ip % 2**(32-$N))) = 0 ]; then
    return 0 # CIDR OK!
  else
    return 1 # CIDR NOT OK!
  fi
}

function isIpValid {
  if [ -z "$1" ]; then
    echo "must supply a ip to check, in the first parameter"
    return 1
  fi
  local  ip=$1
  local  stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      OIFS=$IFS
      IFS='.'
      ip=($ip)
      IFS=$OIFS
      [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
          && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
      stat=$?
  fi
  return $stat
}

function getDate {
    date=$(wget -qSO- --max-redirect=0 google.com 2>&1 | grep Date: | cut -d' ' -f5-8)
    echo "$date"
}

#############
### OS
#############

function isServiceRunning {
    if [ -z "$1" ]; then
      echo "must supply the name of the service in the first parameter"
      return 1
    fi
    if isDocker; then
      local foo=$(service $1 status)
    else
      local foo=$(sudo service $1 status)
    fi
    if [[ -z "$foo" ]]; then
      return 1
    fi
    if [[ $foo == *"running"* ]]; then
      return 0
    fi
    return 1
}

function isServiceInstalled() {
    if [ -z "$1" ]; then
      echo "must supply the name of the service in the first parameter"
      return 1
    fi
    if isDocker; then
      local foo=$(service $1 status)
    else
      local foo=$(sudo service $1 status)
    fi
    if [ -z "$foo" ]; then
      return 1
    fi
    if [[ $foo == *"unrecognized"* ]]; then
      return 1
    fi
    return 0
}

function isApplicationInstalled() {
    if [ -z "$1" ]; then
      echo "must supply the name of the command in the first parameter"
      return 1
    fi
    if [ -z "$(command -v $1)" ]; then
        return 1
    else
        return 0
    fi
}

function isRoot {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
  fi
}

#### OS

function isWsl {
  local foo=$(cat /proc/version)
  if [ "$foo" == *"Microsoft"* ]; then
    return 0
  else
    return 1
  fi
}

#############
### DOCKER
#############

function isDocker {
  if [ -f /.dockerenv ]; then
      return 0
  else
      return 1
  fi
}

function isDockerContainerIsRunning {
    if [ -z "$1" ]; then
      echo "must supply the name of the container in the first parameter"
      return 1
    fi
    local name="^$1\$"
    local foo=$(docker container ls --filter name="$name" --format '{{.Image}}')
    if [ -z "$foo" ] || [ "$foo" != "$1" ]; then
        return 1
    else
        return 0
    fi
}

#true if the container named in the passed parameter exists
#whether it is running or otherwise
function isDockerContainerExists {
    if [ -z "$1" ]; then
      echo "must supply the name of the container in the first parameter"
      return 1
    fi
    local foo=$(docker ps -a --filter name=^ps_dev_env$ --format '{{.Image}}')
    if [ -z "$foo" ] || [ "$foo" != "$1" ]; then
        return 1
    else
        return 0
    fi
}

function isDockerImageExists {
    if [ -z "$1" ]; then
      echo "must supply the name of the image in the first parameter"
      return 1
    fi
    local foo=$(docker images -q $1)
    if [ -z "$foo" ]; then
        return 1
    else
        return 0
    fi
}

function optionallyDeleteLocalDockerImage {
    if [ -z "$1" ]; then
      echo "must supply the name of the image in the first parameter"
      return 1
    fi
    if isDockerImageExists "$1"; then
        read -p "Delete existing image : $1 ?? (y/n) " yn
        if [ "$yn" == "y" ] || [ "$yn" == "Y" ]; then
          if isDockerContainerIsRunning $1; then
            docker container stop $1
            docker container rm $1
          fi
          docker image rm $1
          docker system prune -f
        fi
    fi
}

function optionallyRemoveDockerContainer {
    if [ -z "$1" ]; then
      echo "must supply the name of the container in the first parameter"
      return 1
    fi
    if isDockerContainerExists "$1"; then
      read -p "Delete existing container : $1 ?? (y/n) " yn
      if [ "$yn" == "y" ] || [ "$yn" == "Y" ]; then
            docker system prune -f
            docker stop $1
            docker rm $1
      fi
    fi
}


#############
### STRINGS
#############

# very simple and flaky string replacement
# echo's back the replaced string
#$1 : target string
#$2 : search term
#$3 : replacement
function stringReplace() {
    printf "%s" "${1/"$2"/$3}"
}

function isNumeric {
  re='^[0-9]+$'
  if [[ $1 =~ $re ]] ; then
    return 0
  else
    return 1
  fi
}

function replaceEnvFileValue {
    if [ -z "$1" ]; then
        echo "you must supply the property name in the first parameter"
        return
    fi
    if [ -z "$2" ]; then
        echo "you must supply the property value for $1 in the second parameter"
        return
    fi
    sed -i '' "s|^$1=.*|$1=\"$2\"|" ./.env
}
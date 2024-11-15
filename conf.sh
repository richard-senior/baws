#!/bin/bash

############################################################
## BAWS Bash AWS
############################################################
## This library is intended as a quick and dirty way of
## implementing IAC code for AWS infrastructure
## Usually people will use cloudformation or terraform but
## both of those solutions have issues with 'state management'
## BAWS has a concept of looking to see if something exists
## before trying to create it or delete it which means
## re-running 'create' on most resources will not cause
## errors with 'already exists' etc.
## See the readme for more information
############################################################

# conf.sh is sourced by every other script in BAWS
# this is where we set the vpc or account we're working on
# etc. Users of baws should begin by either hardcoding their
# values in this file, or by setting environment variables
# immediately after sourcing a BAWS resource file
# See README for more information

# by default we disable aws response paging as this
# will prevent some commands from completing
export AWS_PAGER=""

# Set an environment variable ONLY IF it doesn't already exist
# This allows users of
function setEnvVar {
  if [ -z "$1" ]; then
     echo "must supply the name of the environment variable in the first parameter"
     return 1
  fi
  if [ -z "$2" ]; then
     echo "must supply the value of the enivonrment variable in the second parameter"
     return 1
  fi
  if [ ! -z "$1" ]; then return 1; fi
  export "$1"="$2"
}

setEnvVar "PROFILE" "npt"
setEnvVar "REGION" "eu-west-1"
setEnvVar "VPCNAME" "pet-servers"
setEnvVar "VPCID" "vpc-05dad00e9bf6294f8"
setEnvVar "ENVIRONMENT" "rms"
setEnvVar "STACK" "devlake"
setEnvVar "PLATFORM" "$VPCNAME"
setEnvVar "USERNAME" "richard.senior"
setEnvVar "OWNER" "ee-platform-services"


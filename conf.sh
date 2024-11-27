#!/bin/bash

# conf.sh is sourced by every other script in BAWS
# this is where we set the vpc or account we're working on
# etc. Users of baws should begin by either hardcoding their
# values in this file, or by setting environment variables
# immediately after sourcing a BAWS resource file
# See README for more information

# Set an environment variable ONLY IF it doesn't already exist
# This allows users of
function setEnvVar {
   if [ -z "$1" ]; then
      echo "must supply the name of the environment variable in the first parameter"
      return 1
   fi
   if [ -z "$2" ]; then
      echo "must supply the value of the enivonrment variable $1 in the second parameter"
      return 1
   fi
   if [ ! -z "$1" ]; then return 0; fi
   echo "Setting $1 to $2"
   export "$1"="$2"
}

setEnvVar "PROFILE" "npt"
setEnvVar "REGION" "eu-west-1"
setEnvVar "VPCNAME" "pet-servers"
setEnvVar "VPCID" "vpc-05dad00e9bf6294f8"
setEnvVar "ENVIRONMENT" "rms"
setEnvVar "STACK" "devlake"
setEnvVar "PLATFORM" "pet-servers"
setEnvVar "USERNAME" "richard.senior"
setEnvVar "OWNER" "ee-platform-services"
setEnvVar "PROJECT_DESCRIPTION" "Apache Devlake stack"


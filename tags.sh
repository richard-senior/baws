#!/bin/bash

source ./conf.sh

########################################################################
### TAGS           #####################################################
########################################################################


function getTagsRaw {
    if [ -z "$1" ]; then
       echo "You must supply resource NAME (ie my-ec2-instance) in the first parameter"
       exit 1
    fi
    local ret="Key=name,Value=$1 Key=environment-name,Value=${ENVIRONMENT} Key=user,Value=$USERNAME Key=platform-name,Value=$PLATFORM Key=stack-name,Value=$STACK Key=owner,Value=$OWNER"
    echo "$ret"
}

function getTags {
    if [ -z "$1" ]; then
       echo "You must supply NAME in the first parameter"
       exit 1
    fi
    local ret="[{\"Key\":\"name\",\"Value\":\"$1\"},{\"Key\":\"environment-name\",\"Value\":\"$ENVIRONMENT\"},{\"Key\":\"user\",\"Value\":\"$USERNAME\"},{\"Key\":\"platform-name\",\"Value\":\"$PLATFORM\"},{\"Key\":\"stack-name\",\"Value\":\"$STACK\"},{\"Key\":\"owner\",\"Value\":\"$OWNER\"}]"
    echo "$ret"
}

function getTagSpecifications {
    if [ -z "$1" ]; then
       echo "You must supply NAME in the first parameter"
       exit 1
    fi
    local ret="ResourceType=$1,Tags=[{Key=Name,Value=$1},{Key=stack-name,Value=$STACK},{Key=environment-name,Value=$ENVIRONMENT},{Key=user,Value=$USERNAME},{Key=platform-name,Value=$PLATFORM},{Key=owner,Value=$OWNER}]"
    echo "$ret"
}